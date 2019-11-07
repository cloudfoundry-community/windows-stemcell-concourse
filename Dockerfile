FROM ubuntu:latest

RUN  apt-get update && apt-get install -y git apt-utils dialog dosfstools mtools xmlstarlet curl jq
RUN git clone https://github.com/bats-core/bats-core.git \
    && cd bats-core \
    && ./install.sh /usr/local

ENTRYPOINT ["bash"]
