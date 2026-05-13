#!/usr/bin/env bash

set -euo pipefail

# ---- Compute variables ----
PHP_VER="${PHP_VER:?set PHP_VER like 7.4|8.0|8.1|8.2|8.3|8.4}"
PKG="php${PHP_VER}-sqlcipher"
PHP_BIN="php${PHP_VER}"
DOC_DIR="/usr/share/doc/${PKG}"

# Distro codename
if command -v lsb_release >/dev/null 2>&1; then
  DIST_CODENAME="${DIST_CODENAME:-$(lsb_release -sc)}"
else
  . /etc/os-release 2>/dev/null || true
  DIST_CODENAME="${DIST_CODENAME:-${VERSION_CODENAME:-unknown}}"
fi

MAINT_NAME="${MAINT_NAME:-Miguel Jacq}"
MAINT_EMAIL="${MAINT_EMAIL:-mig@mig5.net}"
DATE_RFC2822="$(date -R)"

# Derive package version if not provided
if [[ -z "${PKG_VERSION:-}" ]]; then
  if command -v "${PHP_BIN}" >/dev/null 2>&1; then
    PHP_FULL="$("${PHP_BIN}" -r 'echo PHP_MAJOR_VERSION,".",PHP_MINOR_VERSION,".",PHP_RELEASE_VERSION;')"
  else
    PHP_FULL="$(dpkg-query -W -f='${Version}\n' "${PHP_BIN}-dev" 2>/dev/null | sed 's/-.*//;q' || echo "${PHP_VER}.0")"
  fi

  BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%d%H%M%S)}"

  # Debian revision cannot contain hyphens. Keep this conservative.
  SQLCIPHER_DEB_VER="$(
    printf '%s' "${SQLCIPHER_VERSION:-unknown}" \
      | sed -E 's/^[vV]//; s/[^A-Za-z0-9.+~]/./g'
  )"

  BUILD_ID_DEB="$(
    printf '%s' "${BUILD_ID}" \
      | sed -E 's/[^A-Za-z0-9.+~]/./g'
  )"

  PKG_VERSION="${PHP_FULL}-1+${DIST_CODENAME}.${BUILD_ID_DEB}.sqlcipher${SQLCIPHER_DEB_VER}"
fi


# Export everything envsubst must see
export PHP_VER PKG PHP_BIN DOC_DIR DIST_CODENAME PKG_VERSION MAINT_NAME MAINT_EMAIL DATE_RFC2822 SQLCIPHER_VERSION BUILD_ID

# Only substitute the vars we care about
VARS='${PHP_VER} ${PKG} ${PHP_BIN} ${DOC_DIR} ${DIST_CODENAME} ${PKG_VERSION} ${MAINT_NAME} ${MAINT_EMAIL} ${DATE_RFC2822} ${SQLCIPHER_VERSION} ${BUILD_ID}'

render() {
  local src="$1" dst="$2"
  [[ -f "$src" ]] || return 0
  # Support both ${VAR} and @VAR@ templates
  local tmp; tmp="$(mktemp)"
  sed -E 's/@([A-Z0-9_]+)@/\${\1}/g' "$src" > "$tmp"
  envsubst "$VARS" < "$tmp" > "$dst"
  rm -f "$tmp"
}

# Render files
render debian/changelog.in        debian/changelog
render debian/control.in          debian/control
render debian/copyright.in        debian/copyright
render debian/pkg.examples.in     "debian/${PKG}.examples"
render debian/pkg.php.in          "debian/${PKG}.php"
mkdir -p debian/tests
render debian/tests/control.in    debian/tests/control
render debian/tests/basic.in      debian/tests/basic

# ---- Self-check: make sure changelog header is valid and no ${...} placeholders remain ----
if [[ -f debian/changelog ]]; then
  head -n1 debian/changelog | grep -Eq '^[a-z0-9.+-]+ \([0-9][^)]*\) [^;]+; urgency=' \
    || { echo "ERROR: debian/changelog header invalid:"; sed -n '1,3p' debian/changelog; exit 1; }
  ! grep -q '\${[A-Z0-9_]\+}' debian/changelog \
    || { echo "ERROR: Unsubstituted variables remain in debian/changelog"; sed -n '1,8p' debian/changelog; exit 1; }
fi

