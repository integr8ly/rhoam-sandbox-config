FROM quay.io/centos/centos:7 as build-tools

LABEL maintainer "Devtools <devtools@redhat.com>"
LABEL author "Devtools <devtools@redhat.com>"

ENV LANG=en_US.utf8 \
    GIT_COMMITTER_NAME=devtools \
    GIT_COMMITTER_EMAIL=devtools@redhat.com \
    OCP_VERSION=4.7.16

RUN yum install epel-release -y \
    && yum install https://repo.ius.io/ius-release-el7.rpm -y \
    && yum install --enablerepo=centosplus -y --quiet \
    findutils \
    git224-all \
    procps-ng \
    tar \
    wget \
    which \
    bc \
    kubectl \
    gcc \
    && yum clean all

WORKDIR /tmp

# download, verify and install openshift client tools (oc and kubectl)
RUN curl -L -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz -o openshift-client-linux.tar.gz \
    && echo "378fc049719b297fe44e0cc712f230cd1a68d40fb83d45630e5f3fae5b1a017f openshift-client-linux.tar.gz" > openshift-client-linux.sha256 \
    && sha256sum -c openshift-client-linux.sha256 \
    && tar xzf openshift-client-linux.tar.gz \
    && mv oc /usr/bin/oc \
    && mv kubectl /usr/bin/kubectl \
    && oc version

ENV HOME=/root

COPY find-miners.sh /usr/bin/find-miners.sh
COPY sandbox-cli /usr/bin/sandbox-cli

ENTRYPOINT [ "/bin/bash" ]
