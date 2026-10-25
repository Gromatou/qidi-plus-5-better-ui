#!/bin/sh
# =============================================================================
#  QIDI Plus 5 — Klipper preset (idempotent, reversible, self-upgrading)
#  Run ON THE PRINTER:  sh apply.sh
#  Then restart Klipper: FIRMWARE_RESTART  (or reboot)
# =============================================================================
# Fixes four QIDI Plus 5 stock-firmware behaviours:
#   (a) a MANUAL bed mesh probed WITHOUT levelling the two Z motors -> one side
#       ~1mm higher. Now BED_MESH_CALIBRATE always runs G28(if needed) +
#       Z_TILT_ADJUST before probing.
#   (b) PRINT_START re-meshed on EVERY print. Now it loads the saved mesh
#       (bedmesh_before_print=False, and PRINT_END keeps it off: G31 -> G32).
#   (c) the slicer emits M106 P3 S255 at print start; the stock M106 macro then
#       turned the chamber heater OFF (TARGET=0), so a 50C chamber was killed
#       the instant printing began. Now the fan only stops an idle chamber.
#   (d) M191 blocked until the chamber reached target. Now it only waits until
#       the chamber can still reach target within the first (uncooled) layers,
#       then finishes heating during the print. Tune: SET_CHAMBER_HEADSTART S=..
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

def save(p, text, crlf):
    # Keep the file's original line endings (the QIDI configs are CRLF).
    if crlf:
        text = text.replace("\r\n", "\n").replace("\n", "\r\n")
    open(p, "w", newline="").write(text)

def nrm(text, crlf):
    text = text.replace("\r\n", "\n")
    return text.replace("\n", "\r\n") if crlf else text

BLOCK_RE = re.compile(
    r'[ \t]*# >>> HelixScreen QIDI\+5 preset.*?'
    r'# <<< HelixScreen QIDI\+5 preset[^\n]*\n',
    re.DOTALL)

# Matches our whole m191 + chamber-soak block (for in-place upgrades).
SOAK_END = "# <<< HelixScreen QIDI+5 preset: chamber head-start soak <<<"
SOAK_RE = re.compile(r'(?ms)^\[gcode_macro m191\].*?^' + re.escape(SOAK_END) + r'[^\n]*\n')

BLOCK = (
    "  # >>> HelixScreen QIDI+5 preset: level the Z motors before probing >>>\n"
    '  {% if printer.toolhead.homed_axes|string != "xyz" %}\n'
    "  G28\n"
    "  {% endif %}\n"
    "  Z_TILT_ADJUST\n"
    "  # <<< HelixScreen QIDI+5 preset <<<\n")

