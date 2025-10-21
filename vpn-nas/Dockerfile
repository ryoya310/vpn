FROM debian:bullseye

RUN apt-get update && \
    apt-get install -y \
      strongswan \
      xl2tpd \
      ppp \
      iproute2 \
      net-tools \
      iputils-ping \
      cifs-utils \
      rsync \
      && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh
RUN chmod +x /start.sh

COPY scripts/vpn_connect.sh /scripts/vpn_connect.sh
RUN chmod +x /scripts/vpn_connect.sh

COPY scripts/mount_smb.sh /scripts/mount_smb.sh
RUN chmod +x /scripts/mount_smb.sh

CMD ["/bin/bash", "/start.sh"]
