FROM alpine:3.20
RUN apk add --no-cache bash openssh-client
COPY src/service-status.sh /usr/local/bin/service-status.sh
RUN chmod +x /usr/local/bin/service-status.sh
ENTRYPOINT ["bash", "/usr/local/bin/service-status.sh"]
