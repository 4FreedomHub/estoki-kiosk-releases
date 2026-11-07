#!/bin/bash
# Builds the Estoki kiosk's SD card image: Raspberry Pi's newest Raspberry Pi OS (64-bit) with
# desktop, with install-kiosk.sh run inside it, so the first boot shows Link this kiosk.
#
#   sudo image/build.sh --tag v12-butterfree --out out/
#
# Runs as root on an arm64 Linux machine (GitHub's ubuntu-24.04-arm), so the image's own programs
# run natively in its chroot. It keeps the official image whole, cloud-init included, so Raspberry
# Pi Imager's settings (Wi-Fi, user, SSH, locale) still apply to it. Writes
# estoki-kiosk-<tag>.img.xz and estoki-kiosk-<tag>.json, the sizes and SHA-256 Imager's list needs.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE=$(dirname "$HERE")
BASE_URL=${ESTOKI_BASE_IMAGE_URL:-https://downloads.raspberrypi.com/raspios_arm64_latest}
# Room for the kiosk's venv; the first boot grows the system to fill the card anyway.
GROW=${ESTOKI_IMAGE_GROW:-1G}

tag=""
out=""
while [ $# -gt 0 ]; do
    case "$1" in
        --tag) tag=${2:-}; shift ;;
        --out) out=${2:-}; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$tag" ] && [ -n "$out" ] || { echo "Usage: build.sh --tag <tag> --out <dir>" >&2; exit 2; }
[[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "Not a release tag: $tag" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "Run it as root." >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "Build on an arm64 machine: the image's programs run here." >&2; exit 1; }

mkdir -p "$out"
out=$(cd "$out" && pwd)
work=$(mktemp -d "$out/.build.XXXXXX")
root=$work/root
loop=""

cleanup() {
    set +e
    if mountpoint -q "$root"; then
        umount --recursive "$root"
    fi
    [ -n "$loop" ] && losetup --detach "$loop"
    rm -rf "$work"
}
trap cleanup EXIT

step() { printf '\n==> %s\n' "$*"; }

step "The newest Raspberry Pi OS (64-bit) with desktop"
url=$(curl -fsSL --retry 3 -o "$work/base.img.xz" -w '%{url_effective}' "$BASE_URL")
base=$(basename "$url" .img.xz)
expected=$(curl -fsSL --retry 3 "$url.sha256" | awk '{print $1}')
echo "$expected  $work/base.img.xz" | sha256sum --check --quiet
echo "Base image: $base"
xz --decompress --stdout "$work/base.img.xz" > "$work/kiosk.img"
rm "$work/base.img.xz"

step "Room for the kiosk"
truncate --size="+$GROW" "$work/kiosk.img"
echo ', +' | sfdisk --no-reread --no-tell-kernel -N 2 "$work/kiosk.img"
loop=$(losetup --find --show --partscan "$work/kiosk.img")
# e2fsck exits 1 when it corrected something, which is still a clean file system.
e2fsck -fy "${loop}p2" || [ $? -le 1 ]
resize2fs "${loop}p2"

step "Inside the image"
mkdir -p "$root"
mount "${loop}p2" "$root"
mount "${loop}p1" "$root/boot/firmware"
for dir in dev dev/pts proc sys; do
    mount --bind "/$dir" "$root/$dir"
done
mount -t tmpfs tmpfs "$root/run"
mount -t tmpfs tmpfs "$root/tmp"
mv "$root/etc/resolv.conf" "$work/resolv.conf.image" 2>/dev/null || true
cp --dereference /etc/resolv.conf "$root/etc/resolv.conf"
# Packages installed in the chroot must not start their services on the build machine.
printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
chmod 755 "$root/usr/sbin/policy-rc.d"
mkdir -p "$root/tmp/estoki-setup"
cp -r "$SOURCE/image" "$SOURCE/deploy" "$root/tmp/estoki-setup/"

chroot "$root" /bin/bash /tmp/estoki-setup/image/install-kiosk.sh --image

step "The installed release runs"
chroot "$root" /opt/estoki-pi/current/venv/bin/estoki-pi --version
chroot "$root" env QT_QPA_PLATFORM=offscreen HOME=/root \
    /opt/estoki-pi/current/venv/bin/estoki-pi --self-check

step "Tidying the image"
chroot "$root" apt-get clean
rm -rf "$root/var/lib/apt/lists/"*
rm -f "$root/usr/sbin/policy-rc.d" "$root/etc/resolv.conf"
mv "$work/resolv.conf.image" "$root/etc/resolv.conf" 2>/dev/null || true
umount "$root/tmp" "$root/run"
for dir in sys proc dev/pts dev; do
    umount "$root/$dir"
done
# Unused blocks read back as zeros, so they compress to nothing.
fstrim "$root/boot/firmware" || true
fstrim "$root" || true
umount "$root/boot/firmware" "$root"
e2fsck -fy "${loop}p2" || [ $? -le 1 ]
losetup --detach "$loop"
loop=""

step "Compressing"
name=estoki-kiosk-$tag
mv "$work/kiosk.img" "$out/$name.img"
extract_size=$(stat --format=%s "$out/$name.img")
extract_sha256=$(sha256sum "$out/$name.img" | awk '{print $1}')
xz --threads=0 -6 --force "$out/$name.img"
download_size=$(stat --format=%s "$out/$name.img.xz")
download_sha256=$(sha256sum "$out/$name.img.xz" | awk '{print $1}')
cat > "$out/$name.json" <<JSON
{
  "tag": "$tag",
  "base": "$base",
  "image": "$name.img.xz",
  "extract_size": $extract_size,
  "extract_sha256": "$extract_sha256",
  "image_download_size": $download_size,
  "image_download_sha256": "$download_sha256",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
cat "$out/$name.json"