# New m191 (smart chamber soak) + helpers, replacing the stock m191 section.
M191_NEW = '''[gcode_macro m191]
description: Sets chamber temperature, but only waits until the chamber can still
  reach the target within the first (uncooled) layers, then keeps heating during
  the print.   Usage: M191 [S<temp>] [HEADSTART=<sec>]
gcode:
  # Just fake the R parameter for the chamber.
  {% if printer["heater_generic chamber"] is defined %}
    {% if "R" in params %}
      {% set dummy = params.__setitem__("S", params.R) %}
    {% endif %}
    {% set target = params.S|default(0)|float %}
    {% set n = printer["gcode_macro _CHAMBER_CFG"].uncooled_layers|int %}
    {% set total_min = printer["gcode_macro _CHAMBER_CFG"].total_min|float %}
    {% set tlayers = printer.print_stats.info.total_layer|default(0)|int %}
    {% if params.HEADSTART is defined %}
      {% set headstart = params.HEADSTART|float %}
    {% elif printer["gcode_macro _CHAMBER_CFG"].headstart_sec|float > 0.0 %}
      {% set headstart = printer["gcode_macro _CHAMBER_CFG"].headstart_sec|float %}
    {% elif total_min > 0.0 and tlayers > 0 %}
      {% set headstart = [[n * (total_min * 60.0 / tlayers), 10.0]|max, 900.0]|min %}
    {% else %}
      {% set headstart = 0.0 %}
    {% endif %}
    {% if target > 0.0 %}
      SET_PRINT_SUB_STATUS SUB_STATUS=chamber_heating
      {% if printer["fan_generic chamber_circulation_fan"] is defined %}
        SET_FAN_SPEED FAN=chamber_circulation_fan SPEED=0
      {% endif %}
      SET_HEATER_TEMPERATURE_SCALED HEATER=chamber TARGET={target}
      {% if printer["heater_generic chamber"].temperature < target - 0.5 %}
        _CHAMBER_SOAK_SAMPLE
        G4 P{(printer["gcode_macro _CHAMBER_CFG"].sample_sec|float * 1000)|int}
        _CHAMBER_SOAK_DECIDE S={target} HEADSTART={headstart}
      {% endif %}
    {% endif %}
  {% endif %}

# >>> HelixScreen QIDI+5 preset: chamber head-start soak >>>
[gcode_macro _CHAMBER_CFG]
# Optional head-start override (seconds). 0 (default) = AUTO: derived from the
# slicer's own M73 remaining-time and the total layer count.
variable_headstart_sec: 0
# Safety margin applied to the estimated heat-up time (1.2 = +20%).
variable_margin: 1.2
# Measurement window (seconds) used to estimate the chamber heating rate.
variable_sample_sec: 15
# How many (uncooled) layers the chamber should be ready by.
variable_uncooled_layers: 3
# Filled automatically from M73 R (slicer remaining time, minutes).
variable_total_min: 0.0
# Last print filename seen, to reset the values above between prints.
variable_last_file: ""
gcode:

[gcode_macro _CHAMBER_SOAK_SAMPLE]
variable_t0: 0.0
gcode:
  SET_GCODE_VARIABLE MACRO=_CHAMBER_SOAK_SAMPLE VARIABLE=t0 VALUE={printer["heater_generic chamber"].temperature}

[gcode_macro _CHAMBER_SOAK_DECIDE]
gcode:
  {% set target = params.S|float %}
  {% set headstart = params.HEADSTART|default(printer["gcode_macro _CHAMBER_CFG"].headstart_sec)|float %}
  {% set margin = printer["gcode_macro _CHAMBER_CFG"].margin|float %}
  {% set sample = printer["gcode_macro _CHAMBER_CFG"].sample_sec|float %}
  {% set t0 = printer["gcode_macro _CHAMBER_SOAK_SAMPLE"].t0 %}
  {% set t1 = printer["heater_generic chamber"].temperature %}
  {% set rate = (t1 - t0) / sample if sample > 0.0 else 0.0 %}
  {% if rate > 0.02 and headstart > 0.0 %}
    {% set eta = (target - t1) / rate * margin %}
    {% set threshold = [[target - rate * headstart / margin, 0.0]|max, target]|min %}
    {% if eta <= headstart %}
      {% set dummy = action_respond_info("Chamber soak: ETA %.0fs (incl. %.0f%% margin) <= head-start %.0fs: printing now, chamber finishes during the first layers." % (eta, (margin - 1.0) * 100.0, headstart)) %}
    {% else %}
      {% set dummy = action_respond_info("Chamber soak: ETA %.0fs (incl. %.0f%% margin) > head-start %.0fs: waiting only until %.1f C." % (eta, (margin - 1.0) * 100.0, headstart, threshold)) %}
      TEMPERATURE_WAIT SENSOR="heater_generic chamber" MINIMUM={threshold}
    {% endif %}
  {% else %}
    {% if rate <= 0.02 %}
      {% set dummy = action_respond_info("Chamber soak: heating rate too low to estimate (%.3f C/s): waiting for the full target." % rate) %}
    {% else %}
      {% set dummy = action_respond_info("Chamber soak: no head-start set: waiting for the full target (stock behaviour).") %}
    {% endif %}
    TEMPERATURE_WAIT SENSOR="heater_generic chamber" MINIMUM={([target, 65]|min)-2}
  {% endif %}

[gcode_macro M73]
rename_existing: M73.6245197
gcode:
  {% set f = printer.print_stats.filename|default("") %}
  {% set new_print = f != printer["gcode_macro _CHAMBER_CFG"].last_file %}
  {% if new_print %}
    SET_GCODE_VARIABLE MACRO=_CHAMBER_CFG VARIABLE=last_file VALUE='"{f}"'
    SET_GCODE_VARIABLE MACRO=_CHAMBER_CFG VARIABLE=total_min VALUE=0.0
  {% endif %}
  {% set tmin = 0.0 if new_print else printer["gcode_macro _CHAMBER_CFG"].total_min|float %}
  {% if "R" in params and params.R|float > tmin %}
    SET_GCODE_VARIABLE MACRO=_CHAMBER_CFG VARIABLE=total_min VALUE={params.R|float}
  {% endif %}
  M73.6245197 P{params.P|default(0)} R{params.R|default(0)}

[gcode_macro SET_CHAMBER_HEADSTART]
description: Override the chamber head-start (seconds). 0 = auto (from M73).
gcode:
  SET_GCODE_VARIABLE MACRO=_CHAMBER_CFG VARIABLE=headstart_sec VALUE={params.S|float}
  {% set dummy = action_respond_info("Chamber head-start set to %.0fs." % (params.S|float)) %}
# <<< HelixScreen QIDI+5 preset: chamber head-start soak <<<
'''

