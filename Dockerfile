FROM langgenius/dify-api:1.4.1 AS api
FROM langgenius/dify-web:1.4.1 AS web
FROM langgenius/dify-plugin-daemon:0.1.1-local AS plugin-daemon
FROM semitechnologies/weaviate:1.19.0 AS weaviate

FROM ubuntu:24.04

ARG TZ=Asia/Shanghai

# 设置全局环境变量
ENV EDITION=SELF_HOSTED \
    DEPLOY_ENV=PRODUCTION \
    FLASK_APP=app.py \
    PORT=3000 \
    NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production \
    PM2_INSTANCES=2

# 设置时区
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# 安装所有运行时依赖
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        git make python3.12 python3.12-venv python3-pip \
        libgmp-dev libmpfr-dev libmpc-dev curl ffmpeg \
        expat libldap2 perl libsqlite3-0 zlib1g \
        media-types \
        libmagic1 \
        pkg-config libseccomp-dev wget

# web部分
COPY --from=web /app/web /app/web
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g pnpm@10.8.0
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN pnpm add -g pm2 && \
    mkdir /.pm2 && \
    chown -R 0:0 /.pm2 /app/web && \
    chmod -R g=u /.pm2 /app/web
RUN sed -i 's|process.env.HOSTNAME \|\| ||' /app/web/server.js

# api部分
COPY --from=api /app/api /app/api
WORKDIR /app/api
RUN ln -sf $(which python3.12) /usr/bin/python && \
    ln -sf $(which python3.12) /usr/local/bin/python3

# Python 环境
ENV VIRTUAL_ENV=/app/api/.venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# 安装 uv
ENV UV_VERSION=0.6.14
RUN pip install --break-system-packages --no-cache-dir uv==${UV_VERSION}

# 下载 nltk 数据
RUN python -c "import nltk; nltk.download('punkt'); nltk.download('averaged_perceptron_tagger')"
ENV TIKTOKEN_CACHE_DIR=/app/api/.tiktoken_cache
RUN python -c "import tiktoken; tiktoken.encoding_for_model('gpt2')"

# 复制入口点
COPY ./api/entrypoint.sh /app/api/entrypoint.sh
RUN chmod +x /app/api/entrypoint.sh

# sandbox部分
WORKDIR /app/sandbox
COPY ./sandbox/main ./main
COPY ./sandbox/env ./env
COPY ./sandbox/config.yaml ./conf/config.yaml
COPY ./sandbox/python-requirements.txt ./dependencies/python-requirements.txt
RUN chmod +x ./main ./env && \
    pip3 install --break-system-packages --no-cache-dir \
        httpx==0.27.2 \
        requests==2.32.3 \
        jinja2==3.0.3 \
        PySocks \
        httpx[socks] && \
    ./env && \
    rm -f ./env

# plugin-daemon部分
WORKDIR /app/plugin-daemon
ENV UV_PATH=/usr/local/bin/uv
ENV PLATFORM=local
ENV GIN_MODE=release
RUN mv /usr/lib/python3.12/EXTERNALLY-MANAGED /usr/lib/python3.12/EXTERNALLY-MANAGED.bk && \
    ln -sf $TIKTOKEN_CACHE_DIR /app/plugin-daemon/.tiktoken && \
    python3 -c "import tiktoken; encodings = ['o200k_base', 'cl100k_base', 'p50k_base', 'r50k_base', 'p50k_edit', 'gpt2']; [tiktoken.get_encoding(encoding).special_tokens_set for encoding in encodings]"
COPY --from=plugin-daemon /app/main /app/plugin-daemon/main

# postgres部分
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-common && \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 gosu
ENV PATH="/usr/lib/postgresql/15/bin:${PATH}"
RUN mkdir /docker-entrypoint-initdb.d
COPY pg/docker-entrypoint.sh pg/docker-ensure-initdb.sh /usr/local/bin/
RUN ln -sT docker-ensure-initdb.sh /usr/local/bin/docker-enforce-initdb.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-ensure-initdb.sh

# redis部分
RUN set -eux; \
    groupadd -r -g 1999 redis; \
    useradd -r -g redis -u 1999 redis

ENV REDIS_VERSION=6.2.18
ENV REDIS_DOWNLOAD_URL=http://download.redis.io/releases/redis-6.2.18.tar.gz
ENV REDIS_DOWNLOAD_SHA=470c75bac73d7390be4dd66479c6f29e86371c5d380ce0c7efb4ba2bbda3612d

RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        dpkg-dev \
        gcc \
        libc6-dev \
        libssl-dev \
        make; \
    wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
    echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c -; \
    mkdir -p /usr/src/redis; \
    tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1; \
    rm redis.tar.gz; \
    grep -E '^ *createBoolConfig[(]"protected-mode",.*, *1 *,.*[)],$' /usr/src/redis/src/config.c; \
    sed -ri 's!^( *createBoolConfig[(]"protected-mode",.*, *)1( *,.*[)],)$!\10\2!' /usr/src/redis/src/config.c; \
    grep -E '^ *createBoolConfig[(]"protected-mode",.*, *0 *,.*[)],$' /usr/src/redis/src/config.c; \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    extraJemallocConfigureFlags="--build=$gnuArch"; \
    dpkgArch="$(dpkg --print-architecture)"; \
    case "${dpkgArch##*-}" in \
        amd64 | i386 | x32) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=12" ;; \
        *) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=16" ;; \
    esac; \
    extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-hugepage=21"; \
    grep -F 'cd jemalloc && ./configure ' /usr/src/redis/deps/Makefile; \
    sed -ri 's!cd jemalloc && ./configure !&'"$extraJemallocConfigureFlags"' !' /usr/src/redis/deps/Makefile; \
    grep -F "cd jemalloc && ./configure $extraJemallocConfigureFlags " /usr/src/redis/deps/Makefile; \
    export BUILD_TLS=yes; \
    make -C /usr/src/redis -j "$(nproc)" all; \
    make -C /usr/src/redis install; \
    serverMd5="$(md5sum /usr/local/bin/redis-server | cut -d' ' -f1)"; \
    export serverMd5; \
    find /usr/local/bin/redis* -maxdepth 0 \
        -type f -not -name redis-server \
        -exec sh -eux -c ' \
            md5="$(md5sum "$1" | cut -d" " -f1)"; \
            test "$md5" = "$serverMd5"; \
        ' -- '{}' ';' \
        -exec ln -svfT 'redis-server' '{}' ';'; \
    rm -r /usr/src/redis; \
    apt-mark auto '.*' >/dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark >/dev/null; \
    find /usr/local -type f -executable -exec ldd '{}' ';' \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    redis-cli --version; \
    redis-server --version

RUN mkdir /data && chown redis:redis /data
COPY redis/redis-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/redis-entrypoint.sh

# weaviate部分
COPY --from=weaviate /bin/weaviate /bin/weaviate
RUN apt install -y musl-tools && \
    ln -sf /usr/lib/ld-musl-x86_64.so.1 /lib/libc.musl-x86_64.so.1 && \
    mkdir -p /app/weaviate/modules

# nginx部分
RUN useradd --system --no-create-home --shell /usr/sbin/nologin nginx && \
    apt-get install -y nginx gettext-base
COPY ./nginx /etc/nginx
RUN chmod +x /etc/nginx/docker-entrypoint.sh

# 收尾
ARG COMMIT_SHA
ENV COMMIT_SHA=${COMMIT_SHA}

WORKDIR /app
RUN pip install git+https://github.com/Supervisor/supervisor.git --break-system-packages && \
    pip install git+https://github.com/whereisaaron/supervisor-stdout.git --break-system-packages
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN apt-get install -y openssh-client openssh-server && \
    mkdir -p /var/run/sshd
COPY ssh/sshd.conf /etc/ssh/sshd_config.d/sshd.conf

COPY entrypoint.sh /app/entrypoint.sh
COPY .env /app/.env
RUN chmod +x /app/entrypoint.sh

# 清理
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 可能的挂载点
#   - ./volumes/app:/app/api/storage
#   - ./volumes/plugin:/app/storage
#   - ./volumes/db:/var/lib/postgresql/data
#   - ./volumes/redis:/data
#   - ./volumes/weaviate:/var/lib/weaviate
#   - ./ssl:/etc/ssl

HEALTHCHECK --interval=5s --timeout=10s --retries=60 --start-period=10s \
    CMD curl -s http://127.0.0.1:${DIFY_PORT:-5001}/health | grep -q ok

# 设置容器入口点
CMD ["/app/entrypoint.sh"]
