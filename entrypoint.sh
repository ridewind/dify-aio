#!/bin/bash
set -e

# 处理SSH配置
if [ -n "$SSH_PASSWORD" ]; then
    echo "root:$SSH_PASSWORD" | chpasswd
fi

# 检测环境变量SSH_IDENTITY_FILE，如果变量存在且文件存在，则将其添加到authorized_keys中
if [ -n "$SSH_IDENTITY_FILE" ] && [ -f "$SSH_IDENTITY_FILE" ]; then
    cat "$SSH_IDENTITY_FILE" >> /root/.ssh/authorized_keys
fi

if [ -f "/root/.ssh/authorized_keys" ]; then
    chmod 600 /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
fi

if [ -f "/app/.env" ]; then
  while IFS='=' read -r name value; do
    if [ -z "${!name+x}" ]; then
      eval "export $name=\"$value\""
    fi
  done < <(grep -v '^\s*#' /app/.env | grep -v '^\s*$')
fi

supervisord -c /etc/supervisor/conf.d/supervisord.conf
