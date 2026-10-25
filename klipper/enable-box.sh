#!/bin/sh
# =============================================================================
#  QIDI Plus 5 — enable the QIDI Box (AMS, 4 spools)
# =============================================================================
#  Run ON THE PRINTER:  sh klipper/enable-box.sh
#  Then reload Klipper: FIRMWARE_RESTART
#
#  Requires the Box MCU firmware to match the host. An older Box firmware fails
#  at startup with:  mcu 'mcu_box1': Unknown command: irq_button_query
#  The stock QIDI firmware ships the Box image under ~/update
#  (QD_PLUS5_BOX_<version>.bin); update the firmware once, then run this.
#
#  Writes ~/printer_data/config/box.cfg from box.cfg.template (same layout the
#  stock QIDI client generates) and sets box_count=1 / enable_box=1 in
#  saved_variables.cfg. Backups: box.cfg.helixplus5.bak
# =============================================================================
set -eu

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
KS_USER="${KS_USER:-$(id -un)}"
HOME_DIR="$(getent passwd "$KS_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="$HOME"
CFG="${1:-$HOME_DIR/printer_data/config}"

BOX="$(ls /dev/serial/by-id/usb-Klipper_QIDI_BOX_* 2>/dev/null | head -1 || true)"
if [ -z "$BOX" ]; then
    echo "ERROR: no QIDI Box found (/dev/serial/by-id/usb-Klipper_QIDI_BOX_*)."
    echo "       Check the Box cable and power, then re-run."
    exit 1
fi
echo "Found QIDI Box: $BOX"

python3 - "$HERE/box.cfg.template" "$BOX" "$CFG" <<'PY'
import os, re, shutil, sys
tpl_path, serial, cfg = sys.argv[1:4]
text = open(tpl_path).read().replace("@BOX_SERIAL@", serial)
target = os.path.join(cfg, "box.cfg")

def write(path, data):
    try:
        with open(path, "w") as f:
            f.write(data)
    except PermissionError:
        tmp = "/tmp/.qidi-box-write"
        with open(tmp, "w") as f:
            f.write(data)
        os.system('sudo cp -f %s "%s" && sudo chown qidi:netdev "%s"'
                  % (tmp, path, path))

backup = target + ".helixplus5.bak"
if os.path.exists(target) and not os.path.exists(backup):
    try:
        shutil.copy2(target, backup)
    except PermissionError:
        os.system('sudo cp -f "%s" "%s"' % (target, backup))
write(target, text)
print("box.cfg        : written")

sv = os.path.join(cfg, "saved_variables.cfg")
if os.path.exists(sv):
    t = open(sv).read()
    t = re.sub(r"(?m)^box_count\s*=.*$", "box_count = 1", t)
    t = re.sub(r"(?m)^enable_box\s*=.*$", "enable_box = 1", t)
    write(sv, t)
    print("saved_variables: box_count=1, enable_box=1")
PY

echo
echo "Done. Now reload Klipper so the Box is initialised:"
echo "  - from HelixScreen/Fluidd:  FIRMWARE_RESTART"
echo "  - check:  printer.multi_color_controller  ->  hardware.box_count = 1"
