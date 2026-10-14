#!/bin/sh
# =============================================================================
#  QIDI Plus 5 — uninstall
#    sh uninstall.sh            # revert Klipper fixes + remove the dropped profile
#    sh uninstall.sh --helixscreen   # also uninstall HelixScreen (restores stock UI)
# =============================================================================
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
KS_USER="${KS_USER:-$(id -un)}"
HOME_DIR="$(getent passwd "$KS_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="$HOME"
HS_DIR="${HOME_DIR}/helixscreen"
HS_ASSETS="${HS_DIR}/assets"
HS_CONFIG="${HOME_DIR}/printer_data/config/helixscreen"

say() { printf '\n\033[0;36m%s\033[0m\n' "$*"; }

say "[1/3] Reverting the Klipper preset"
sh "${HERE}/klipper/revert.sh"

say "[2/3] Removing the QIDI Plus 5 profile files"
rm -f "${HS_CONFIG}/printer_database.d/qidi-plus5.json"
rm -f "${HS_ASSETS}/config/presets/qidi_plus5.json"
rm -f "${HS_ASSETS}/images/printers/qidi-plus-5.png"
echo "removed dropped profile files"

say "[3/3] Disabling the daily auto-update timer"
sudo systemctl disable --now qidi-plus-5-better-ui-update.timer 2>/dev/null || true
rm -f "$HOME_DIR/.qidi-plus-5-better-ui/update.sh"
sudo rm -f /etc/systemd/system/qidi-plus-5-better-ui-update.service \
           /etc/systemd/system/qidi-plus-5-better-ui-update.timer
sudo systemctl daemon-reload 2>/dev/null || true
echo "auto-update timer removed"

if [ "${1:-}" = "--helixscreen" ]; then
    say "Uninstalling HelixScreen (restores the stock QIDI UI)"
    curl -sSL https://releases.helixscreen.org/install.sh | sh -s -- --uninstall
fi

curl -s -m 10 -G "http://127.0.0.1:7125/printer/gcode/script" \
     --data-urlencode "script=FIRMWARE_RESTART" >/dev/null 2>&1 || true
echo "Done. Send FIRMWARE_RESTART if Klipper did not reload."
