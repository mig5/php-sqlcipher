#!/usr/bin/env bash

set -euo pipefail

# Space-separated list of PHP major.minor versions to build
PHPS="${PHPS:-"7.4 8.0 8.1 8.2 8.3 8.4"}"

# Matrix of base images with their distro codenames (image|codename)
BASE_MATRIX=(
  "debian:13|trixie"
  "debian:12|bookworm"
  "ubuntu:24.04|noble"
  "ubuntu:22.04|jammy"
)

# Where to put artifacts on the host
OUT_DIR="${OUT_DIR:-"$(cd "$(dirname "$0")/.."; pwd)/build"}"

# Docker binary
DOCKER_BIN="${DOCKER_BIN:-docker}"

# Pass extra args to `docker build` if needed
EXTRA_BUILD_ARGS=${EXTRA_BUILD_ARGS:-}

export DOCKER_BUILDKIT=1

# Always run from scripts/ so relative paths work the same
cd "$(dirname "$0")"

# Dockerfile is in parent; use repo root as build context
DOCKERFILE="../Dockerfile"
CONTEXT=".."

mkdir -p "$OUT_DIR"

echo "==> Output directory: $OUT_DIR"
echo "==> Dockerfile: $DOCKERFILE (context: $CONTEXT)"
echo "==> PHP versions: $PHPS"
echo "==> Base matrix:"
printf '    - %s\n' "${BASE_MATRIX[@]}"

for entry in "${BASE_MATRIX[@]}"; do
  IFS='|' read -r BASE_IMAGE CODENAME <<<"$entry"

  for PHP_VER in $PHPS; do
    TAG="pkg-php${PHP_VER}-${CODENAME}"
    DEST_DIR="${OUT_DIR}/${CODENAME}/php${PHP_VER}"

    echo
    echo "==== Building: base=${BASE_IMAGE} (${CODENAME}), php=${PHP_VER} -> tag=${TAG}"
    echo "     Artifacts -> ${DEST_DIR}"
    mkdir -p "${DEST_DIR}"

    # Build the image.
    $DOCKER_BIN build \
        -f "${DOCKERFILE}" \
        --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
        --build-arg "PHP_VER=${PHP_VER}" \
        --progress=plain \
        -t "${TAG}" \
        ${EXTRA_BUILD_ARGS} \
        "${CONTEXT}"

    # Export /dist/ from the image to the host
    CID="$($DOCKER_BIN create "${TAG}" sh -c 'exit 0')"

    # Copy artifacts
    if ! $DOCKER_BIN cp "${CID}:/dist/." "${DEST_DIR}/"; then
      echo "!! No /dist found in image ${TAG}."
    else
      #find "${DEST_DIR}" -type f ! -name "*.deb" -delete || true
      # Sanity check
      if compgen -G "${DEST_DIR}/*.deb" >/dev/null; then
        echo "==> Collected $(ls -1 "${DEST_DIR}"/*.deb | wc -l | tr -d ' ') .deb files"
      else
        echo "!! No .deb files found for ${TAG} after copy."
      fi
    fi
  done
done

echo
echo "   Done. All artifacts are under: ${OUT_DIR}"
echo "   Structure: build/<codename>/php<version>/*.deb"
