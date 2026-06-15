# yafancontrol — Yet Another Fan Control

A small fan-speed controller for **ThinkPad laptops**. ThinkPads cap the fan speed at a
conservative level to stay quiet, which causes heavy performance loss (thermal throttling) under
sustained load. `yafancontrol` lifts that cap based on temperature thresholds. Tested on a
ThinkPad X1 Extreme Gen 2 — let us know if you run it elsewhere. Please read the **Disclaimer**.

It reads the CPU temperature and the current fan RPM, and drives `/proc/acpi/ibm/fan` in a closed
loop: below `temp_kick_in` it leaves the fan in `auto` (quiet, firmware-managed); above it, it
toggles between `level 7` and `disengaged` to hold a temperature-derived RPM setpoint.

## Implementation

This is a **C program** (`yafancontrol.c`). It replaces the original bash script (kept as
`yafancontrol.sh` for reference): the bash loop forked `cat`/`grep`/`awk`/`sleep` five times every
second — a steady 1 Hz CPU spike. The C version reads sensors with `pread()` and sleeps with
`nanosleep()`, so one poll is a handful of syscalls and it **forks nothing**.

It also arms the `thinkpad_acpi` EC fan watchdog (120 s): if the daemon ever dies uncleanly, the
firmware resumes safe fan control within 120 s. On a clean stop it restores `level auto`.

Prerequisite: the `thinkpad_acpi` module must be loaded with `fan_control=1`
(`/sys/module/thinkpad_acpi/parameters/fan_control` = `Y`).

## Build & install

**Debian/Ubuntu (.deb):**
```sh
./debian-package.sh           # compiles yafancontrol.c, builds yafancontrol_<ver>.deb
sudo dpkg -i yafancontrol_1.2.deb
```

**openSUSE/Fedora (.rpm):**
```sh
./rpm-package.sh              # needs rpmbuild + gcc; builds from yafancontrol.spec
sudo rpm -i ~/rpmbuild/RPMS/*/yafancontrol-1.2-*.rpm
```

**Manual:**
```sh
cc -O2 -Wall -Wextra -o /usr/local/bin/yafancontrol yafancontrol.c
```

Both packages install the binary to `/usr/bin/yafancontrol`, the config to
`/etc/yafancontrol/yafancontrol.cfg`, and a `yafancontrol.service` unit, then enable and start it.

## Calibration

The control loop clamps its RPM setpoint to `fan_speed_min` (RPM at `level 7`) and `fan_speed_max`
(RPM at `disengaged`). These vary per machine. Measure them once:

```sh
sudo systemctl stop yafancontrol
sudo yafancontrol --calibrate     # ~30 s, spins the fan up, prints the two values
sudo systemctl start yafancontrol
```

Paste the printed `fan_speed_min` / `fan_speed_max` into `/etc/yafancontrol/yafancontrol.cfg`.
Until calibrated, the conservative defaults are used; they only matter once the temperature
exceeds `temp_kick_in`.

## Configuration — `/etc/yafancontrol/yafancontrol.cfg`

All temperatures are in millidegrees Celsius.

- `temp_raise` — above this, ramp the desired fan speed up.
- `temp_lower` — below this, ramp the desired fan speed down.
- `temp_kick_in` — above this, engage active fan control.
- `temp_kick_off` — below this, release back to `auto`.
- `verbosity` — 7 = standard messages, 8 = one line per second (spammy). See `journalctl -u yafancontrol`.
- `interval_ms` — poll interval in milliseconds (default 1000).
- `fan_speed_min` / `fan_speed_max` — RPM setpoint clamps; see **Calibration**.
- `temp_file` / `fan_file` — sensor and control paths (defaults suit ThinkPads).

## Disclaimer

Provided "as is" without warranty of any kind. The author and copyright holder, Thomas Hartwig, is
not responsible for any damages or issues arising from use. Use at your own risk.

## Note

Lenovo does not document what happens when running the fan beyond the standard threshold. In the
author's experience this is not an issue, but the disclaimer applies. Running the fan this high is
loud, and because it holds a fixed RPM it can pulse slightly. Licensed under Apache-2.0 (see `LICENSE`).
