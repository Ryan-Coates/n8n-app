FROM alpine:3.21

RUN apk add --no-cache bash curl git python3 docker-cli

WORKDIR /app
COPY deploy-manager.sh .
RUN chmod +x deploy-manager.sh

VOLUME ["/var/log", "/var/repo-clone"]

ENTRYPOINT ["/app/deploy-manager.sh"]
