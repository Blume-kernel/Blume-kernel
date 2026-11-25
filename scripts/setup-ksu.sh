#!/usr/bin/env bash
set -e

: "${KSU_TYPE:?}"
: "${KERNEL_DIR:?}"
: "${WORK_DIR:?}"

git config --global init.defaultBranch main
git config --global advice.addEmbeddedRepo false

cd "$KERNEL_DIR"

_link_ksu_driver() {
  local DIR="$1"
  [ ! -L "drivers/kernelsu" ] && [ ! -d "drivers/kernelsu" ] && ln -sf "../${DIR}/kernel" drivers/kernelsu
  grep -q "obj-.*kernelsu" drivers/Makefile || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
  grep -q "kernelsu/Kconfig" drivers/Kconfig || echo 'source "drivers/kernelsu/Kconfig"' >> drivers/Kconfig
}

_inject_susfs_init() {
  local KSU_C="$1"
  [ -f "$KSU_C" ] || return 0
  grep -q "susfs_init" "$KSU_C" && return 0

  grep -q "#include <linux/susfs.h>" "$KSU_C" || sed -i '/#include <linux\/fs\.h>/a #include <linux\/susfs.h>/' "$KSU_C" || true
  grep -q "susfs_init()" "$KSU_C" || sed -i '/ksu_core_init();/a \\tsusfs_init();' "$KSU_C" || sed -i '/int __init ksu_init(/,/^}/{ /return 0;/i \\tsusfs_init(); }' "$KSU_C" || true
}

_pin_ksun_kbuild() {
  local KBUILD_FILE="$1" VER="$2" TAG="$3"
  [ -f "$KBUILD_FILE" ] || return 0
  python3 - "$KBUILD_FILE" "$VER" "$TAG" <<'PY'
import re, sys

path, ver, tag = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
pinned = (
    "obj-$(CONFIG_KSU) += kernelsu.o\n\n"
    "# Pinned version for Soong/Android ROM sandbox & embedded git tree builds\n"
    f"KSU_VERSION := {ver}\n"
    f"KSU_VERSION_TAG := {tag}\n"
    "$(info -- KernelSU-Next version: $(KSU_VERSION))\n"
    "$(info -- KernelSU-Next tag: $(KSU_VERSION_TAG))\n"
    "ccflags-y += -DKSU_VERSION=$(KSU_VERSION)\n"
    'ccflags-y += -DKSU_VERSION_TAG=\\"$(KSU_VERSION_TAG)\\"\n\n'
    "KSU_NEW_DCACHE_FLUSH"
)
new_txt, n = re.subn(
    r"obj-\$\(CONFIG_KSU\)\s*\+=\s*kernelsu\.o\n.*?KSU_NEW_DCACHE_FLUSH",
    lambda _: pinned,
    txt,
    count=1,
    flags=re.S,
)
if n:
    open(path, "w").write(new_txt)
PY
}

if [ "$KSU_TYPE" = "ksun" ]; then
  rm -rf ./KernelSU ./drivers/kernelsu ./KernelSU-Next
  curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh" | bash -s dev-susfs
  [ -d "KernelSU-Next" ] || { echo "[ERROR] KernelSU-Next not found"; exit 1; }

  PIN_KSUN_TAG=$(jq -r '.ksun_tag // "v3.4.2"' "$WORK_DIR/sources/source-pins.json" 2>/dev/null || echo "v3.4.2")
  cd KernelSU-Next
  git fetch --unshallow origin dev --tags 2>/dev/null || git fetch origin dev --tags 2>/dev/null || true
  BASE_COMMIT=$(git merge-base HEAD FETCH_HEAD 2>/dev/null || git merge-base HEAD origin/dev 2>/dev/null || echo "HEAD")
  KSUN_TAG=$(git describe --tags --abbrev=0 "$BASE_COMMIT" 2>/dev/null || echo "$PIN_KSUN_TAG")
  [ -n "$KSUN_TAG" ] && [ "$KSUN_TAG" != "unknown" ] || KSUN_TAG="$PIN_KSUN_TAG"
  _git_cnt=$(git rev-list --count "$BASE_COMMIT" 2>/dev/null || echo "")
  if [ -n "$_git_cnt" ] && [ "$_git_cnt" -gt 100 ] 2>/dev/null; then
    _ksun_ver=$(( 30000 + _git_cnt ))
  else
    _ksun_ver="33660"
  fi
  echo "KSUN_TAG=$KSUN_TAG" >> "${GITHUB_ENV:-/dev/null}"
  echo "$KSUN_TAG" > "$WORK_DIR/ksun_tag.txt"
  echo "${_ksun_ver}" > "$WORK_DIR/ksun_version.txt"
  cd ..

  _pin_ksun_kbuild "KernelSU-Next/kernel/Kbuild" "$_ksun_ver" "$KSUN_TAG"

  git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android13-5.15
  SUSFS_COMMIT=$(git -C susfs4ksu rev-parse --short HEAD 2>/dev/null || echo "unknown")
  echo "SUSFS_COMMIT=$SUSFS_COMMIT" >> "${GITHUB_ENV:-/dev/null}"

  SUSFS_PATCH="susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
  [ -f "$SUSFS_PATCH" ] || { echo "[ERROR] SUSFS patch not found: $SUSFS_PATCH"; exit 1; }
  patch -p1 --forward --fuzz=3 < "$SUSFS_PATCH"
  mkdir -p fs include/linux
  cp -f susfs4ksu/kernel_patches/fs/* fs/
  cp -f susfs4ksu/kernel_patches/include/linux/* include/linux/
  if [ -f "KernelSU-Next/kernel/core/init.c" ]; then
    _inject_susfs_init "KernelSU-Next/kernel/core/init.c"
  else
    _inject_susfs_init "KernelSU-Next/kernel/ksu.c"
  fi
  _link_ksu_driver "KernelSU-Next"
  rm -rf susfs4ksu KernelSU-Next/.git
fi

echo "[OK] KSU setup complete: $KSU_TYPE"