# --- (a) Z_TILT_ADJUST before probing, in BED_MESH_CALIBRATE ---------------
p = os.path.join(cfg, "bed_mesh.cfg")
s = open(p, newline="").read()
crlf = "\r\n" in s
if crlf:
    s = s.replace("\r\n", "\n")
if BLOCK_RE.search(s):
    # upgrade/refresh an existing block in place
    s2 = BLOCK_RE.sub(BLOCK, s, count=1)
    if nrm(s2, crlf) != nrm(s, crlf):
        backup(p); save(p, s2, crlf)
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
        save(p, s, crlf)
        print("bed_mesh.cfg   : added Z_TILT_ADJUST before probing")

# --- (b1) default: do not auto-mesh at print start -------------------------
p = os.path.join(cfg, "globals.cfg")
s = open(p, newline="").read()
crlf = "\r\n" in s
if crlf:
    s = s.replace("\r\n", "\n")
if re.search(r'(?m)^variable_bedmesh_before_print:\s*True\s*$', s):
    backup(p)
    s = re.sub(r'(?m)^variable_bedmesh_before_print:\s*True\s*$',
               "variable_bedmesh_before_print:False", s, count=1)
    save(p, s, crlf)
    print("globals.cfg    : bedmesh_before_print -> False")
else:
    print("globals.cfg    : already False")

# --- (b2) keep it off: PRINT_END G31 -> G32 --------------------------------
p = os.path.join(cfg, "start_end.cfg")
s = open(p, newline="").read()
crlf = "\r\n" in s
if crlf:
    s = s.replace("\r\n", "\n")
if "HelixScreen QIDI+5 preset" in s:
    print("start_end.cfg  : already applied")
else:
    s2, n = re.subn(r'(?m)^([ \t]*)G31([ \t]*)$',
                    r'\1G32  # HelixScreen QIDI+5 preset: keep print-start mesh disabled',
                    s, count=1)
    if n:
        backup(p); save(p, s2, crlf)
        print("start_end.cfg  : PRINT_END G31 -> G32")
    else:
        print("start_end.cfg  : no standalone G31 found, SKIPPED")

# --- (c) chamber circulation fan must not cut the chamber heater -----------
p = os.path.join(cfg, "fans.cfg")
s = open(p, newline="").read()
crlf = "\r\n" in s
if crlf:
    s = s.replace("\r\n", "\n")
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
        backup(p); save(p, s2, crlf)
        print("fans.cfg       : M106 P3 no longer cuts an actively-heated chamber")
    else:
        print("fans.cfg       : M106 P3 condition not found, SKIPPED")

# --- (d) smart chamber soak: do not block on the full chamber heat-up -------
p = os.path.join(cfg, "heaters.cfg")
s = open(p, newline="").read()
crlf = "\r\n" in s
if crlf:
    s = s.replace("\r\n", "\n")
if SOAK_RE.search(s):
    s2 = SOAK_RE.sub(lambda _: M191_NEW, s, count=1)
    if nrm(s2, crlf) != nrm(s, crlf):
        backup(p); save(p, s2, crlf)
        print("heaters.cfg    : soak block refreshed (upgraded)")
    else:
        print("heaters.cfg    : already applied")
else:
    m = re.search(r'(?m)^\[gcode_macro m191\][^\n]*\n.*?(?=\n\[)', s, re.DOTALL)
    if not m:
        print("heaters.cfg    : m191 macro not found, SKIPPED")
    else:
        backup(p)
        save(p, s[:m.start()] + M191_NEW + s[m.end():], crlf)
        print("heaters.cfg    : m191 -> head-start chamber soak")
PY

echo
echo "Done. Now reload Klipper so the changes take effect:"
echo "  - from HelixScreen/Fluidd: send  FIRMWARE_RESTART"
echo "  - or:  sudo systemctl restart klipper"
