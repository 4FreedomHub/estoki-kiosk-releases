#!/bin/bash
# Edits an fstab for the kiosk: the root file system without access times, and the kiosk user's
# cache directory in memory. Safe to run again; every other line is kept as it was.
#
#   kiosk-fstab.sh FSTAB CACHE_DIR UID GID
set -euo pipefail

fstab=$1 cache=$2 uid=$3 gid=$4
edited=$(awk '$1 !~ /^#/ && $2 == "/" && $4 !~ /(^|,)noatime(,|$)/ { $4 = $4 ",noatime" } { print }' "$fstab")
if ! awk -v cache="$cache" '$1 !~ /^#/ && $2 == cache { found = 1 } END { exit !found }' "$fstab"; then
    edited+=$'\n'"tmpfs $cache tmpfs nosuid,nodev,mode=0700,uid=$uid,gid=$gid,size=64m 0 0"
fi
printf '%s\n' "$edited" > "$fstab"
