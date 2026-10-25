#!/bin/sh
# =============================================================================
#  QIDI Plus 5 — install HelixScreen + the Klipper fixes (one command)
# =============================================================================
#  Run ON THE PRINTER as user 'qidi':
#
#      curl -sSL https://raw.githubusercontent.com/Gromatou/qidi-plus-5-better-ui/main/install.sh | sh
#  (or clone this repo and run:  sh install.sh)
#
#  What it does:
#    1. Applies the Klipper macro preset (Z-level before a manual mesh; no
#       re-mesh on every print; chamber heater stays on while printing).
#                                                        -> klipper/apply.sh
#    2. Installs (or updates) HelixScreen with the official installer.
#    3. Adds the QIDI Plus 5 printer profile (database entry + preset + image)
#       so it shows up and is detected BEFORE it ships in a HelixScreen release.
#    4. Reloads Klipper and the screen UI.
#    5. Enables auto-update at boot (a systemd oneshot service) that pulls
#       future macro fixes from GitHub.     -> update.sh   (disable: --disable-boot)
#
#  Idempotent. Re-running updates HelixScreen and re-checks the Klipper edits.
# =============================================================================
set -eu

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"

# Bootstrap so `curl ... | sh` works: fetch the repo when there is no checkout.
if [ ! -f "${HERE}/klipper/apply.sh" ]; then
    _tmp="$(mktemp -d)"
    echo "Fetching qidi-plus-5-better-ui..."
    curl -fsSL -m 90 \
        "https://github.com/Gromatou/qidi-plus-5-better-ui/archive/refs/heads/main.tar.gz" \
        -o "$_tmp/repo.tgz" || { echo "Download failed."; exit 1; }
    tar -xzf "$_tmp/repo.tgz" -C "$_tmp"
    exec sh "$_tmp/qidi-plus-5-better-ui-main/install.sh" "$@"
fi

KS_USER="${KS_USER:-$(id -un)}"
HOME_DIR="$(getent passwd "$KS_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="$HOME"
HS_DIR="${HOME_DIR}/helixscreen"
HS_ASSETS="${HS_DIR}/assets"
# HelixScreen 1.0.6+ keeps its writable config in helixscreen/config; older
# builds used printer_data/config/helixscreen. Use whichever exists.
HS_CONFIG="${HS_DIR}/config"
[ -d "$HS_CONFIG" ] || HS_CONFIG="${HOME_DIR}/printer_data/config/helixscreen"
PLAYER="${HOME_DIR}/QIDI_Client/bin/qidiclient"

say() { printf '\n\033[0;36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m%s\033[0m\n' "$*"; }

# --- sanity -------------------------------------------------------------------
[ -f "$PLAYER" ] || [ -d "${HOME_DIR}/QIDI_Client" ] || {
    echo "This does not look like a QIDI Plus 5 (no ~/QIDI_Client). Aborting."; exit 1; }

# =============================================================================
say "[1/5] Applying the Klipper preset"
sh "${HERE}/klipper/apply.sh"

# =============================================================================
say "[2/5] Installing / updating HelixScreen"
echo "      (sudo may ask for your password once — default 'qiditech')"
sudo -v 2>/dev/null || true
if [ -d "$HS_DIR" ]; then
    curl -sSL https://releases.helixscreen.org/install.sh | sh -s -- --update
else
    curl -sSL https://releases.helixscreen.org/install.sh | sh
fi
ok "HelixScreen installed"

# =============================================================================
say "[3/5] Adding the QIDI Plus 5 profile (pre-release)"
mkdir -p "${HS_CONFIG}/printer_database.d" "${HS_CONFIG}/presets" \
         "${HS_ASSETS}/config/presets" "${HS_ASSETS}/images/printers"
cp -f "${HERE}/files/printer_database.d/qidi-plus5.json" \
      "${HS_CONFIG}/printer_database.d/qidi-plus5.json"
cp -f "${HERE}/files/presets/qidi_plus5.json" "${HS_CONFIG}/presets/qidi_plus5.json"
cp -f "${HERE}/files/presets/qidi_plus5.json" "${HS_ASSETS}/config/presets/qidi_plus5.json"
cp -f "${HERE}/files/images/printers/qidi-plus-5.png" "${HS_ASSETS}/images/printers/qidi-plus-5.png"
ok "Plus 5 profile + preset + image in place"

# =============================================================================
say "[4/5] Reloading Klipper and the screen UI"
curl -s -m 10 -G "http://127.0.0.1:7125/printer/gcode/script" \
     --data-urlencode "script=FIRMWARE_RESTART" >/dev/null 2>&1 || true
sudo systemctl stop helixscreen 2>/dev/null || true
# The QIDI's 480x800 panel is mounted rotated; keep HelixScreen upright. Patch
# the saved setting while the app is stopped so it does not rewrite it on exit.
if [ -f "${HS_CONFIG}/settings.json" ]; then
    python3 - "${HS_CONFIG}/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.setdefault("display", {})["rotate"] = 90
d["display"]["rotation_probed"] = True
json.dump(d, open(p, "w"), indent=2)
print("rotation      : display.rotate=90")
PY
fi
sudo systemctl restart helixscreen 2>/dev/null || true

# =============================================================================
say "[5/5] Enabling auto-update at boot (admin rights needed)"
echo "      (enter your password if sudo asks — default is 'qiditech')"
if sh "${HERE}/update.sh" --enable-boot; then
    ok "Auto-update enabled at boot (systemd service)"
else
    echo "  skipped — enable later with:  sh update.sh --enable-boot"
fi

cat <<EOF

$(ok "Done.")
  - On the screen's first-run wizard, pick:  Qidi Plus 5
  - Do ONE manual mesh (Bed Mesh) so the saved profile exists — print start
    will then load it instead of re-probing.
  - Macro fixes are pulled from GitHub at every boot; apply one now with:
        sh update.sh
  - Disable auto-update:  sh update.sh --disable-boot
  - Revert the Klipper edits:   sh ${HERE}/klipper/revert.sh
  - Remove HelixScreen:         curl -sSL https://releases.helixscreen.org/install.sh | sh -s -- --uninstall
EOF
