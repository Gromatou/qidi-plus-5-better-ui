#!/bin/sh
# =============================================================================
#  QIDI Plus 5 — Klipper preset (idempotent, reversible, self-upgrading)
#  Run ON THE PRINTER:  sh apply.sh
#  Then restart Klipper: FIRMWARE_RESTART  (or reboot)
# =============================================================================
# Fixes three QIDI Plus 5 stock-firmware behaviours:
#   (a) a MANUAL bed mesh probed WITHOUT levelling the two Z motors -> one side
#       ~1mm higher. Now BED_MESH_CALIBRATE always runs G28(if needed) +
#       Z_TILT_ADJUST before probing.
#   (b) PRINT_START re-meshed on EVERY print. Now it loads the saved mesh
#       (bedmesh_before_print=False, and PRINT_END keeps it off: G31 -> G32).
#   (c) the slicer emits M106 P3 S255 at print start; the stock M106 macro then
#       turned the chamber heater OFF (TARGET=0), so a 50C chamber was killed
#       the instant printing began. Now the fan only stops an idle chamber.
#
# Backups: <file>.helixplus5.bak  (restore with revert.sh)
set -eu

CFG="${1:-$HOME/printer_data/config/klipper-macros-qd}"
[ -d "$CFG" ] || { echo "ERROR: Klipper macros dir not found: $CFG"; exit 1; }

python3 - "$CFG" <<'PY'
import sys, os, re, shutil
cfg = sys.argv[1]

def backup(p):
    b = p + ".helixplus5.bak"
    if not os.path.exists(b):
        shutil.copy2(p, b)

BLOCK_RE = re.compile(
    r'[ \t]*# >>> HelixScreen QIDI\+5 preset.*?'
    r'# <<< HelixScreen QIDI\+5 preset[^\n]*\n',
    re.DOTALL)

BLOCK = (
    "  # >>> HelixScreen QIDI+5 preset: level the Z motors before probing >>>\n"
    '  {% if printer.toolhead.homed_axes|string != "xyz" %}\n'
    "  G28\n"
    "  {% endif %}\n"
    "  Z_TILT_ADJUST\n"
    "  # <<< HelixScreen QIDI+5 preset <<<\n")

# --- (a) Z_TILT_ADJUST before probing, in BED_MESH_CALIBRATE ---------------
p = os.path.join(cfg, "bed_mesh.cfg")
s = open(p).read()
if BLOCK_RE.search(s):
    # upgrade/refresh an existing block in place
    s2 = BLOCK_RE.sub(BLOCK, s, count=1)
    if s2 != s:
        backup(p); open(p, "w").write(s2)
        print("bed_mesh.cfg   : block refreshed (upgraded)")
    else:
        print("bed_mesh.cfg   : already applied")
else:
    m = re.search(r'(?m)^[ \t]*BED_MESH_CHECK ABORT=1[ \t]*$', s)
    if not m:
        print("bed_mesh.cfg   : BED_MESH_CHECK anchor not found, SKIPPED")
    else:
        backup(p)
        s = s[:m.end()] + "\n" + BLOCK + s[m.end():]
        open(p, "w").write(s)
        print("bed_mesh.cfg   : added Z_TILT_ADJUST before probing")

# --- (b1) default: do not auto-mesh at print start -------------------------
p = os.path.join(cfg, "globals.cfg")
s = open(p).read()
if re.search(r'(?m)^variable_bedmesh_before_print:\s*True\s*$', s):
    backup(p)
    s = re.sub(r'(?m)^variable_bedmesh_before_print:\s*True\s*$',
               "variable_bedmesh_before_print:False", s, count=1)
    open(p, "w").write(s)
    print("globals.cfg    : bedmesh_before_print -> False")
else:
    print("globals.cfg    : already False")

# --- (b2) keep it off: PRINT_END G31 -> G32 --------------------------------
p = os.path.join(cfg, "start_end.cfg")
s = open(p).read()
if "HelixScreen QIDI+5 preset" in s:
    print("start_end.cfg  : already applied")
else:
    s2, n = re.subn(r'(?m)^([ \t]*)G31([ \t]*)$',
                    r'\1G32  # HelixScreen QIDI+5 preset: keep print-start mesh disabled',
                    s, count=1)
    if n:
        backup(p); open(p, "w").write(s2)
        print("start_end.cfg  : PRINT_END G31 -> G32")
    else:
        print("start_end.cfg  : no standalone G31 found, SKIPPED")

# --- (c) chamber circulation fan must not cut the chamber heater -----------
p = os.path.join(cfg, "fans.cfg")
s = open(p).read()
if "HelixScreen QIDI+5 preset: keep chamber heating" in s:
    print("fans.cfg       : already applied")
else:
    old_if = ('{% if printer["heater_generic chamber"] is defined '
              'and params.S|float >0.0 %}')
    new_if = ('{% if printer["heater_generic chamber"] is defined '
              'and params.S|float >0.0\n'
              '                and printer["heater_generic chamber"].target == 0 %}')
    if old_if in s:
        s2 = s.replace(old_if, new_if, 1).replace(
            "SET_HEATER_TEMPERATURE_SCALED HEATER=chamber TARGET=0",
            "SET_HEATER_TEMPERATURE_SCALED HEATER=chamber TARGET=0"
            "  # HelixScreen QIDI+5 preset: keep chamber heating", 1)
        backup(p); open(p, "w").write(s2)
        print("fans.cfg       : M106 P3 no longer cuts an actively-heated chamber")
    else:
        print("fans.cfg       : M106 P3 condition not found, SKIPPED")
PY

echo
echo "Done. Now reload Klipper so the changes take effect:"
echo "  - from HelixScreen/Fluidd: send  FIRMWARE_RESTART"
echo "  - or:  sudo systemctl restart klipper"
