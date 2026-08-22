FROM alpine:3.20
RUN apk add --no-cache bash iputils iproute2
COPY src/lan-devices.sh /usr/local/bin/lan-devices.sh
RUN chmod +x /usr/local/bin/lan-devices.sh
ENTRYPOINT ["bash", "/usr/local/bin/lan-devices.sh"]
