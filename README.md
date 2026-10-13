# QIDI Plus 5 — HelixScreen + Klipper fixes

One-command setup to run **[HelixScreen](https://helixscreen.org)** on the QIDI
Plus 5's built-in 480×800 screen — replacing the stock QIDI UI — together with a
small **Klipper preset** that fixes two stock-firmware quirks.

> Unofficial. Verified on **QIDI Plus 5, firmware 01.01.01.07** (RK3308 host).
> Use at your own risk. Fully reversible.

## Install

SSH into the printer (stock user `qidi`, default password `qiditech`) and run:

```sh
ssh qidi@<PRINTER_IP>
curl -sSL https://raw.githubusercontent.com/Gromatou/qidi-plus-5-better-ui/main/install.sh | sh
```

Then pick **“QIDI Plus 5”** in the screen's first-run wizard.

### What the script does

1. **Applies the Klipper preset** (`klipper/apply.sh`) — see below.
2. **Installs / updates HelixScreen** with the [official installer](https://helixscreen.org).
   HelixScreen talks to Moonraker and renders on the framebuffer/DRM; it does not
   need X11 or Wayland, and it replaces the stock `qidi-client` screen app.
3. **Adds the QIDI Plus 5 profile** — a printer-database entry, a hardware preset
   and the product image — so the Plus 5 is detected and shows up *before* it
   ships in a HelixScreen release. (Once the upstream PR is in a release, this
   step is a no-op you can delete.)
4. Reloads Klipper (`FIRMWARE_RESTART`) and restarts the screen UI.

## The Klipper preset

`klipper/apply.sh` edits the stock `klipper-macros-qd/` macros (idempotent, with
`*.helixplus5.bak` backups):

1. **Level Z before a manual bed mesh.** A mesh launched by hand (HelixScreen /
   Fluidd / slicer) probed *without* levelling the two Z motors → one side ~1 mm
   higher. Now `BED_MESH_CALIBRATE` runs `G28` (if needed) + `Z_TILT_ADJUST`
   before probing, only outside a print (during a print `PRINT_START` already
   levelled).
2. **No re-mesh on every print.** `PRINT_START` re-probed the whole bed every job
   and `PRINT_END` re-armed it with `G31`. Now the default is off
   (`bedmesh_before_print:False`) and `PRINT_END` keeps it off (`G31`→`G32`), so
   print start **loads the saved mesh**. A hand mesh still works and is stored as
   profile `default`, which print start loads.

Revert just the Klipper edits: `sh klipper/revert.sh`.

### Why a script and not a `[include]`

Klipper parses configs with `configparser(strict=False)` and **merges same-named
sections** (last wins), so a second `[gcode_macro BED_MESH_CALIBRATE]`/`g29`
would *replace* QIDI's macro (losing its adaptive KAMP logic) instead of wrapping
it, and `rename_existing` cannot wrap a same-named section. Editing the QIDI files
in place is the clean way to change their behaviour.

## Uninstall

```sh
sh uninstall.sh                 # revert Klipper + remove the dropped Plus 5 profile
sh uninstall.sh --helixscreen   # also uninstall HelixScreen (restores the stock QIDI UI)
```

## Files

```
install.sh / uninstall.sh          one-command setup / teardown
klipper/apply.sh  klipper/revert.sh  the Klipper preset (idempotent, reversible)
files/printer_database.d/…         Plus 5 auto-detection entry (pre-release)
files/presets/qidi_plus5.json      Plus 5 hardware preset + display rotation
files/images/printers/…            Plus 5 product image
```

## Upstream

The QIDI Plus 5 printer profile is contributed to HelixScreen upstream
(`add QIDI Plus 5` PR). Once it ships in a release, `files/` and step 3 of the
installer become unnecessary.

## Caveats

- A **QIDI firmware update** overwrites the Klipper macros — re-run
  `klipper/apply.sh` afterwards.
- Installing HelixScreen replaces the stock screen app, so the QIDI cloud/app
  integration and its camera preview stop while it runs; uninstalling brings them
  back. Klipper, Moonraker, Fluidd (web) and printing are unaffected.
- Not affiliated with QIDI or HelixScreen.
