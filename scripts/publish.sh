#!/usr/bin/env bash

set -eoux pipefail

OUT_DIR="${OUT_DIR:-"$(cd "$(dirname "$0")/.."; pwd)/build"}"

for CODENAME in trixie bookworm noble jammy; do
  # feed all .deb for that codename into the repo
  if compgen -G "${OUT_DIR}/${CODENAME}/php*/*.deb" >/dev/null 2>&1; then
    find "${OUT_DIR}/${CODENAME}" -name '*.deb' -print0 \
      | xargs -0 -n1 reprepro -b repo includedeb "$CODENAME"
  fi
done
