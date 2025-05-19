
    docker run -d --name dify \
      -p 80:80 \
      -v $(pwd)/volumes/app:/app/api/storage \
      -v $(pwd)/volumes/plugin:/app/storage \
      -v $(pwd)/volumes/db:/var/lib/postgresql/data \
      -v $(pwd)/volumes/redis:/data \
      -v $(pwd)/volumes/weaviate:/var/lib/weaviate \
      dify-custom