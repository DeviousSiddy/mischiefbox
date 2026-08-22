FROM alpine:3.20
RUN apk add --no-cache bash curl bc
COPY src/speed-test.sh /usr/local/bin/speed-test.sh
RUN chmod +x /usr/local/bin/speed-test.sh
ENTRYPOINT ["bash", "/usr/local/bin/speed-test.sh"]
