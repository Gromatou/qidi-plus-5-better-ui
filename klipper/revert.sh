#!/bin/sh
# QIDI Plus 5 Klipper preset — revert. Restores the *.helixplus5.bak files.
# Run ON THE PRINTER:  sh revert.sh   then FIRMWARE_RESTART.
set -eu

CFG="${1:-$HOME/printer_data/config/klipper-macros-qd}"
[ -d "$CFG" ] || { echo "ERROR: Klipper macros dir not found: $CFG"; exit 1; }

found=0
for f in bed_mesh.cfg globals.cfg start_end.cfg fans.cfg; do
    p="$CFG/$f"
    if [ -f "$p.helixplus5.bak" ]; then
        cp -f "$p.helixplus5.bak" "$p"
        echo "restored $f"
        found=1
    fi
done
[ "$found" = 1 ] || echo "Nothing to revert (no .helixplus5.bak files)."
echo "Now reload Klipper: FIRMWARE_RESTART"
