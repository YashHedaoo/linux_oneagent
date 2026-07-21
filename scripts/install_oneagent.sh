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
#   DT_CERT_PATH       Local path to Dynatrace root cert (for air-gapped signature verify)
#   DT_LOCAL_INSTALLER Local path to a pre-downloaded installer (skips download step)
#
# Ref: https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent/installation-and-operation/linux/installation/install-oneagent-on-linux

set -euo pipefail

: "${DT_ENV_URL:?DT_ENV_URL is required}"
: "${DT_PAAS_TOKEN:?DT_PAAS_TOKEN is required}"

ARCH="${DT_ARCH:-x86}"
INSTALLER_FLAGS="${DT_INSTALLER_FLAGS:---set-infra-only=false --set-app-log-content-access=true}"
VERIFY_SIGNATURE="${DT_VERIFY_SIGNATURE:-true}"
CERT_PATH="${DT_CERT_PATH:-}"
LOCAL_INSTALLER="${DT_LOCAL_INSTALLER:-}"
INSTALLER="/tmp/Dynatrace-OneAgent-Linux.sh"

# Strip any trailing slash from the env URL.
BASE_URL="${DT_ENV_URL%/}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- Idempotency ---------------------------------------------------------
# Skip if OneAgent is already running on this host. We try multiple detection
# methods because some legacy on-prem boxes don't have systemd or have it
# disabled.
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet oneagent 2>/dev/null; then
    log "OneAgent service is active — skipping install."
    exit 0
  fi
fi

# Fallback: look for the running OneAgent process. The actual binary is at
# /opt/dynatrace/oneagent/agent/lib/<ver>/liboneagentproc.so; the parent
# process matches this string in /proc/<pid>/comm.
if pgrep -f 'oneagent/agent/lib' >/dev/null 2>&1; then
  log "OneAgent process detected — skipping install."
  exit 0
fi

# ---- Installer acquisition ----------------------------------------------
if [ -n "$LOCAL_INSTALLER" ] && [ -f "$LOCAL_INSTALLER" ]; then
  log "Using pre-downloaded installer at $LOCAL_INSTALLER"
  cp "$LOCAL_INSTALLER" "$INSTALLER"
else
  log "Downloading OneAgent installer (arch=${ARCH})..."
  curl -fsSL -o "$INSTALLER" \
    "${BASE_URL}/api/v1/deployment/installer/agent/unix/default/latest?arch=${ARCH}&flavor=default" \
    -H "Authorization: Api-Token ${DT_PAAS_TOKEN}" \
    || die "Failed to download installer from ${BASE_URL}"
fi

# ---- Signature verification ---------------------------------------------
if [ "$VERIFY_SIGNATURE" = "true" ]; then
  log "Verifying installer signature..."

  if [ -n "$CERT_PATH" ] && [ -f "$CERT_PATH" ]; then
    CERT="$CERT_PATH"
  else
    CERT="/tmp/dt-root.cert.pem"
    curl -fsSL -o "$CERT" https://ca.dynatrace.com/dt-root.cert.pem \
      || die "Could not download Dynatrace root certificate. For air-gapped networks, set DT_CERT_PATH."
  fi

  # Reconstruct the signed-message envelope and verify PKCS7 signature.
  ( echo 'Content-Type: multipart/signed; protocol="application/x-pkcs7-signature"; micalg="sha-256"; boundary="--SIGNED-INSTALLER"' ; \
    echo ; echo ; echo '----SIGNED-INSTALLER' ; \
    cat "$INSTALLER" ) \
    | openssl cms -verify -CAfile "$CERT" -binary -no_signer_cert_verify > /dev/null \
    || die "Installer signature verification FAILED — refusing to install."

  log "Signature OK."
  [ "$CERT" = "/tmp/dt-root.cert.pem" ] && rm -f "$CERT"
fi

# ---- Install ------------------------------------------------------------
log "Running installer with flags: $INSTALLER_FLAGS"
# shellcheck disable=SC2086
/bin/sh "$INSTALLER" $INSTALLER_FLAGS

log "Cleaning up installer."
rm -f "$INSTALLER"

log "OneAgent installation complete."