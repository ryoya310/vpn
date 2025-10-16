FROM debian:bullseye

RUN apt-get update && \
    apt-get install -y strongswan xl2tpd ppp iproute2 iputils-ping cifs-utils && \
    apt-get clean

COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/bin/bash", "/start.sh"]
