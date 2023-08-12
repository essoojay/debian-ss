FROM debian:latest
RUN set -evx && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y shadowsocks-libev shadowsocks-v2ray-plugin
CMD [ "ss-server" ]
