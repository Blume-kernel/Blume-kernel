#!/usr/bin/env bash
set -e

PINS_FILE="sources/source-pins.json"

_curl() { curl -s --retry 3 --retry-delay 2 "$@" || echo ""; }
_pin() { jq -r ".${1} // \"unknown\"" "$PINS_FILE" 2>/dev/null || echo "unknown"; }

KSUN_TAG=$(_curl "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/tags" | jq -r '.[0].name // "unknown"' 2>/dev/null || echo "unknown")
[ -n "$KSUN_TAG" ] || KSUN_TAG="unknown"

SUSFS_TAG=$(_curl "https://api.github.com/repos/sidex15/susfs4ksu-module/tags" | jq -r 'if type=="array" and length>0 then .[0].name else "unknown" end' 2>/dev/null || echo "unknown")
[ -n "$SUSFS_TAG" ] || SUSFS_TAG="unknown"

WILDKERNELS_COMMIT=$(_curl "https://api.github.com/repos/WildKernels/kernel_patches/commits/main" | jq -r '.sha // "unknown"' 2>/dev/null || echo "unknown")
[ -n "$WILDKERNELS_COMMIT" ] || WILDKERNELS_COMMIT="unknown"

PIN_MOTO_COMMIT=$(_pin "moto_commit")
[ "$PIN_MOTO_COMMIT" != "unknown" ] || PIN_MOTO_COMMIT="13a9dd56c42b7d708542afab690ee7e419f0dc3a"

MOTO_RAW=$(_curl "https://raw.githubusercontent.com/ctOS-rtwo/android_kernel_motorola_sm8550/${PIN_MOTO_COMMIT}/Makefile")
MOTO_SUB=$(echo "$MOTO_RAW" | awk -F' *= *' '/^VERSION / {v=$2} /^PATCHLEVEL / {p=$2} /^SUBLEVEL / {s=$2} END {if (v && p && s) print "v"v"."p"."s; else print "unknown"}')
MOTO_SUB="${MOTO_SUB:-unknown}"

SUSFS_KERNEL_VER=$(_curl "https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android13-5.15/kernel_patches/include/linux/susfs.h" | awk -F'"' '/^#define SUSFS_VERSION / {print $2; exit}')
SUSFS_KERNEL_VER="${SUSFS_KERNEL_VER:-v2.4.0}"

PIN_MOTO=$(_pin "moto_sublevel")
PIN_KSUN=$(_pin "ksun_tag")
PIN_SUSFS=$(_pin "susfs_tag")
PIN_SUSFS_KVER=$(_pin "susfs_kernel_version")
PIN_WILDKERNELS=$(_pin "wildkernels_commit")
UPDATES=()
[ "$MOTO_SUB" != "$PIN_MOTO" ] && UPDATES+=("moto: ${PIN_MOTO} -> ${MOTO_SUB}")
[ "$KSUN_TAG" != "$PIN_KSUN" ] && UPDATES+=("ksu-next: ${PIN_KSUN} -> ${KSUN_TAG}")
[ "$SUSFS_TAG" != "$PIN_SUSFS" ] && UPDATES+=("susfs: ${PIN_SUSFS} -> ${SUSFS_TAG}")
[ "$SUSFS_KERNEL_VER" != "$PIN_SUSFS_KVER" ] && UPDATES+=("susfs-kernel: ${PIN_SUSFS_KVER} -> ${SUSFS_KERNEL_VER}")
[ "$WILDKERNELS_COMMIT" != "$PIN_WILDKERNELS" ] && UPDATES+=("wildkernels: ${PIN_WILDKERNELS:0:9} -> ${WILDKERNELS_COMMIT:0:9}")

if [ "${#UPDATES[@]}" -gt 0 ]; then
  HAS_UPDATE="true"
  UPDATE_DETAIL=$(printf '%s\n' "${UPDATES[@]}")
else
  HAS_UPDATE="false"
  UPDATE_DETAIL=""
fi

{
  echo "CHECK_KSUN_TAG=$KSUN_TAG"
  echo "CHECK_SUSFS_TAG=$SUSFS_TAG"
  echo "CHECK_SUSFS_KERNEL_VER=$SUSFS_KERNEL_VER"
  echo "CHECK_WILDKERNELS_COMMIT=$WILDKERNELS_COMMIT"
  echo "CHECK_MOTO_SUB=$MOTO_SUB"
  echo "CHECK_MOTO_COMMIT=$PIN_MOTO_COMMIT"
  echo "HAS_UPDATE=$HAS_UPDATE"
  echo "UPDATE_DETAIL<<EOF"
  echo "$UPDATE_DETAIL"
  echo "EOF"
} >> "${GITHUB_ENV:-/dev/null}"

echo "[OK] Source check complete"
