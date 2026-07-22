#!/usr/bin/env bash
#
# Deploy Dynatrace OneAgent across Linux hosts via SSH.
#
# Usage:
#   ./scripts/deploy.sh [host1 host2 ...]
#
# Environment variables:
#   DT_ENV_URL           Dynatrace environment URL (required or fetched via Artifactory)
#   DT_PAAS_TOKEN        PaaS token (required)
#   ARTIFACTORY_URL      URL to file in JFrog Artifactory containing DT_ENV_URL (optional)
#   ARTIFACTORY_TOKEN    Bearer token for JFrog Artifactory (optional)
#   ARTIFACTORY_USER     Username for JFrog Artifactory basic auth (optional)
#   ARTIFACTORY_PASSWORD Password for JFrog Artifactory basic auth (optional)
#   TARGET_HOSTS         Space- or comma-separated hostnames/IPs (if hosts not passed as args)
#   SSH_USER             SSH username (default: ubuntu)
#   SSH_PRIVATE_KEY_PATH Path to SSH private key file (optional)
#   SSH_PORT             SSH port (default: 22)
#   BASTION_HOST         Bastion/jump host (optional)
#   BASTION_USER         Bastion SSH username (default: SSH_USER)
#   BASTION_PORT         Bastion SSH port (default: 22)
#   DT_ARCH              Target architecture (default: x86)
#   DT_INSTALLER_FLAGS   Installer flags (default: --set-infra-only=false --set-app-log-content-access=true)
#   DT_VERIFY_SIGNATURE  Verify installer signature: true (default) | false
#   DT_CERT_PATH         Local path to root cert (optional)
#   DT_LOCAL_INSTALLER   Local path to pre-downloaded installer (optional)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install_oneagent.sh"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- Fetch DT_ENV_URL from JFrog Artifactory if needed -----------------
ART_URL="${ARTIFACTORY_URL:-${JFROG_URL:-}}"
ART_TOKEN="${ARTIFACTORY_TOKEN:-${JFROG_TOKEN:-}}"
ART_USER="${ARTIFACTORY_USER:-${JFROG_USER:-}}"
ART_PASS="${ARTIFACTORY_PASSWORD:-${JFROG_PASSWORD:-}}"

if [ -z "${DT_ENV_URL:-}" ] && [ -n "$ART_URL" ]; then
  log "DT_ENV_URL not provided directly — fetching from JFrog Artifactory at ${ART_URL}..."
  CURL_AUTH=()
  if [ -n "$ART_TOKEN" ]; then
    CURL_AUTH=(-H "Authorization: Bearer ${ART_TOKEN}")
  elif [ -n "$ART_USER" ] && [ -n "$ART_PASS" ]; then
    CURL_AUTH=(-u "${ART_USER}:${ART_PASS}")
  fi

  FETCHED_URL="$(curl -fsSL "${CURL_AUTH[@]}" "$ART_URL" | tr -d '\r\n' | xargs)"
  if [ -z "$FETCHED_URL" ]; then
    die "Failed to fetch DT_ENV_URL from JFrog Artifactory at ${ART_URL}"
  fi
  DT_ENV_URL="$FETCHED_URL"
  export DT_ENV_URL
  log "Successfully fetched DT_ENV_URL from Artifactory: ${DT_ENV_URL}"
fi

# ---- Validate Prerequisites & Inputs -------------------------------------
: "${DT_ENV_URL:?Error: DT_ENV_URL is required (set DT_ENV_URL or ARTIFACTORY_URL)}"
: "${DT_PAAS_TOKEN:?Error: DT_PAAS_TOKEN is required}"

if [ ! -f "$INSTALL_SCRIPT" ]; then
  die "Installer script not found at $INSTALL_SCRIPT"
fi

# Determine target hosts
HOSTS=()
if [ "$#" -gt 0 ]; then
  HOSTS=("$@")
elif [ -n "${TARGET_HOSTS:-}" ]; then
  # Handle JSON array format if passed from GitHub Actions or comma/space separated string
  RAW_HOSTS="${TARGET_HOSTS//[\[\]\'\"]/}"
  IFS=', ' read -r -a HOSTS <<< "$RAW_HOSTS"
fi

# Remove empty entries
CLEAN_HOSTS=()
for h in "${HOSTS[@]}"; do
  [ -n "$h" ] && CLEAN_HOSTS+=("$h")
done
HOSTS=("${CLEAN_HOSTS[@]}")

if [ "${#HOSTS[@]}" -eq 0 ]; then
  die "No target hosts provided. Specify hosts as arguments or set TARGET_HOSTS."
fi

# SSH Options
SSH_USER="${SSH_USER:-ubuntu}"
SSH_PORT="${SSH_PORT:-22}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o Port="$SSH_PORT")

