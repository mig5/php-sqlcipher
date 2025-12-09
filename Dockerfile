# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE} AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=UTC
ARG PHP_VER=8.2
ARG SQLCIPHER_VERSION=4.12.0

ENV TZ=${TZ} PHP_VER=${PHP_VER} SQLCIPHER_VERSION=${SQLCIPHER_VERSION}

SHELL ["/bin/bash","-o","pipefail","-c"]

# --- Root-only bootstrap: system deps, APT sources, build-deps ---
WORKDIR /work
COPY scripts/ /scripts/

RUN apt-get update && apt-get install -y --no-install-recommends \
      apt-transport-https apt-utils autoconf autopkgtest build-essential \
      ca-certificates curl dpkg-dev devscripts debhelper dh-php pkg-php-tools \
      build-essential devscripts debhelper dh-php dpkg-dev \
      git gnupg pkg-config pkg-php-tools \
      libicu-dev libreadline-dev libssl-dev libsqlite3-dev libtool \
      lintian lsb-release tcl-dev

# Configure PHP repos & ensure deb-src
RUN /bin/bash /scripts/setup-php-sources.sh

# Install PHP build-deps for the selected version
RUN apt-get update \
 && apt-get build-dep -y php${PHP_VER}

# Ensure that autopkgtest works ok, by making sure the 'examples' files are installed
# from the deb as part of running the tests, which depend on them being present (they
# *are* the tests).
RUN rm -f /etc/dpkg/dpkg.cfg.d/docker /etc/dpkg/dpkg.cfg.d/excludes; \
  printf 'path-include=/usr/share/doc/*\n' | tee /etc/dpkg/dpkg.cfg.d/01-include-docs; \
  apt-get update && \
  apt-get -y --no-install-recommends install php${PHP_VER}-cli

# Create unprivileged builder and artifact dir
RUN useradd -m -u 10001 -s /usr/sbin/nologin builder \
 && install -d -o builder -g builder /work /work/src /dist

# --- Unprivileged build from here ---
USER builder
WORKDIR /work/src
RUN git clone --branch v${SQLCIPHER_VERSION} --depth 1 https://github.com/sqlcipher/sqlcipher.git build-sqlcipher && \
  git clone --branch main --depth 1 https://git.mig5.net/mig5/pdo_sqlcipher.git && \
  mkdir php-src && cd php-src && apt-get -y source php${PHP_VER}

COPY --chown=builder:builder . .

# --- No network from here for the actual build ---
RUN --network=none bash -lc '\
  set -euo pipefail && umask 022 && \
  ./scripts/render-debian-files.sh && \
  dpkg-buildpackage -us -uc -b -rfakeroot && \
  . /etc/os-release && lintian -i -E --pedantic --profile "${ID}" --fail-on error ../*.changes'

# Run autopkgtest as root (needs to touch /etc/apt)
USER root
RUN --network=none bash -lc 'set -euo pipefail; \
      pkg=$(ls -1 /work/*.deb | grep -v dbgsym | head -n1); \
      autopkgtest "$pkg" -- null'

# Back to unprivileged user
USER builder
RUN mkdir -p /dist && cp -a ../*.{deb,buildinfo,changes} /dist/ || true

# --- Artifacts-only stage ---
FROM scratch AS artifact
COPY --from=build /dist/ /dist/
