# deploy/

Files installed on the Raspberry Pi, by `image/install-kiosk.sh`: inside the SD card image when it
is built, or on a Pi already running Raspberry Pi OS through `https://estokiapp.com/kiosk/install`.
What each one is and where it goes; `docs/PROVISIONING.md` is the guide for setting a kiosk up.

| File | Installed as | Owner, mode |
|---|---|---|
| `config.example.toml` | `/etc/estoki-pi/config.toml`, only to change a default | `root:estoki`, 640 |
| (written by the kiosk) | `/var/lib/estoki-pi/device.json`: its sign-in, once a household member links it | `estoki:estoki`, 600, in a directory `estoki:estoki` 700 |
| `updater.env.example` | `/etc/estoki-pi/updater.env`, only to change a default | `root:root`, 600 |
| `updater/estoki-pi-update` | `/usr/local/sbin/estoki-pi-update` | `root:root`, 755 |
| `updater/allowed_signers` | `/usr/local/share/estoki-pi/allowed_signers`: the key releases are signed with | `root:root`, 644 |
| `config.example.toml` | also `/usr/local/share/estoki-pi/config.example.toml`, to copy from | `root:root`, 644 |
| `systemd/estoki-pi-updater.service`, `.timer` | `/etc/systemd/system/`, the timer enabled | `root:root`, 644 |
| `firstboot/estoki-pi-firstboot` | `/usr/local/sbin/estoki-pi-firstboot`: once, after cloud-init, sets the kiosk user's autologin again and the Pi 5's `PSU_MAX_CURRENT=5000`, and restarts if either changed | `root:root`, 755 |
| `systemd/estoki-pi-firstboot.service` | `/etc/systemd/system/`, enabled; runs until `/var/lib/estoki-pi/firstboot-done` exists | `root:root`, 644 |
| `udev/90-estoki-backlight.rules` | `/etc/udev/rules.d/`: the `video` group may turn the backlight off | `root:root`, 644 |
| `polkit/50-estoki-pi-power-off.rules` | `/etc/polkit-1/rules.d/`: `estoki` may turn the Pi off, for Shut down on the kiosk's screen | `root:root`, 644 |
| `journald/50-estoki-pi.conf` | `/etc/systemd/journald.conf.d/`: the journal in memory (`Storage=volatile`, 32 MB), so logging doesn't write to the card | `root:root`, 644 |
| `kanshi/config` | `/home/estoki/.config/kanshi/config`, unless there is one: the Touch Display 2 in landscape | `estoki`, 644 |
| `systemd/estoki-pi.service` | `/etc/systemd/user/`, enabled for `estoki` only (a link in `~estoki/.config/systemd/user/graphical-session.target.wants/`) | `root:root`, 644 |
| `systemd/labwc-session.target` | `/etc/systemd/user/` | `root:root`, 644 |
| `labwc/autostart` | appended to `/home/estoki/.config/labwc/autostart` | `estoki`, 644 |
| `labwc/shutdown` | `/home/estoki/.config/labwc/shutdown` | `estoki`, 644 |

## What the updater makes

```
/opt/estoki-pi/
├── current -> releases/v2-ivysaur      the release the kiosk runs; switched in one rename
├── releases/
│   ├── v2-ivysaur/                      venv/, dist/ (the downloaded assets), release.json
│   └── v1-bulbasaur/                    the previous release, kept for --rollback
├── skipped-tags                         releases rolled back from, or that failed their smoke test
└── .update.lock
/var/cache/estoki-pi/pip/                pip's cache (wheels are still checked against the lock's hashes)
```

A release on 4FreedomHub/estoki-kiosk-releases must carry `estoki_pi-<VERSION_CODE>-py3-none-any.whl`,
`requirements.lock`, `manifest.json` and its signature `manifest.json.sig`; its
`estoki-kiosk-setup.tar.gz` (this folder and `image/`) is what `/kiosk/install` runs. The updater installs a release only when its version code is higher than the
installed one, and only switches to it after `estoki-pi --version` and `estoki-pi --self-check`
pass in the new venv.

## Assumptions about the Pi

- Raspberry Pi OS 64-bit **with desktop**, Debian 13 (trixie) based: its `python3` is 3.13 and
  its glibc is new enough for PySide6's `manylinux_2_39_aarch64` wheels. Bookworm (Python 3.11,
  glibc 2.36) cannot run this, and `install-kiosk.sh` refuses it.
- lightdm logs the user `estoki` in to the labwc desktop; `install-kiosk.sh` creates the user (no
  password, uid 1100 or above, in `input`, `dialout` and `video`) and sets `autologin-user`.
- The scanner as `[scanner] mode` finds it (`auto` by default): `docs/PROVISIONING.md` §4.

## Useful commands

```bash
sudo systemctl start estoki-pi-updater.service      # update now
journalctl -u estoki-pi-updater -e                  # what the updater did
sudo estoki-pi-update --check                       # what it would do
sudo estoki-pi-update --rollback                    # back to the previous release, and stay there
systemctl --user status estoki-pi                   # as estoki: the kiosk
journalctl --user -u estoki-pi -e                   # as estoki: the kiosk's log
```
