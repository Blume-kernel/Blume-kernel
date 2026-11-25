#!/usr/bin/env bash
set -e

: "${KERNEL_SRC:?}"
: "${SOURCE_TYPE:?}"
: "${KSU_TYPE:?}"
: "${BUILD_TYPE:-stable}"
: "${WORK_DIR:=$GITHUB_WORKSPACE}"

source /tmp/apply_patch.sh
cd "$KERNEL_SRC"

WILDKERNELS_REF=$(jq -r '.wildkernels_commit // "main"' "$WORK_DIR/sources/source-pins.json" 2>/dev/null || echo "main")
WILDKERNELS_ROOT="https://raw.githubusercontent.com/WildKernels/kernel_patches/${WILDKERNELS_REF}"
WILDKERNELS_BASE="${WILDKERNELS_ROOT}/common"
WILDKERNELS_PATCHES=(
  add_limitation_scaling_min_freq.patch
  re_write_limitation_scaling_min_freq.patch
  silence_irq_cpu_logspam.patch
  silence_system_logspam.patch
  reduce_cache_pressure.patch
  minimise_wakeup_time.patch
  reduce_freeze_timeout.patch
  avoid_extra_s2idle_wake_attempts.patch
  adjust_cpu_scan_order.patch
  disable_cache_hot_buddy.patch
  increase_ext4_default_commit_age.patch
  add_timeout_wakelocks_globally.patch
  clear_page_16bytes_align.patch
  f2fs_enlarge_min_fsync_blocks.patch
  f2fs_reduce_congestion.patch
  file_struct_8bytes_align.patch
  force_tcp_nodelay.patch
  int_sqrt.patch
  IPv6_NAT_FIX.patch
  mem_opt_prefetch.patch
  optimized_mem_operations.patch
  optimise_memcmp.patch
  increase_sk_mem_packets.patch
  reduce_gc_thread_sleep_time.patch
  reduce_pci_pme_wakeups.patch
  unicode_bypass_fix_6.1-.patch
  use_unlikely_wrap_cpufreq.patch
)

for PATCH in "${WILDKERNELS_PATCHES[@]}"; do
  apply_patch "$WILDKERNELS_BASE/$PATCH" "${PATCH%.patch}"
done

apply_patch "${WILDKERNELS_ROOT}/gki_ptrace.patch" "gki_ptrace"
apply_patch "${WILDKERNELS_BASE}/bbrv3/0001-net-tcp-backport-BBRv3-to-android13-5.15-lts.patch" "bbrv3_android13-5.15-lts" "1"
apply_patch "${WILDKERNELS_BASE}/ntsync/ntsync_base.patch" "ntsync_base" "1"
apply_patch "${WILDKERNELS_BASE}/ntsync/ntsync_compat_android13-5.15.patch" "ntsync_compat_android13-5.15" "1"

PATCHES_DIR="$WORK_DIR/patches"
if [ -d "$PATCHES_DIR/common" ]; then
  for PATCH in "$PATCHES_DIR/common"/*.patch; do
    [ -f "$PATCH" ] || continue
    apply_patch "$PATCH" "$(basename "$PATCH" .patch)"
  done
fi

if [ -d "$PATCHES_DIR/${SOURCE_TYPE}-only" ]; then
  for PATCH in "$PATCHES_DIR/${SOURCE_TYPE}-only"/*.patch; do
    [ -f "$PATCH" ] || continue
    apply_patch "$PATCH" "$(basename "$PATCH" .patch)"
  done
fi

if [ "$BUILD_TYPE" = "testing" ] && [ -d "$PATCHES_DIR/testing" ]; then
  for PATCH in "$PATCHES_DIR/testing"/*.patch; do
    [ -f "$PATCH" ] || continue
    apply_patch "$PATCH" "$(basename "$PATCH" .patch)"
  done
fi

echo "[OK] All patches applied from WildKernels ${WILDKERNELS_REF}"
