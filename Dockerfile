FROM ubuntu:latest

RUN  apt-get update && apt-get install -y git apt-utils dialog dosfstools mtools xmlstarlet curl jq unzip
RUN curl -L https://github.com/vmware/govmomi/releases/download/v0.22.1/govc_linux_amd64.gz \
    | gunzip > /usr/local/bin/govc \
    && chmod +x /usr/local/bin/govc
RUN git clone https://github.com/bats-core/bats-core.git \
    && cd bats-core \
    && ./install.sh /usr/local

ENTRYPOINT ["bash"]
