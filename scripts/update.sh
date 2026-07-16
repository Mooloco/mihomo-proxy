#!/bin/sh
# update.sh
# 拉取最新镜像并重启服务

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

cd "$ROOT"
rm -f providers/proxy/subscription.yaml

echo "🔄 重新生成配置..."
sh scripts/apply-config.sh

echo ""
echo "🔄 拉取最新镜像..."
docker compose pull

echo "🚀 重启服务..."
docker compose up -d

echo "✅ 更新完成"
echo ""
echo "📋 当前容器状态："
docker compose ps
