# Helm is built from Artie's fork instead of taken from the base image, to carry two fixes from
# https://github.com/artie-labs/helm/pull/1 ahead of an upstream release: API discovery runs once per
# process instead of once per object in Build, and objects of the same kind are applied concurrently.
# HELM_REF pins the exact commit; HELM_VERSION is what `helm version` prints in build logs.
ARG HELM_REPO=https://github.com/artie-labs/helm.git
ARG HELM_REF=2e4c18fb6
ARG HELM_VERSION=v4.3.1-concurrent-update.2

# Runs on the build machine's own platform and cross-compiles for the target, so a multi-arch
# build does not compile under emulation. The result is a static binary (CGO_ENABLED=0).
FROM --platform=$BUILDPLATFORM golang:1.27-alpine AS helm-build
ARG HELM_REPO
ARG HELM_REF
ARG HELM_VERSION
ARG TARGETOS
ARG TARGETARCH
RUN apk add --no-cache bash git make
RUN git clone --filter=blob:none --no-checkout ${HELM_REPO} /helm && \
    git -C /helm checkout --detach ${HELM_REF}
WORKDIR /helm
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} make build VERSION=${HELM_VERSION} && \
    test -x bin/helm

FROM alpine/helm:4.3.1
# Helm supported version along with K8 version: https://helm.sh/docs/topics/version_skew/
# List of Helm images: https://hub.docker.com/r/alpine/helm/tags

LABEL maintainer="Yann David (@Typositoire) <davidyann88@gmail>"

# Versions for gcloud, kubectl, doctl, awscli, azure-cli
# K8 versions: https://kubernetes.io/releases/
ARG KUBERNETES_VERSION=1.35.9
ARG GCLOUD_VERSION=590.0.0
ARG DOCTL_VERSION=1.186.0
ARG AWSCLI_VERSION=2.34.63-r0
# azure-cli versions: https://pypi.org/project/azure-cli/#history
ARG AZURE_CLI_VERSION=2.91.0
ARG HELM_DIFF_VERSION=3.15.15
# helm-diff release signing key: https://github.com/databus23/helm-diff#helm-4
ARG HELM_DIFF_KEY_FINGERPRINT=C5645EF47482257A1F806D2BEA17A2A206AFF8CD
# Set by buildx from --platform: amd64 or arm64
ARG TARGETARCH


#gcloud path
ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin

#install packages
RUN apk add --update --upgrade --no-cache jq bash curl git gettext gnupg libintl py-pip aws-cli=${AWSCLI_VERSION} && \
    apk add --no-cache --virtual .build-deps gcc musl-dev python3-dev libffi-dev openssl-dev cargo make && \
    pip install --break-system-packages --upgrade pip && \
    pip install --break-system-packages azure-cli==${AZURE_CLI_VERSION} && \
    apk del .build-deps

#install kubectl
RUN curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/${TARGETARCH}/kubectl && \
    chmod +x /usr/local/bin/kubectl

#install gcloud
# gcloud names its archives x86_64 and arm
RUN GCLOUD_ARCH=$([ "${TARGETARCH}" = arm64 ] && echo arm || echo x86_64) && \
    wget https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCLOUD_VERSION}-linux-${GCLOUD_ARCH}.tar.gz \
    -O /tmp/google-cloud-sdk.tar.gz | bash

# For use with gke-gcloud-auth-plugin below
# see https://cloud.google.com/blog/products/containers-kubernetes/kubectl-auth-changes-in-gke
# for details
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

RUN mkdir -p /usr/local/gcloud \
    && tar -C /usr/local/gcloud -xvzf /tmp/google-cloud-sdk.tar.gz \
    && /usr/local/gcloud/google-cloud-sdk/install.sh -q \
    ## auth package is split out now, need explicit install
    ## --quiet disables interactive prompts
    && gcloud components install gke-gcloud-auth-plugin --quiet

# Replace the base image's helm with the build from Artie's fork (see the top of this file)
COPY --from=helm-build /helm/bin/helm /usr/bin/helm

#copy scripts
ADD assets /opt/resource

#install plugins
# Helm 4 verifies plugin signatures; install the signed release tarball against the pinned maintainer key
RUN curl -fsSL https://github.com/databus23.gpg | gpg --dearmor > /tmp/helm-diff.gpg && \
  gpg --show-keys --with-colons /tmp/helm-diff.gpg | grep -q "^fpr:::::::::${HELM_DIFF_KEY_FINGERPRINT}:" && \
  helm plugin install --keyring /tmp/helm-diff.gpg \
    https://github.com/databus23/helm-diff/releases/download/v${HELM_DIFF_VERSION}/diff-${HELM_DIFF_VERSION}-linux-${TARGETARCH}.tgz && \
  rm /tmp/helm-diff.gpg

#install doctl
RUN curl -sL -o /tmp/doctl.tar.gz https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-${TARGETARCH}.tar.gz && \
  tar -C /usr/local/bin -zxvf /tmp/doctl.tar.gz && \
  chmod +x /usr/local/bin/doctl

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
