#!/bin/bash
# Turns Raspberry Pi OS (64-bit) with desktop, Trixie, into an Estoki kiosk, from the files in
# deploy/ beside this directory. The image build runs it inside the image (--image); bootstrap.sh
# runs it on a Pi that already has Raspberry Pi OS. Safe to run again: it only adds what is missing,
# and never overwrites the person's own settings.
#
#   install-kiosk.sh [--image] [--environment prod|dev]
#   install-kiosk.sh --check      only say whether this system can be a kiosk
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPLOY=${ESTOKI_DEPLOY_DIR:-$HERE/../deploy}
OS_RELEASE=${ESTOKI_OS_RELEASE:-/etc/os-release}
KIOSK_USER=estoki

image=false
check_only=false
environment=prod
while [ $# -gt 0 ]; do
    case "$1" in
        --image) image=true ;;
        --check) check_only=true ;;
        --environment) environment=${2:-}; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$environment" in
    prod|dev) ;;
    *) echo "--environment is prod or dev, not '$environment'." >&2; exit 2 ;;
esac

say() { printf '\n==> %s\n' "$*"; }
refuse() { printf 'This system cannot be an Estoki kiosk: %s\n' "$*" >&2; exit 1; }

# The kiosk needs Trixie's Python 3.13 and glibc, a 64-bit system for its PySide6 wheels, and the
# labwc desktop it runs in.
check_system() {
    local codename="" arch
    [ -r "$OS_RELEASE" ] || refuse "there is no $OS_RELEASE."
    # shellcheck source=/dev/null
    codename=$(. "$OS_RELEASE" && printf '%s' "${VERSION_CODENAME:-}")
    case "$codename" in
        trixie) ;;
        "") refuse "it does not say which Debian release it is. Use Raspberry Pi OS based on Debian 13 (trixie)." ;;
        *) refuse "it runs Debian '$codename'. Use Raspberry Pi OS based on Debian 13 (trixie)." ;;
    esac
    arch=${ESTOKI_ARCH:-$(dpkg --print-architecture)}
    [ "$arch" = "arm64" ] || refuse "it is $arch. Use Raspberry Pi OS (64-bit)."
    command -v "${ESTOKI_LABWC:-labwc}" >/dev/null 2>&1 \
        || refuse "it has no desktop. Use Raspberry Pi OS (64-bit) with desktop, not Lite."
}

check_system
if $check_only; then
    echo "This system can be an Estoki kiosk."
    exit 0
fi
[ "$(id -u)" -eq 0 ] || refuse "run it as root (sudo)."

home=/home/$KIOSK_USER

say "Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3-venv

say "The kiosk's user, $KIOSK_USER"
# The image's first-boot wizard would otherwise ask for a user before the kiosk could start.
if id rpi-first-boot-wizard >/dev/null 2>&1; then
    userdel --remove rpi-first-boot-wizard 2>/dev/null || userdel rpi-first-boot-wizard
fi
rm -f /etc/xdg/autostart/piwiz.desktop
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
    # Above 1000, which Raspberry Pi OS's tools take for the person's own user (made by Imager).
    useradd --create-home --shell /bin/bash --comment "Estoki kiosk" -K UID_MIN=1100 "$KIOSK_USER"
    # No password: it only ever logs in to the desktop by itself.
    passwd --lock "$KIOSK_USER"
fi
# input and dialout read the scanner as a keyboard or a serial port; video turns the backlight off.
usermod --append --groups input,dialout,video "$KIOSK_USER"

say "Desktop: log $KIOSK_USER in by itself, never blank"
SUDO_USER=$KIOSK_USER raspi-config nonint do_boot_behaviour B4
# Blanking on labwc is a swayidle line in the user's autostart (raspi-config's do_blanking); the
# kiosk sleeps the screen itself. raspi-config can't be asked: it picks labwc by a running labwc.
if [ -e "$home/.config/labwc/autostart" ]; then
    sed -i '/swayidle/d' "$home/.config/labwc/autostart"
fi
install -m 644 "$DEPLOY/udev/90-estoki-backlight.rules" /etc/udev/rules.d/90-estoki-backlight.rules
# Shut down on the kiosk's screen turns the Pi off as its user.
install -D -m 644 "$DEPLOY/polkit/50-estoki-pi-power-off.rules" \
    /etc/polkit-1/rules.d/50-estoki-pi-power-off.rules

