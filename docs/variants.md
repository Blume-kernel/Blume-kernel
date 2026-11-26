# Variants & Features

## Variants

| Variant | Source | Root | Extras |
|---------|--------|------|--------|
| Blume-KSU-Next | ctOS SM8550 (5.15.226+ LTS) | KernelSU-Next v3.4.2 + SUSFS v2.4.0 | BBG |
| Blume-Vanilla | ctOS SM8550 (5.15.226+ LTS) | Vanilla | — |

All variants include: **WildKernels optimization patches** · **BBRv3 TCP** · **BORE scheduler** · **NTSync** · **LRNG** · **LZ4 ZRAM** · **Thin LTO** · **Droidspaces support**

---

## Droidspaces Support

This kernel ships with [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) container support.

Enabled configs: `SYSVIPC` · `IPC_NS` · `PID_NS` · `POSIX_MQUEUE` · `DEVTMPFS` · `BINFMT_MISC` · Netfilter extras

kABI fix applied for GKI < 6.12 to prevent vendor module crashes on boot.

> **SuSFS users:** disable **"HIDE SUS MOUNTS FOR ALL PROCESSES"** in SuSFS4KSU settings, otherwise containers will fail to start.

---

## Build Details

| | Blume-kernel |
|--|---------------------|
| Source | `ctOS-rtwo/android_kernel_motorola_sm8550` |
| Base commit | `13a9dd56c42b` (`android13-5.15-lts` 5.15.225 merge) |
| Config base | `gki_defconfig` |
| Platform fragment | `vendor/kalama_GKI.config` (if present) |
| Device fragments | `moto-kalama.config` · `moto-kalama-gki.config` · `moto-kalama-rtwo.config` |
| Toolchain | Neutron Clang (`06092026`) |
| LTO | Thin |
