#!/bin/sh
# apply-config.sh
# 从 .env 读取配置，自动检测订阅可用性，渲染 config.yaml.template → config.yaml
#
# 逻辑：
#   1. 用 User-Agent: mihomo 请求订阅链接
#   2. 返回内容包含 "proxies:" 字段 → 直接使用原链接
#   3. 不包含 → 通过 subconverter 转换后使用

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

# ── 检测订阅内容是否 Mihomo 可用 ───────────────────────────
echo "🔍 正在检测订阅链接可用性（UA: mihomo）..."

PROBE=$(curl -sS \
  --max-time 15 \
  --user-agent "mihomo" \
  "$SUBSCRIPTION_URL" 2>/dev/null | head -c 4096) || true

if echo "$PROBE" | grep -q "proxies:"; then
  # 直接可用
  FINAL_URL="$SUBSCRIPTION_URL"
  echo "✅ 订阅内容为 Mihomo 可用格式，直接使用原链接"
else
  # 需要转换
  echo "⚠️  订阅内容不包含 proxies: 字段，自动切换到 subconverter 转换"

  SUBCONVERTER_BASE="${SUBCONVERTER_URL:-https://api.v1.mk}"

  # URL 编码订阅链接（编码特殊字符，保留协议头的 :// 不动）
  ENCODED_URL=$(printf '%s' "$SUBSCRIPTION_URL" | sed \
    -e 's/%/%25/g' \
    -e 's/ /%20/g' \
    -e 's/&/%26/g' \
    -e 's/+/%2B/g' \
    -e 's/=/%3D/g' \
    -e 's/?/%3F/g' \
    -e 's/#/%23/g')

  # target=clash + list=true：输出纯节点列表，适合 proxy-providers 使用
  FINAL_URL="${SUBCONVERTER_BASE}/sub?target=clash&list=true&url=${ENCODED_URL}"
  echo "   转换后端: ${SUBCONVERTER_BASE}"

  # 验证转换结果
  echo "🔍 验证转换结果..."
  CONVERTED_PROBE=$(curl -sS \
    --max-time 20 \
    --user-agent "mihomo" \
    "$FINAL_URL" 2>/dev/null | head -c 4096) || true

  if echo "$CONVERTED_PROBE" | grep -q "proxies:"; then
    echo "✅ 转换成功，订阅可用"
  else
    echo "❌ 转换后内容仍不包含 proxies: 字段，请检查："
    echo "   - SUBSCRIPTION_URL 是否正确"
    echo "   - SUBCONVERTER_URL 后端是否可访问"
    echo "   - 可尝试在浏览器访问: ${FINAL_URL}"
    echo ""
    echo "   当前仍会写入 config.yaml，但 Mihomo 启动后节点可能为空。"
  fi
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
