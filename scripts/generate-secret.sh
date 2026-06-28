#!/bin/sh
# generate-secret.sh
# 自动生成随机 SECRET 并写入 .env 文件

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 找不到 .env 文件: $ENV_FILE"
  exit 1
fi

# 生成 32 位随机 hex 字符串
SECRET=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)

# 写入 .env（替换 SECRET= 行）
if grep -q "^SECRET=" "$ENV_FILE"; then
  sed -i "s|^SECRET=.*|SECRET=${SECRET}|" "$ENV_FILE"
else
  echo "SECRET=${SECRET}" >> "$ENV_FILE"
fi

echo "✅ SECRET 已写入 .env"
echo "   SECRET=${SECRET}"
echo ""
echo "👉 记得运行 sh scripts/apply-config.sh 重新生成 config.yaml"
