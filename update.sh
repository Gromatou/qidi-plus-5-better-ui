#!/bin/sh
# =============================================================================
#  QIDI Plus 5 better-UI — self-update
# -----------------------------------------------------------------------------
#  Pulls the latest Klipper macro fixes + QIDI Plus 5 profile from GitHub and
#  applies them (idempotent, reversible, backup-protected). It NEVER restarts
#  Klipper by itself: macro changes load at the next FIRMWARE_RESTART.
#
#    sh update.sh                   # check + apply now
#    sh update.sh --check           # only report installed vs latest version
#    sh update.sh --quiet           # for the timer (minimal output)
#    sh update.sh --install-timer   # enable a daily automatic run (needs sudo)
#    sh update.sh --uninstall-timer # disable the automatic run
#
#  Safe to run any time (even mid-print: it only writes config files).
# =============================================================================
set -eu

REPO="Gromatou/qidi-plus-5-better-ui"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TGZ="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

KS_USER="${KS_USER:-$(id -un)}"
HOME_DIR="$(getent passwd "$KS_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="$HOME"
STATE_DIR="${HOME_DIR}/.qidi-plus-5-better-ui"
VER_FILE="${STATE_DIR}/version"
SELF="${STATE_DIR}/update.sh"

MODE="${1:-}"
QUIET=0
[ "$MODE" = "--quiet" ] && QUIET=1
say()  { [ "$QUIET" = 1 ] || printf '\n\033[0;36m%s\033[0m\n' "$*"; }
ok()   { [ "$QUIET" = 1 ] || printf '\033[0;32m%s\033[0m\n' "$*"; }
info() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }

SVC=/etc/systemd/system/qidi-plus-5-better-ui-update.service
TMR=/etc/systemd/system/qidi-plus-5-better-ui-update.timer

# Disabling the timer needs no network and must not re-apply anything.
if [ "$MODE" = "--uninstall-timer" ]; then
    sudo systemctl disable --now qidi-plus-5-better-ui-update.timer 2>/dev/null || true
    sudo rm -f "$SVC" "$TMR"
    sudo systemctl daemon-reload 2>/dev/null || true
    ok "Daily auto-update disabled"
    exit 0
fi

# --- locate a usable checkout (run from a clone, else download) --------------
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
src=""
if [ -f "${HERE}/klipper/apply.sh" ]; then
    src="$HERE"
else
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT INT TERM HUP
    say "Downloading ${REPO}@${BRANCH}..."
    curl -fsSL -m 90 "$TGZ" -o "$tmp/repo.tgz" || { echo "Download failed."; exit 1; }
    tar -xzf "$tmp/repo.tgz" -C "$tmp"
    src="$(find "$tmp" -maxdepth 1 -type d -name 'qidi-plus-5-better-ui-*' | head -n1)"
    [ -n "$src" ] || { echo "Could not unpack the repo."; exit 1; }
fi

remote_ver="$(tr -d '[:space:]' < "${src}/VERSION" 2>/dev/null || echo unknown)"
local_ver="$(cat "$VER_FILE" 2>/dev/null || echo none)"

if [ "$MODE" = "--check" ]; then
    say "installed: ${local_ver}   latest: ${remote_ver:-unknown}"
    [ "$local_ver" = "$remote_ver" ] && ok "Up to date." || info "Update available."
    exit 0
fi

say "qidi-plus-5-better-ui — installed: ${local_ver}   latest: ${remote_ver:-unknown}"

# --- apply the Klipper macro fixes (idempotent) ------------------------------
say "[1/2] Applying the latest Klipper preset"
sh "${src}/klipper/apply.sh"

# --- refresh the Plus 5 profile overlay (only if HelixScreen is present) -----
say "[2/2] Refreshing the QIDI Plus 5 profile overlay"
HS="${HOME_DIR}/helixscreen"
cfgd="${HOME_DIR}/printer_data/config/helixscreen"
if [ -d "$HS" ]; then
    mkdir -p "${cfgd}/printer_database.d" "${HS}/assets/config/presets" "${HS}/assets/images/printers"
    cp -f "${src}/files/printer_database.d/qidi-plus5.json" "${cfgd}/printer_database.d/qidi-plus5.json"
    cp -f "${src}/files/presets/qidi_plus5.json"            "${HS}/assets/config/presets/qidi_plus5.json"
    cp -f "${src}/files/images/printers/qidi-plus-5.png"    "${HS}/assets/images/printers/qidi-plus-5.png"
    info "profile overlay refreshed"
else
    info "HelixScreen not installed, skipped"
fi

# --- remember the version ----------------------------------------------------
mkdir -p "$STATE_DIR"
printf '%s\n' "${remote_ver:-unknown}" > "$VER_FILE"
[ -f "$SELF" ] || cp -f "${src}/update.sh" "$SELF" 2>/dev/null || true
ok "Up to date (${remote_ver:-unknown}). Klipper changes load at the next FIRMWARE_RESTART."

# --- daily auto-update timer (systemd) ---------------------------------------
if [ "$MODE" = "--install-timer" ]; then
    mkdir -p "$STATE_DIR"
    cp -f "${src}/update.sh" "$SELF"; chmod +x "$SELF"
    sudo tee "$SVC" >/dev/null <<UNIT
[Unit]
Description=QIDI Plus 5 better-UI — pull latest Klipper macro fixes + profile
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${KS_USER}
ExecStart=/bin/sh ${SELF} --quiet
UNIT
    sudo tee "$TMR" >/dev/null <<UNIT
[Unit]
Description=Daily QIDI Plus 5 better-UI update

[Timer]
OnBootSec=15min
OnUnitActiveSec=1d
Persistent=true
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
UNIT
    sudo systemctl daemon-reload
    sudo systemctl enable --now qidi-plus-5-better-ui-update.timer
    ok "Daily auto-update enabled (qidi-plus-5-better-ui-update.timer)"
fi
