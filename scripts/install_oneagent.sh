#!/usr/bin/env bash
#
# Downloads and installs the Dynatrace OneAgent on a Linux host.
# Driven entirely by environment variables so no secrets are baked into the file.
#
# Required env:
#   DT_ENV_URL         Dynatrace environment URL (e.g. https://abc12345.live.dynatrace.com)
#   DT_PAAS_TOKEN      PaaS token used to download the installer
# Optional env:
#   DT_ARCH            x86 (default) | arm | ppcle | s390
#   DT_INSTALLER_FLAGS flags for the installer (default: infra-only off, log access on)
#   DT_VERIFY_SIGNATURE  true (default) | false
#
# Ref: https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent/installation-and-operation/linux/installation/install-oneagent-on-linux

set -euo pipefail

: "${DT_ENV_URL:?DT_ENV_URL is required}"
: "${DT_PAAS_TOKEN:?DT_PAAS_TOKEN is required}"

ARCH="${DT_ARCH:-x86}"
INSTALLER_FLAGS="${DT_INSTALLER_FLAGS:---set-infra-only=false --set-app-log-content-access=true}"
VERIFY_SIGNATURE="${DT_VERIFY_SIGNATURE:-true}"
INSTALLER="/tmp/Dynatrace-OneAgent-Linux.sh"

# Strip any trailing slash from the env URL.
BASE_URL="${DT_ENV_URL%/}"

log() { printf '==> %s\n' "$*"; }

# Idempotency: skip if OneAgent is already installed.
if [ -d /opt/dynatrace/oneagent ] || systemctl list-unit-files 2>/dev/null | grep -q '^oneagent'; then
  log "OneAgent already present on this host — skipping install."
  exit 0
fi

log "Downloading OneAgent installer (arch=${ARCH})..."
curl -fsSL -o "$INSTALLER" \
  "${BASE_URL}/api/v1/deployment/installer/agent/unix/default/latest?arch=${ARCH}&flavor=default" \
  -H "Authorization: Api-Token ${DT_PAAS_TOKEN}"

if [ "$VERIFY_SIGNATURE" = "true" ]; then
  log "Verifying installer signature..."
  curl -fsSL -o /tmp/dt-root.cert.pem https://ca.dynatrace.com/dt-root.cert.pem
  ( echo 'Content-Type: multipart/signed; protocol="application/x-pkcs7-signature"; micalg="sha-256"; boundary="--SIGNED-INSTALLER"' ; echo ; echo ; echo '----SIGNED-INSTALLER' ; cat "$INSTALLER" ) \
    | openssl cms -verify -CAfile /tmp/dt-root.cert.pem -binary -no_signer_cert_verify > /dev/null
  log "Signature OK."
  rm -f /tmp/dt-root.cert.pem
fi

log "Running installer..."
# shellcheck disable=SC2086
/bin/sh "$INSTALLER" $INSTALLER_FLAGS

log "Cleaning up installer."
rm -f "$INSTALLER"

log "OneAgent installation complete."