say "The screen in landscape"
install -d -m 755 -o "$KIOSK_USER" -g "$KIOSK_USER" "$home/.config" "$home/.config/kanshi"
if [ ! -e "$home/.config/kanshi/config" ]; then
    install -m 644 -o "$KIOSK_USER" -g "$KIOSK_USER" "$DEPLOY/kanshi/config" "$home/.config/kanshi/config"
fi

say "The kiosk's files"
install -d -m 755 /etc/estoki-pi /opt/estoki-pi /var/cache/estoki-pi /usr/local/share/estoki-pi
install -d -m 700 -o "$KIOSK_USER" -g "$KIOSK_USER" /var/lib/estoki-pi
if [ "$environment" = dev ] && [ ! -e /etc/estoki-pi/config.toml ]; then
    printf 'environment = "dev"\n' > /etc/estoki-pi/config.toml
    chown root:"$KIOSK_USER" /etc/estoki-pi/config.toml
    chmod 640 /etc/estoki-pi/config.toml
fi
install -m 755 "$DEPLOY/updater/estoki-pi-update" /usr/local/sbin/estoki-pi-update
install -m 644 "$DEPLOY/updater/allowed_signers" /usr/local/share/estoki-pi/allowed_signers
install -m 644 "$DEPLOY/config.example.toml" /usr/local/share/estoki-pi/config.example.toml
install -m 755 "$DEPLOY/firstboot/estoki-pi-firstboot" /usr/local/sbin/estoki-pi-firstboot
install -m 644 "$DEPLOY/systemd/estoki-pi-updater.service" "$DEPLOY/systemd/estoki-pi-updater.timer" \
    "$DEPLOY/systemd/estoki-pi-firstboot.service" /etc/systemd/system/
install -m 644 "$DEPLOY/systemd/estoki-pi.service" "$DEPLOY/systemd/labwc-session.target" /etc/systemd/user/

say "Fewer writes to the card, so pulling the plug is safe"
install -D -m 644 "$DEPLOY/journald/50-estoki-pi.conf" /etc/systemd/journald.conf.d/50-estoki-pi.conf
rm -rf /var/log/journal
# The root file system without access times (Raspberry Pi OS's own default), and the kiosk user's
# caches (Qt's compiled QML among them) in memory.
cache=$home/.cache
"$HERE/kiosk-fstab.sh" /etc/fstab "$cache" "$(id -u "$KIOSK_USER")" "$(id -g "$KIOSK_USER")"
install -d -m 700 -o "$KIOSK_USER" -g "$KIOSK_USER" "$cache"

say "Start the kiosk with $KIOSK_USER's desktop"
install -d -m 755 -o "$KIOSK_USER" -g "$KIOSK_USER" "$home/.config/labwc"
autostart=$home/.config/labwc/autostart
if ! grep -qs 'labwc-session.target' "$autostart"; then
    cat "$DEPLOY/labwc/autostart" >> "$autostart"
    chown "$KIOSK_USER:$KIOSK_USER" "$autostart"
fi
install -m 644 -o "$KIOSK_USER" -g "$KIOSK_USER" "$DEPLOY/labwc/shutdown" "$home/.config/labwc/shutdown"
# What `systemctl --user enable estoki-pi.service` does, without the user's own systemd running.
wants=$home/.config/systemd/user/graphical-session.target.wants
install -d -m 755 -o "$KIOSK_USER" -g "$KIOSK_USER" "$home/.config/systemd" "$home/.config/systemd/user" "$wants"
ln -sfn /etc/systemd/user/estoki-pi.service "$wants/estoki-pi.service"
chown -h "$KIOSK_USER:$KIOSK_USER" "$wants/estoki-pi.service"

say "Updates, and what is left for the first boot"
systemctl enable estoki-pi-updater.timer estoki-pi-firstboot.service

say "The newest kiosk release"
ESTOKI_PI_PIP_CACHE=/var/cache/estoki-pi/pip /usr/local/sbin/estoki-pi-update
[ -e /opt/estoki-pi/current/venv/bin/estoki-pi ] || refuse "no kiosk release could be installed."

if $image; then
    # The image ships without the downloads: a kiosk only needs them again for the next release.
    rm -rf /var/cache/estoki-pi/pip
else
    systemctl daemon-reload
    systemctl start estoki-pi-updater.timer
    # The image does this on its first boot; here the restart below applies it.
    /usr/local/sbin/estoki-pi-firstboot
fi

say "Done"
if $image; then
    echo "The kiosk is installed in the image."
else
    echo "Restart the Pi to start the kiosk: sudo reboot"
fi
