FROM alpine:3.20
RUN apk add --no-cache bash docker-cli
COPY src/docker-health.sh /usr/local/bin/docker-health.sh
RUN chmod +x /usr/local/bin/docker-health.sh
ENTRYPOINT ["bash", "/usr/local/bin/docker-health.sh"]
