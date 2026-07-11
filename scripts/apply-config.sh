#!/bin/sh
# apply-config.sh
# 从 .env 读取配置，自动检测订阅可用性，渲染 config.yaml.template → config.yaml
#
# 逻辑：
#   1. 用 User-Agent: mihomo 请求订阅链接，取回原始内容
#   2. 内容包含 "proxies:" 字段 → Mihomo 可直接使用，原样使用该链接
#   3. 不包含 → 按节点链接列表解析（必要时 base64 解码），
#      把解析出的节点链接交给本地 SubConverter-Extended 转换成 proxies: 列表。
#      SubConverter-Extended 不会主动连接远程订阅服务器，所以这一步必须由本脚本
#      先把订阅内容取回来，再把节点链接喂给它——不能直接把订阅 URL 转发过去。
#
# 注意：走第 3 种情况时，节点列表是本次运行时的静态快照，不会随机场后台更新自动
# 刷新，需要重新运行本脚本（或 update.sh）才能同步最新节点。

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
ENV_FILE="${ROOT}/.env"
TEMPLATE="${ROOT}/config/config.yaml.template"
OUTPUT="${ROOT}/config/config.yaml"

# ── 读取 .env ──────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 找不到 .env 文件: $ENV_FILE"
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# ── 检查必填项 ─────────────────────────────────────────────
if [ -z "$SUBSCRIPTION_URL" ]; then
  echo "❌ 请先在 .env 中填写 SUBSCRIPTION_URL"
  exit 1
fi

if [ -z "$SECRET" ]; then
  echo "❌ SECRET 为空，请先运行: sh scripts/generate-secret.sh"
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "❌ 找不到配置模板: $TEMPLATE"
  exit 1
fi

SUBCONVERTER_BASE="http://127.0.0.1:${SUBCONVERTER_PORT:-25500}"
NODE_SCHEME_RE='(vmess|vless|trojan|ss|ssr|hysteria2?|hy2|tuic|anytls)://'

# ── 抓取订阅原始内容 ───────────────────────────────────────
echo "🔍 正在检测订阅链接可用性（UA: mihomo）..."

RAW_BODY=$(curl -sSL --compressed --max-time 15 --user-agent "mihomo" "$SUBSCRIPTION_URL" 2>/dev/null) || true

if [ -z "$RAW_BODY" ]; then
  echo "❌ 无法获取订阅内容，请检查 SUBSCRIPTION_URL 或网络连接"
  exit 1
fi

PROBE=$(printf '%s' "$RAW_BODY" | head -c 4096)

if echo "$PROBE" | grep -q "proxies:"; then
  # ── 情况一：Mihomo 可直接使用 ──────────────────────────────
  FINAL_URL="$SUBSCRIPTION_URL"
  echo "✅ 订阅内容为 Mihomo 可用格式，直接使用原链接"
