#!/bin/bash
set -e

if [ -f "/app/.env" ]; then
  while IFS='=' read -r name value; do
    if [ -z "${!name+x}" ]; then
      eval "export $name=\"$value\""
    fi
  done < <(grep -v '^\s*#' /app/.env | grep -v '^\s*$')
fi

supervisord -c /etc/supervisor/conf.d/supervisord.conf
