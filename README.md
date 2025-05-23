
```bash
docker run -d -p 80 -p 443 -p 22 --name dify \
	-v ./volumes/app:/app/api/storage \
	-v ./volumes/plugin:/app/storage \
	-v ./volumes/db:/var/lib/postgresql/data \
	-v ./volumes/redis:/data \
	-v ./volumes/weaviate:/var/lib/weaviate \
	-v ./ssl:/etc/ssl \
	-e NGINX_HTTPS_ENABLED=true \
	-e NGINX_SSL_CERT_FILENAME=fullchain.cer \
	-e NGINX_SSL_CERT_KEY_FILENAME=privatekey.key \
	-e SSH_PASSWORD=123456 \
	dify-all-in-one:1.4.0
```
```bash
docker run -d -p 80 -p 443 -p 22 --name dify \
	-v ./volumes/app:/app/api/storage \
	-v ./volumes/plugin:/app/storage \
	-v ./volumes/db:/var/lib/postgresql/data \
	-v ./volumes/redis:/data \
	-v ./volumes/weaviate:/var/lib/weaviate \
	-v ./ssl:/etc/ssl \
	-v ./zker_rsa.pub:/root/.ssh/zker_rsa.pub:ro \
	-e NGINX_HTTPS_ENABLED=true \
	-e NGINX_SSL_CERT_FILENAME=fullchain.cer \
	-e NGINX_SSL_CERT_KEY_FILENAME=privatekey.key \
	-e SSH_IDENTITY_FILE=/root/.ssh/zker_rsa.pub \
	dify-all-in-one:1.4.0
```
	
readyProbe:
```yaml
exec:
  command:
    - sh
    - - -c
    - "! supervisorctl -c /etc/supervisor/conf.d/supervisord.conf status | grep -q RUNNING"
initialDelaySeconds: 10   # 更短的初始延迟，快速响应就绪状态
periodSeconds: 5          # 更高的探测频率
failureThreshold: 1       # 一次失败即标记未就绪
```