else
  # ── 情况二：解析节点链接，交给本地 SubConverter-Extended 转换 ──
  echo "⚠️  订阅内容不包含 proxies: 字段，尝试解析为节点链接列表"

  if printf '%s' "$RAW_BODY" | grep -qE "$NODE_SCHEME_RE"; then
    # 已经是明文节点链接列表，无需 base64 解码
    NODE_LIST="$RAW_BODY"
  else
    # 常见的通用订阅格式：整体是 base64，解码后每行一条节点链接
    # 不少订阅服务器返回时会省略末尾的 = padding，这里先补齐再解码
    B64=$(printf '%s' "$RAW_BODY" | tr -d ' \t\r\n')
    MOD=$((${#B64} % 4))
    if [ "$MOD" -eq 2 ]; then
      B64="${B64}=="
    elif [ "$MOD" -eq 3 ]; then
      B64="${B64}="
    fi

    if command -v base64 >/dev/null 2>&1; then
      NODE_LIST=$(printf '%s' "$B64" | base64 -d 2>/dev/null) || NODE_LIST=""
    elif command -v openssl >/dev/null 2>&1; then
      NODE_LIST=$(printf '%s' "$B64" | openssl base64 -d -A 2>/dev/null) || NODE_LIST=""
    else
      echo "❌ 系统缺少 base64 / openssl 命令，无法解码订阅内容"
      echo "   OpenWrt 上尝试: opkg update && opkg install coreutils-base64"
      exit 1
    fi
  fi

  NODE_COUNT=$(printf '%s\n' "$NODE_LIST" | grep -cE "$NODE_SCHEME_RE" || true)

  if [ "$NODE_COUNT" -eq 0 ]; then
    echo "❌ 订阅内容既不是 Mihomo 可用格式，也无法解析出节点链接"
    echo "   请检查 SUBSCRIPTION_URL 是否正确，或该订阅格式暂不支持自动解析"
    exit 1
  fi

  echo "   解析到 ${NODE_COUNT} 条节点链接，交由本地 SubConverter-Extended 转换"
  echo "🔍 正在请求本地 SubConverter-Extended（${SUBCONVERTER_BASE}）..."

  JOINED_LINKS=$(printf '%s\n' "$NODE_LIST" | grep -E "$NODE_SCHEME_RE" | tr '\n' '|' | sed 's/|$//')

  # 用 curl 自身完成正确的 URL 编码（历史上手写 sed 编码遗漏了 @ : 等字符），
  # -w '%{url_effective}' 拿到编码后实际请求的完整地址，直接写入 config.yaml
  CONVERTED_URL=$(curl -sS -G "${SUBCONVERTER_BASE}/sub" \
    --max-time 20 \
    --data-urlencode "target=clash" \
    --data-urlencode "list=true" \
    --data-urlencode "url=${JOINED_LINKS}" \
    -o /dev/null -w '%{url_effective}' 2>/dev/null) || true

  if [ -z "$CONVERTED_URL" ]; then
    echo "❌ 无法连接本地 SubConverter-Extended（${SUBCONVERTER_BASE}）"
    echo "   请确认 subconverter 容器已启动：docker compose ps"
    exit 1
  fi

  # 验证转换结果确实包含节点
  CONVERTED_PROBE=$(curl -sSL --max-time 20 "$CONVERTED_URL" 2>/dev/null | head -c 4096) || true

  if echo "$CONVERTED_PROBE" | grep -q "proxies:" && ! echo "$CONVERTED_PROBE" | grep -qE "proxies:[[:space:]]*\[\]"; then
    echo "✅ 转换成功，共 ${NODE_COUNT} 个节点"
  else
    echo "❌ 转换后未获取到节点，请访问以下地址排查："
    echo "   ${CONVERTED_URL}"
    echo ""
    echo "   当前仍会写入 config.yaml，但 Mihomo 启动后节点可能为空。"
  fi

  FINAL_URL="$CONVERTED_URL"

  echo ""
  echo "ℹ️  节点列表为本次运行时的静态快照，不会随机场后台更新自动刷新。"
  echo "   如需同步最新节点：sh scripts/update.sh"
fi

# ── 渲染模板 ───────────────────────────────────────────────
# sed 对 / 需要转义（URL 中含大量 /）：改用 | 作为分隔符
ESCAPED_URL=$(printf '%s' "$FINAL_URL" | sed 's/[&]/\\&/g')
ESCAPED_SECRET=$(printf '%s' "$SECRET" | sed 's/[&]/\\&/g')

sed \
  -e "s|__CONVERTED_URL__|${ESCAPED_URL}|g" \
  -e "s|__SECRET__|${ESCAPED_SECRET}|g" \
  "$TEMPLATE" > "$OUTPUT"

echo "✅ config/config.yaml 已生成"
echo ""
echo "   订阅 URL: ${FINAL_URL}"
echo "   如需查看完整配置: cat config/config.yaml"
