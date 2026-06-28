#!/bin/sh
# restore.sh
# 从备份文件恢复 config / providers / .env

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
BACKUP_DIR="${ROOT}/backup"

# 列出可用备份
echo "📋 可用备份："
ls -t "${BACKUP_DIR}"/mihomo_backup_*.tar.gz 2>/dev/null || {
  echo "❌ 没有找到任何备份文件"
  exit 1
}

echo ""
# 如果传入了参数则使用，否则自动选择最新备份
if [ -n "$1" ]; then
  ARCHIVE="$1"
else
  ARCHIVE=$(ls -t "${BACKUP_DIR}"/mihomo_backup_*.tar.gz | head -1)
  echo "未指定备份文件，将恢复最新备份: $(basename "$ARCHIVE")"
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "❌ 找不到备份文件: $ARCHIVE"
  exit 1
fi

echo ""
printf "⚠️  此操作将覆盖当前 config / providers / .env，是否继续？[y/N] "
read -r CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "已取消。"
  exit 0
fi

# 停止服务
echo "⏹  停止 Docker Compose 服务..."
cd "$ROOT" && docker compose down 2>/dev/null || true

# 解压
TMPDIR=$(mktemp -d)
tar -xzf "$ARCHIVE" -C "$TMPDIR"
EXTRACTED=$(ls "$TMPDIR")

# 恢复文件
echo "♻️  恢复文件..."
rm -rf "${ROOT}/config" "${ROOT}/providers"
cp -r "${TMPDIR}/${EXTRACTED}/config"    "${ROOT}/config"
cp -r "${TMPDIR}/${EXTRACTED}/providers" "${ROOT}/providers"
cp    "${TMPDIR}/${EXTRACTED}/.env"      "${ROOT}/.env"
rm -rf "$TMPDIR"

echo "✅ 恢复完成"
echo "▶️  启动服务: cd ${ROOT} && docker compose up -d"
