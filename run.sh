#!/bin/sh
# run.sh
# 交互式部署向导：收集缺失配置 → 生成 Secret → 渲染 config.yaml →
# 打印访问信息 → 确认后执行 docker compose up -d
#
# 本脚本不重复实现逻辑，只负责收集信息并依次调用 scripts/ 下的脚本。

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ROOT}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 找不到 .env 文件: $ENV_FILE"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ 未找到 docker 命令，请先安装 Docker / docker compose 插件"
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

echo "======================================"
echo " Mihomo Proxy 部署向导"
echo "======================================"
echo ""

# ── 1. 订阅链接 ──────────────────────────────────────────────
if [ -z "$SUBSCRIPTION_URL" ]; then
  printf "请输入订阅链接: "
  read -r INPUT_SUB
  if [ -z "$INPUT_SUB" ]; then
    echo "❌ 订阅链接不能为空"
    exit 1
  fi
  ESCAPED_SUB=$(printf '%s' "$INPUT_SUB" | sed 's/[&]/\\&/g')
  sed -i "s|^SUBSCRIPTION_URL=.*|SUBSCRIPTION_URL=\"${ESCAPED_SUB}\"|" "$ENV_FILE"
  SUBSCRIPTION_URL="$INPUT_SUB"
  echo "✅ 已写入 .env"
else
  echo "订阅链接：已配置（如需更换，直接编辑 .env 的 SUBSCRIPTION_URL 后重新运行本脚本）"
fi
echo ""

# ── 2. 路由器局域网 IP ────────────────────────────────────────
printf "当前 HOST_IP=%s，需要修改就输入新值，直接回车跳过: " "$HOST_IP"
read -r INPUT_IP
if [ -n "$INPUT_IP" ]; then
  sed -i "s|^HOST_IP=.*|HOST_IP=${INPUT_IP}|" "$ENV_FILE"
  HOST_IP="$INPUT_IP"
  echo "✅ 已更新 HOST_IP"
fi
echo ""

# ── 3. API Secret ────────────────────────────────────────────
if [ -z "$SECRET" ]; then
  printf "请输入自定义 API Secret（直接回车则自动生成随机值）: "
  read -r INPUT_SECRET
  if [ -n "$INPUT_SECRET" ]; then
    ESCAPED_SECRET=$(printf '%s' "$INPUT_SECRET" | sed 's/[&]/\\&/g')
    sed -i "s|^SECRET=.*|SECRET=${ESCAPED_SECRET}|" "$ENV_FILE"
    SECRET="$INPUT_SECRET"
    echo "✅ 已写入自定义 Secret"
  else
    echo "🔑 未输入，自动生成随机 Secret..."
    sh "${ROOT}/scripts/generate-secret.sh"
    set -a
    . "$ENV_FILE"
    set +a
  fi
else
  echo "Secret：已配置"
fi
echo ""

# ── 4. 渲染 config.yaml ──────────────────────────────────────
echo "⚙️  生成 config/config.yaml..."
sh "${ROOT}/scripts/apply-config.sh"
echo ""

# 重新加载 .env，确保下面展示的是最新值
set -a
. "$ENV_FILE"
set +a

# ── 5. 打印访问信息 ──────────────────────────────────────────
echo "======================================"
echo " 部署信息一览"
echo "======================================"
echo "Zashboard 管理面板:     http://${HOST_IP}:${DASHBOARD_PORT}"
echo "Mihomo API:             http://${HOST_IP}:${API_PORT}"
echo "SubConverter 转换面板:  http://${HOST_IP}:${SUBCONVERTER_PORT}/dashboard"
echo "API / Dashboard Secret: ${SECRET}"
echo ""
echo "客户端代理地址:"
echo "  Mixed:   ${HOST_IP}:${MIXED_PORT}"
echo "  SOCKS5:  ${HOST_IP}:${SOCKS_PORT}"
echo "  HTTP:    ${HOST_IP}:${HTTP_PORT}"
echo "  DNS:     ${HOST_IP}:${DNS_PORT}（Fake-IP，可选）"
echo "======================================"
echo ""

# ── 6. 确认启动 ──────────────────────────────────────────────
printf "是否现在执行 docker compose up -d 启动服务？[y/N] "
read -r CONFIRM
if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
  cd "$ROOT"
  docker compose up -d
  echo ""
  echo "✅ 服务已启动，上方链接现已可用"
  docker compose ps
else
  echo "已跳过启动，之后可手动运行: cd ${ROOT} && docker compose up -d"
fi
