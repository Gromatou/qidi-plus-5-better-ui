# QIDI Plus 5 — better UI + Klipper macro fixes

One-command setup to run **[HelixScreen](https://helixscreen.org)** on the QIDI
Plus 5's built-in 480×800 screen — replacing the stock QIDI UI — **plus a small,
community-maintained set of Klipper macro fixes** for real stock-firmware bugs.

> Unofficial. Verified on **QIDI Plus 5, firmware 01.01.01.07** (RK3308 host).
> Use at your own risk. Fully reversible.

## Install

SSH into the printer (stock user `qidi`, default password `qiditech`) and run:

```sh
ssh qidi@<PRINTER_IP>
curl -sSL https://raw.githubusercontent.com/Gromatou/qidi-plus-5-better-ui/main/install.sh | sh
```

Then pick **“QIDI Plus 5”** in the screen's first-run wizard. The installer also
switches on **auto-update at boot** (see below). To refresh by hand any time:

```sh
sh update.sh
```

---

## The Klipper macro fixes — the heart of this project

QIDI's stock macros have behaviours that bite heavily on this machine. Every fix
below is applied in place, is **idempotent**, keeps a `*.helixplus5.bak` backup,
and is **undone with one command** (`sh klipper/revert.sh`). They are the reason
this repo exists, and **more of them are very welcome — see [Contributing](#contributing).**

1. **Bed mesh without levelling Z → one side ~1 mm high.**
   A mesh launched by hand (from HelixScreen, Fluidd, or a slicer) probed the bed
   *without* levelling the two Z motors first, so the mesh was skewed. Now
   `BED_MESH_CALIBRATE` runs `G28` (only if unhomed) + `Z_TILT_ADJUST` before
   probing — automatically, only outside a print.

2. **Full re-mesh on every single print.**
   `PRINT_START` re-probed the whole bed for every job and `PRINT_END` re-armed it
   (`G31`). Now the default is off (`bedmesh_before_print: False`) and `PRINT_END`
   keeps it off (`G31`→`G32`), so a print start **loads the saved mesh** in
   seconds. A hand mesh still works and is stored as profile `default`.

3. **Chamber heater cut off the moment printing starts.**
   The slicer emits `M106 P3 S255` at print start, and the stock `M106` macro
   turned the chamber heater **off** whenever the circulation fan spun up
   (`SET_HEATER_TEMPERATURE_SCALED HEATER=chamber TARGET=0`). A 50 °C chamber was
   killed the instant the first layer began. The macro now only stops the chamber
   if it is **not** already heating, so the setpoint is respected during a print.

4. **Print start blocked until the chamber reached temperature.**
   `M191` waited for the chamber to *fully* heat before printing (minutes of dead
   time). Now it measures the chamber heating rate (with a **+20 % safety margin**)
   and only waits until the chamber can still reach target within the first
   (uncooled) layers — the chamber then finishes heating during those layers.
   The head-start is derived **automatically** from data the slicer already emits
   (`M73` remaining-time + total layer count), so **no slicer g-code change is
   needed**. Override it if you want (0 = auto):

   ```gcode
   SET_CHAMBER_HEADSTART S=180
   ```

```sh
ssh qidi@<PRINTER_IP>
sh klipper/revert.sh      # undo all macro edits (restores *.helixplus5.bak)
```

### Auto-update

New fixes are pulled straight from this repo by **`update.sh`**, which re-applies
the preset (idempotent) and refreshes the Plus 5 profile overlay:

```sh
sh update.sh                     # check + apply now
sh update.sh --check             # just show installed vs latest version
sh update.sh --enable-boot       # update automatically at every boot (needs sudo)
sh update.sh --disable-boot      # disable it
```

Auto-update is a **systemd oneshot service that runs at boot** (the QIDI host has
no `cron` daemon). It writes files only and **never restarts Klipper by itself** —
the macro changes take effect at the next `FIRMWARE_RESTART`, so a running print
is never disturbed. A handy side effect: after a QIDI firmware update wipes the
macros, the next reboot restores the fixes automatically. `install.sh` enables it
for you.

### QIDI Box (AMS, 4 spools)

The QIDI Box is auto-detected by Klipper only when `box.cfg` exists; the stock QIDI
UI normally writes it, so a HelixScreen install otherwise shows only "external
filament". To enable it from the shell:

```sh
sh klipper/enable-box.sh     # detects /dev/serial/by-id/usb-Klipper_QIDI_BOX_*
# then: FIRMWARE_RESTART
```

> **Box firmware must match the host.** An older Box MCU fails at startup with
> `mcu 'mcu_box1': Unknown command: irq_button_query`. The fix is the stock QIDI
> firmware update (it also flashes the Box, target `QD_PLUS5_BOX_02.03.01.21`).
> Only after that does `enable-box.sh` yield a working `multi_color_controller`
> (`hardware.box_count = 1`).

### Why a script and not a `[include]`

Klipper parses configs with `configparser(strict=False)` and **merges same-named
sections** (last wins), so a second `[gcode_macro BED_MESH_CALIBRATE]`/`g29`
would *replace* QIDI's macro (losing its adaptive KAMP logic) instead of wrapping
it, and `rename_existing` cannot wrap a same-named section. Editing the QIDI files
in place is the clean way to change their behaviour.

---

## What else the installer does

1. Applies the Klipper macro fixes above (`klipper/apply.sh`).
2. Installs / updates HelixScreen with the [official installer](https://helixscreen.org)
   (it talks to Moonraker and renders on the framebuffer/DRM — no X11/Wayland).
3. Adds the QIDI Plus 5 printer profile (database entry + preset + image) so the
   machine is detected *before* it ships in a HelixScreen release.
4. Reloads Klipper (`FIRMWARE_RESTART`) and restarts the screen UI.
5. Enables auto-update at boot.

## Uninstall

```sh
sh uninstall.sh                 # revert macros + remove the profile + disable auto-update
sh uninstall.sh --helixscreen   # also uninstall HelixScreen (restores the stock QIDI UI)
```

## Files

```
install.sh / uninstall.sh          one-command setup / teardown
update.sh                          auto-update (GitHub → machine) + boot service
klipper/apply.sh  klipper/revert.sh  the Klipper macro fixes (idempotent, reversible)
VERSION                            preset version, shown by update.sh --check
files/printer_database.d/…         Plus 5 auto-detection entry (pre-release)
files/presets/qidi_plus5.json      Plus 5 hardware preset + display rotation
files/images/printers/…            Plus 5 product image
```

## Contributing

**This is where the value is — please jump in.** The macros above are the real
payoff, and there is plenty more that could be fixed by people who know this
machine. Good first contributions:

- **A new macro fix.** Add a block to `klipper/apply.sh` that edits the QIDI
  macro in place, and register it in `klipper/revert.sh`. Keep it idempotent
  (re-running must be a no-op) and anchor it on a stable string.
- **Test on your firmware.** Confirmed working (or broken) on a firmware version
  other than `01.01.01.07`? Say so in an issue — it helps everyone.
- **Report a quirk.** If a stock limitation annoys you, open an issue even
  without a fix; that's how #1–#3 started.

Open an [issue](https://github.com/Gromatou/qidi-plus-5-better-ui/issues) or a
pull request — small, focused changes are easiest to review.

## Upstream

The QIDI Plus 5 printer profile is contributed to HelixScreen upstream
(`add QIDI Plus 5` PR). Once it ships in a release, `files/` and step 3 of the
installer become unnecessary.

## Caveats

- A **QIDI firmware update** overwrites the Klipper macros — run `sh update.sh`
  (or re-run `klipper/apply.sh`) afterwards.
- Installing HelixScreen replaces the stock screen app, so the QIDI cloud/app
  integration and its camera preview stop while it runs; uninstalling brings them
  back. Klipper, Moonraker, Fluidd (web) and printing are unaffected.
- Not affiliated with QIDI or HelixScreen.
