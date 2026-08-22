FROM alpine:3.20
RUN apk add --no-cache bash netcat-openbsd
COPY src/port-check.sh /usr/local/bin/port-check.sh
RUN chmod +x /usr/local/bin/port-check.sh
ENTRYPOINT ["bash", "/usr/local/bin/port-check.sh"]