if [ -n "${SSH_PRIVATE_KEY_PATH:-}" ]; then
  SSH_OPTS+=(-i "$SSH_PRIVATE_KEY_PATH")
fi

# Bastion / ProxyJump option
if [ -n "${BASTION_HOST:-}" ]; then
  B_USER="${BASTION_USER:-$SSH_USER}"
  B_PORT="${BASTION_PORT:-22}"
  SSH_OPTS+=(-o "ProxyJump=${B_USER}@${BASTION_HOST}:${B_PORT}")
fi

# Optional Dynatrace environment variables
ARCH="${DT_ARCH:-x86}"
INSTALLER_FLAGS="${DT_INSTALLER_FLAGS:---set-infra-only=false --set-app-log-content-access=true}"
VERIFY_SIGNATURE="${DT_VERIFY_SIGNATURE:-true}"
CERT_PATH="${DT_CERT_PATH:-}"
LOCAL_INSTALLER="${DT_LOCAL_INSTALLER:-}"

PRESERVE_KEYS="DT_ENV_URL,DT_PAAS_TOKEN,DT_ARCH,DT_INSTALLER_FLAGS,DT_VERIFY_SIGNATURE,DT_CERT_PATH,DT_LOCAL_INSTALLER"

deploy_to_host() {
  local host="$1"
  log "Starting deployment on target host: ${host}"

  local target_spec="${SSH_USER}@${host}"

  # 1. Check SSH connection and passwordless sudo
  log "[${host}] Verifying SSH connection and passwordless sudo..."
  if ! ssh "${SSH_OPTS[@]}" "$target_spec" "sudo -n -v" >/dev/null 2>&1; then
    die "[${host}] Pre-flight failed: SSH user '${SSH_USER}' cannot run passwordless sudo ('sudo -n -v') on ${host}."
  fi
  log "[${host}] Pre-flight check passed."

  # 2. Copy install_oneagent.sh
  log "[${host}] Uploading installer script to /tmp/install_oneagent.sh..."
  scp "${SSH_OPTS[@]}" "$INSTALL_SCRIPT" "${target_spec}:/tmp/install_oneagent.sh"

  # 3. Copy optional local cert or pre-downloaded installer if specified
  local remote_cert=""
  if [ -n "$CERT_PATH" ] && [ -f "$CERT_PATH" ]; then
    log "[${host}] Uploading local root certificate..."
    scp "${SSH_OPTS[@]}" "$CERT_PATH" "${target_spec}:/tmp/dt-root.cert.pem"
    remote_cert="/tmp/dt-root.cert.pem"
  fi

  local remote_installer=""
  if [ -n "$LOCAL_INSTALLER" ] && [ -f "$LOCAL_INSTALLER" ]; then
    log "[${host}] Uploading pre-downloaded installer..."
    scp "${SSH_OPTS[@]}" "$LOCAL_INSTALLER" "${target_spec}:/tmp/Dynatrace-OneAgent-Linux.sh"
    remote_installer="/tmp/Dynatrace-OneAgent-Linux.sh"
  fi

  # 4. Execute installer on remote host securely
  log "[${host}] Running installer script as root..."
  ssh "${SSH_OPTS[@]}" "$target_spec" bash -s <<EOF
set -e
export DT_ENV_URL=$(printf '%q' "$DT_ENV_URL")
export DT_PAAS_TOKEN=$(printf '%q' "$DT_PAAS_TOKEN")
export DT_ARCH=$(printf '%q' "$ARCH")
export DT_INSTALLER_FLAGS=$(printf '%q' "$INSTALLER_FLAGS")
export DT_VERIFY_SIGNATURE=$(printf '%q' "$VERIFY_SIGNATURE")
export DT_CERT_PATH=$(printf '%q' "$remote_cert")
export DT_LOCAL_INSTALLER=$(printf '%q' "$remote_installer")

chmod +x /tmp/install_oneagent.sh
sudo --preserve-env=${PRESERVE_KEYS} bash /tmp/install_oneagent.sh
rm -f /tmp/install_oneagent.sh /tmp/dt-root.cert.pem /tmp/Dynatrace-OneAgent-Linux.sh
EOF

  log "[${host}] OneAgent deployment succeeded!"
}

# Run deployment sequentially for target hosts
FAILED_HOSTS=()
for host in "${HOSTS[@]}"; do
  if ! deploy_to_host "$host"; then
    warn "Deployment failed on ${host}"
    FAILED_HOSTS+=("$host")
  fi
done

if [ "${#FAILED_HOSTS[@]}" -gt 0 ]; then
  die "Deployment failed on the following host(s): ${FAILED_HOSTS[*]}"
fi

log "All deployments completed successfully!"
