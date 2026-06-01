#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Copy the Self-hosted VPN installer to a server and run it remotely.

Usage:
  ./deploy-remote.sh --host root@SERVER_IP --vpn-domain vpn.example.com --sub-domain vpn.example.com [options]

Required:
  --host SSH_TARGET          Example: root@203.0.113.10
  --vpn-domain DOMAIN        Domain used by Shadowrocket node traffic.
  --sub-domain DOMAIN        Domain used by the private subscription URL. Can equal --vpn-domain.

Options passed through to install.sh:
  --connect-port PORT        SSH connection port. Default: 22.
  --email EMAIL
  --node-name NAME
  --rules-file PATH
  --web-server MODE
  --sub-auth-user USER
  --sub-auth-password PASS
  --trojan-password VALUE
  --ws-path PATH
  --sub-path PATH
  --ssh-port PORT
  --skip-ufw
  --preflight-only           Copy scripts and run preflight without installing.
  -h, --help
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST=""
CONNECT_PORT="22"
INSTALL_ARGS=()
PREFLIGHT_ONLY="0"
VPN_DOMAIN=""
SUB_DOMAIN=""
SSH_PORT="22"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --connect-port)
      CONNECT_PORT="${2:-22}"
      shift 2
      ;;
    --vpn-domain)
      VPN_DOMAIN="${2:-}"
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    --sub-domain)
      SUB_DOMAIN="${2:-}"
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="${2:-22}"
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    --email|--node-name|--rules-file|--web-server|--sub-auth-user|--sub-auth-password|--trojan-password|--ws-path|--sub-path)
      INSTALL_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    --skip-ufw)
      INSTALL_ARGS+=("$1")
      shift
      ;;
    --preflight-only)
      PREFLIGHT_ONLY="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${HOST}" ]] || die "--host is required"
[[ ${#INSTALL_ARGS[@]} -gt 0 ]] || die "install arguments are required"
[[ -n "${VPN_DOMAIN}" ]] || die "--vpn-domain is required"
[[ -n "${SUB_DOMAIN}" ]] || die "--sub-domain is required"
[[ "${CONNECT_PORT}" =~ ^[0-9]+$ ]] || die "--connect-port must be numeric"

REMOTE_DIR="/root/vpn-deploy"

ssh -p "${CONNECT_PORT}" "${HOST}" "mkdir -p ${REMOTE_DIR}"
scp -P "${CONNECT_PORT}" "${SCRIPT_DIR}/install.sh" "${SCRIPT_DIR}/verify.sh" "${SCRIPT_DIR}/check-ip.sh" "${SCRIPT_DIR}/preflight.sh" "${SCRIPT_DIR}/refresh-subscription.sh" "${SCRIPT_DIR}/shadowrocket-rules.conf" "${HOST}:${REMOTE_DIR}/"
ssh -p "${CONNECT_PORT}" "${HOST}" "chmod +x ${REMOTE_DIR}/install.sh ${REMOTE_DIR}/verify.sh ${REMOTE_DIR}/check-ip.sh ${REMOTE_DIR}/preflight.sh ${REMOTE_DIR}/refresh-subscription.sh"

ssh -p "${CONNECT_PORT}" "${HOST}" "bash ${REMOTE_DIR}/preflight.sh --vpn-domain $(printf '%q' "${VPN_DOMAIN}") --sub-domain $(printf '%q' "${SUB_DOMAIN}") --ssh-port $(printf '%q' "${SSH_PORT}")"

if [[ "${PREFLIGHT_ONLY}" == "1" ]]; then
  echo
  echo "Preflight finished. Install was not run because --preflight-only was set."
  exit 0
fi

ssh -p "${CONNECT_PORT}" "${HOST}" "bash ${REMOTE_DIR}/install.sh $(printf '%q ' "${INSTALL_ARGS[@]}")"

echo
echo "Remote install finished. Run verification with:"
echo "  ssh -p ${CONNECT_PORT} ${HOST} 'sudo bash ${REMOTE_DIR}/verify.sh'"
echo
echo "Run IP/ASN check with:"
echo "  ssh -p ${CONNECT_PORT} ${HOST} 'sudo bash ${REMOTE_DIR}/check-ip.sh'"
