docker buildx build --platform linux/amd64 --build-arg NODE_ENV=production -t kmapp2024/kmapp:kmapp-cms .
docker push kmapp2024/kmapp:kmapp-cms