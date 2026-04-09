#!/bin/bash
set -e

echo "[Init] Starting Vaultwarden OSS Sync Setup..."

mkdir -p /root/.config/rclone

# 基础 rclone 配置
cat > /root/.config/rclone/rclone.conf <<EOF
[backend]
EOF

if [ "$STORAGE_TYPE" = "s3" ]; then
    echo "[Init] Configuring S3 Backend..."
    cat >> /root/.config/rclone/rclone.conf <<EOF
type = s3
provider = Other
env_auth = false
access_key_id = ${S3_ACCESS_KEY}
secret_access_key = ${S3_SECRET_KEY}
endpoint = ${S3_ENDPOINT}
region = ${S3_REGION:-us-east-1}
EOF
    REMOTE_DIR="backend:${S3_BUCKET}/${S3_PATH:-vaultwarden}"
elif [ "$STORAGE_TYPE" = "webdav" ]; then
    echo "[Init] Configuring WebDAV Backend..."
    cat >> /root/.config/rclone/rclone.conf <<EOF
type = webdav
url = ${WEBDAV_URL}
vendor = ${WEBDAV_VENDOR:-other}
user = ${WEBDAV_USER}
pass = $(rclone obscure "${WEBDAV_PASS}")
EOF
    REMOTE_DIR="backend:${WEBDAV_PATH:-vaultwarden}"
else
    echo "[Error] STORAGE_TYPE must be 's3' or 'webdav'."
    exit 1
fi

# 设置加密层
if [ -n "$ENCRYPT_PASSWORD" ]; then
    echo "[Init] Configuring Encryption Layer..."
    cat >> /root/.config/rclone/rclone.conf <<EOF
[crypt]
type = crypt
remote = ${REMOTE_DIR}
password = $(rclone obscure "${ENCRYPT_PASSWORD}")
EOF
    if [ -n "$ENCRYPT_SALT" ]; then
        echo "password2 = $(rclone obscure "${ENCRYPT_SALT}")" >> /root/.config/rclone/rclone.conf
    fi
    REMOTE_TARGET="crypt:"
else
    REMOTE_TARGET="${REMOTE_DIR}"
fi

export REMOTE_TARGET

echo "[Init] Restoring data from remote: ${REMOTE_TARGET} to /data/"
# 从远端恢复数据，如果失败不报错，可能首次运行或者远端空
rclone copy "${REMOTE_TARGET}" /data/ -v || echo "[Init] Warn: First run or remote is empty. Skipping restore."

# 如果是全新启动且恢复到了备份快照，但主数据库文件不存在，则用快照初始化
if [ ! -f /data/db.sqlite3 ] && [ -f /data/db_backup.sqlite3 ]; then
    echo "[Init] Restoring db.sqlite3 from db_backup.sqlite3 snapshot..."
    cp -a /data/db_backup.sqlite3 /data/db.sqlite3
fi

# 生成并启动后台同步脚本
INTERVAL=${SYNC_INTERVAL:-5}
cat > /sync.sh <<EOF
#!/bin/bash
while true; do
    sleep \$(( ${INTERVAL} * 60 ))
    echo "[\$(date)] Creating SQLite hot-backup snapshot..."
    sqlite3 /data/db.sqlite3 ".backup /data/db_backup.sqlite3"
    
    echo "[\$(date)] Auto-syncing data from /data/ to ${REMOTE_TARGET}..."
    rclone sync /data/ "${REMOTE_TARGET}" \\
      --exclude "db.sqlite3" \\
      --exclude "db.sqlite3-wal" \\
      --exclude "db.sqlite3-shm" \\
      -v
done
EOF
chmod +x /sync.sh

echo "[Init] Starting background sync process (Interval: ${INTERVAL}m)..."
/sync.sh &

echo "[Init] Starting Vaultwarden..."
# Delegate to standard vaultwarden startup script if it exists
if [ -x /start.sh ]; then
    exec /start.sh "$@"
else
    exec vaultwarden "$@"
fi
