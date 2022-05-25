FROM registry.access.redhat.com/ubi8/ubi
MAINTAINER Steffen Scheib
RUN dnf update -y && dnf -y install python38 python38-pip zabbix-sender git jq
RUN pip3.8 install python-kasa dumb-init

# setup init
RUN mkdir /init
ADD containerfiles/init.sh /init/init.sh
RUN chmod 755 /init/init.sh

# setup /app
RUN mkdir -p /app/code
RUN git clone https://github.com/sscheib/tplink_smartplug_zabbix.git /app/code/
RUN mv /app/code/src/tplink_smartplug.sh /app/

# Give execution permissions on the script
RUN chmod +x /app/tplink_smartplug.sh

# Cleanup
RUN rm -rf /app/code
RUN dnf remove -y git
RUN dnf clean all
RUN rm -rf /var/cache/yum

# Run the command on container startup
ENTRYPOINT ["dumb-init", "--"]
CMD ["bash", "-c", "/init/init.sh && exec /app/tplink_smartplug.sh --zabbix-server $ZBX_SERVER --host $SMARTPLUG_HOST"]
