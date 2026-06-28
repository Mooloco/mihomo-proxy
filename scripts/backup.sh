#!/bin/sh
# backup.sh
# 备份 config / providers / .env 到 backup/ 目录

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${ROOT}/backup/mihomo_backup_${TIMESTAMP}"

mkdir -p "$BACKUP_DIR"

echo "📦 开始备份..."

# 备份配置
cp -r "${ROOT}/config"    "${BACKUP_DIR}/config"
cp -r "${ROOT}/providers" "${BACKUP_DIR}/providers"
cp    "${ROOT}/.env"      "${BACKUP_DIR}/.env"

# 打包为 tar.gz
ARCHIVE="${ROOT}/backup/mihomo_backup_${TIMESTAMP}.tar.gz"
tar -czf "$ARCHIVE" -C "${ROOT}/backup" "mihomo_backup_${TIMESTAMP}"
rm -rf "$BACKUP_DIR"

echo "✅ 备份完成: ${ARCHIVE}"

# 仅保留最近 5 个备份
cd "${ROOT}/backup"
ls -t mihomo_backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
echo "🗑  旧备份已清理（保留最新 5 个）"
