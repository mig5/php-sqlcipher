#!/usr/bin/env bash

set -euo pipefail

. /etc/os-release
curl -fsSL -o /tmp/debsuryorg-archive-keyring.deb \
https://packages.sury.org/debsuryorg-archive-keyring.deb
# SHA256SUM matches what https://mirrors.dotsrc.org/deb.sury.org/bind-dev/dists/bullseye/main/binary-amd64/Packages shows
echo "7511384559c9ddf1d5ce5f60be429ae9d4e7d01d9480d6f1b7a30c0810cf8b60 /tmp/debsuryorg-archive-keyring.deb" | sha256sum -c -
dpkg -i /tmp/debsuryorg-archive-keyring.deb

codename="$(lsb_release -sc)"
cat >/etc/apt/sources.list.d/php.list <<EOF
deb     [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${codename} main
deb-src [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${codename} main
EOF

apt-get update;
apt-get install -y --no-install-recommends php${PHP_VER}-dev
