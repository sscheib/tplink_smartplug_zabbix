FROM alpine:3.12

STOPSIGNAL SIGTERM
RUN apk update && apk upgrade
RUN set -eux && \
    addgroup -S -g 1995 zabbix && \
    adduser -S \
            -D -G zabbix -G root \
            -u 1997 \
            -h /var/lib/zabbix/ \
        zabbix && \
    mkdir -p /etc/zabbix && \
    mkdir -p /etc/zabbix/zabbix_agentd.d && \
    mkdir -p /var/lib/zabbix && \
    mkdir -p /var/lib/zabbix/enc && \
    mkdir -p /var/lib/zabbix/modules && \
    apk add --no-cache --clean-protected \
            tini \
            bash \
            tzdata \
            coreutils \
            iputils \
            pcre \
            libcurl \
            libldap && \
    rm -rf /var/cache/apk/*

ARG MAJOR_VERSION=5.0
ARG ZBX_VERSION=${MAJOR_VERSION}.3
ARG ZBX_SOURCES=https://git.zabbix.com/scm/zbx/zabbix.git

ENV TERM=xterm ZBX_VERSION=${ZBX_VERSION} ZBX_SOURCES=${ZBX_SOURCES}

RUN set -eux && \
    apk add --no-cache --virtual build-dependencies \
            autoconf \
            automake \
            curl-dev \
            openssl-dev \
            openldap-dev \
            g++ \
            pcre-dev \
            make \
            git \
            coreutils && \
    cd /tmp/ && \
    git clone ${ZBX_SOURCES} --branch ${ZBX_VERSION} --depth 1 --single-branch zabbix-${ZBX_VERSION} && \
    cd /tmp/zabbix-${ZBX_VERSION} && \
    zabbix_revision=`git rev-parse --short HEAD` && \
    sed -i "s/{ZABBIX_REVISION}/$zabbix_revision/g" include/version.h && \
    ./bootstrap.sh && \
    export CFLAGS="-fPIC -pie -Wl,-z,relro -Wl,-z,now" && \
    ./configure \
            --datadir=/usr/lib \
            --libdir=/usr/lib/zabbix \
            --prefix=/usr \
            --sysconfdir=/etc/zabbix \
            --prefix=/usr \
            --enable-agent \
            --with-libcurl \
            --with-ldap \
            --with-openssl \
            --enable-ipv6 \
            --silent && \
    make -j"$(nproc)" -s && \
    cp /tmp/zabbix-${ZBX_VERSION}/src/zabbix_sender/zabbix_sender /usr/bin/zabbix_sender && \
    chmod +x /usr/bin/zabbix_sender

# install additional dependencies
RUN apk add jq py3-pip bash
RUN pip3 install python-kasa dumb-init


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

RUN cd /tmp/ && \
    rm -rf /tmp/zabbix-${ZBX_VERSION}/ && \
    chown --quiet -R zabbix:root /etc/zabbix/ /var/lib/zabbix/ && \
    chgrp -R 0 /etc/zabbix/ /var/lib/zabbix/ && \
    chmod -R g=u /etc/zabbix/ /var/lib/zabbix/ && \
    apk del --purge --no-network \
            build-dependencies && \
    rm -rf /var/cache/apk/*

# Run the command on container startup
ENTRYPOINT ["dumb-init", "--"]
CMD ["/bin/sh", "-c", "/init/init.sh && exec /app/tplink_smartplug.sh --zabbix-server $ZBX_SERVER --host $SMARTPLUG_HOST"]
