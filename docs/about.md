# About

**Blume-kernel** is an automated kernel project for the Motorola Edge 40 Pro (rtwo) — Snapdragon 8 Gen 2 / SM8550.

The project is based on the original rtwo build system and is maintained by **joao-lisa**.

---

## Why

Stock kernels are fine. Custom kernels are fun. Automated builds are better.

The build system focuses on reproducible CI builds, GKI compatibility and KernelSU-Next integration.

---

## Stack

- Kernel: Motorola `SM8550` (`android13-5.15-lts` 5.15.225)
- Root: KernelSU-Next v3.4.2 / Vanilla
- SUSFS v2.4.0 for filesystem spoofing
- Extras: Droidspaces, NTSync, Baseband-Guard LSM, LRNG, BORE scheduler
- CI/CD: GitHub Actions — fully automated build, package, release, notify
- Built with GitHub Actions and the Android kernel toolchain.

---

## Support

You assume all risk by flashing this kernel.

Before asking for help, check [installation troubleshooting](installation.md) first and attach the relevant build log.

Use the repository issues for build and installation reports.

---

## Contact

- GitHub: [joao-lisa/Blume-kernel](https://github.com/joao-lisa/Blume-kernel)
