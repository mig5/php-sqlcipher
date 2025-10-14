#!/usr/bin/env bash

set -euo pipefail

. /etc/os-release
case "${ID}" in
  ubuntu)
    apt-get update
    apt-get install -y --no-install-recommends software-properties-common
    # Adds both deb and deb-src for Ondřej’s PPA
    add-apt-repository -y -s ppa:ondrej/php
    ;;
  debian)
    # Official way per deb.sury.org README
    curl -fsSL -o /tmp/debsuryorg-archive-keyring.deb \
      https://packages.sury.org/debsuryorg-archive-keyring.deb
    # SHA256SUM matches what https://mirrors.dotsrc.org/deb.sury.org/bind-dev/dists/bullseye/main/binary-amd64/Packages shows
    echo "d1df4b797498829bb4dbd23de7a88945924a0eac6bce9b6c68e6650c85187f5f /tmp/debsuryorg-archive-keyring.deb" | sha256sum -c -
    dpkg -i /tmp/debsuryorg-archive-keyring.deb

    codename="$(lsb_release -sc)"
    cat >/etc/apt/sources.list.d/php.list <<EOF
deb     [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${codename} main
deb-src [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${codename} main
EOF
    ;;
  *)
    echo "Unsupported distro ID=${ID}" >&2; exit 2;;
esac

apt-get update;
apt-get install -y --no-install-recommends php${PHP_VER}-dev
