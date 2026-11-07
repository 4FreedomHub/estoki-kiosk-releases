#!/bin/bash
# Makes a Pi already running Raspberry Pi OS into an Estoki kiosk, from the newest signed release:
#
#   curl -fsSL https://estokiapp.com/kiosk/install | sudo bash
#   curl -fsSL https://estokiapp.com/kiosk/install | sudo bash -s -- --environment dev
#
# It refuses anything but Raspberry Pi OS (64-bit) with desktop on Trixie, then downloads the newest
# release's manifest, its signature and the setup archive, runs the archive's install-kiosk.sh only
# when the signature is the release key's and the archive matches the manifest, and passes its own
# options on to it. The installer itself refuses to run without root.
set -euo pipefail

RELEASES=${ESTOKI_RELEASES_URL:-https://github.com/4FreedomHub/estoki-kiosk-releases/releases/latest/download}
OS_RELEASE=${ESTOKI_OS_RELEASE:-/etc/os-release}
# The release key, as in deploy/updater/allowed_signers; a test keeps the two the same.
ALLOWED_SIGNERS='estoki-kiosk-release namespaces="estoki-kiosk-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwxkHASpI9NwXmnuGJk6MZxhxuy5ew1ihRcddakcSgm estoki-kiosk-release'

refuse() { printf 'This system cannot be an Estoki kiosk: %s\n' "$*" >&2; exit 1; }

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
if [ "${ESTOKI_CHECK_ONLY:-}" = 1 ]; then
    echo "This system can be an Estoki kiosk."
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

echo "==> Downloading the newest kiosk release"
curl -fsSL --retry 3 -o manifest.json "$RELEASES/manifest.json"
curl -fsSL --retry 3 -o manifest.json.sig "$RELEASES/manifest.json.sig"
if [ -n "${ESTOKI_ALLOWED_SIGNERS_FILE:-}" ]; then
    cp "$ESTOKI_ALLOWED_SIGNERS_FILE" allowed_signers
else
    printf '%s\n' "$ALLOWED_SIGNERS" > allowed_signers
fi
ssh-keygen -Y verify -f allowed_signers -I estoki-kiosk-release -n estoki-kiosk-release \
    -s manifest.json.sig < manifest.json >/dev/null \
    || refuse "the release's signature does not check out. Try again in a few minutes."

setup_name=$(python3 -c '
import json
print((json.load(open("manifest.json")).get("setup") or {}).get("name", ""))
')
case "$setup_name" in
    ""|*/*|.*) refuse "the newest release has no setup archive." ;;
esac
curl -fsSL --retry 3 -o "$setup_name" "$RELEASES/$setup_name"
python3 -c '
import hashlib, json, sys
expected = json.load(open("manifest.json"))["setup"]["sha256"]
sys.exit(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest() != expected)
' "$setup_name" || refuse "the setup archive does not match the signed manifest. Try again in a few minutes."

mkdir setup
tar -xzf "$setup_name" -C setup
bash setup/image/install-kiosk.sh "$@"
