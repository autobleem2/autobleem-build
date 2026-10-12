# CLAUDE.md - autobleem-build

Developer map of this repo. Usage of the image (build, run, what is where inside) is in
[`docker/README.md`](docker/README.md) and is not repeated here; the stage list is the header of
`docker/Dockerfile`. `README.md` at the root is a 7-line summary.

## What it is, who uses it

One Docker image, `ghcr.io/autobleem2/autobleem-build`, holding every compiler AutoBleem 2 is built with.
It is the single source of that image (`.github/workflows/image.yml` says the launcher's old copy of
`docker/` is retired). Users:

- The launcher's CI and its nightly/release builds: they compile inside `:develop` (nightlies) or `:latest`
  (`v*` releases) - see `image.yml` header.
- `docker/run.sh`: runs any command in the image with the current checkout mounted at its own path.
- This repo's own `.github/workflows/retroarch.yml`, which runs `ci/build_retroarch.sh` /
  `ci/build_cores.sh` in `ghcr.io/autobleem2/autobleem-build:latest`.
- autobleem-core's CI: no file here names that repo, so check its workflows for how it pulls the image.

## Layout

| Path | What |
|---|---|
| `docker/Dockerfile` | the multi-stage image; context is `docker/`, not the repo root |
| `docker/build-image.sh` | stages inputs, then `docker build`; the only supported way to build |
| `docker/run.sh` | `docker run` wrapper (calling uid, `AB_*` env, sccache mount, pcsx checkouts) |
| `docker/ab-validate.sh` | per-stage self-test, installed in the image as `ab-validate` |
| `docker/win-llvm.cmake` | toolchain file copied to `/opt/win-llvm.cmake` |
| `docker/runner/` | `compose.yml` + `.env.example` for the org-scoped self-hosted runner (label `psc-build`) |
| `toolchains/psc/`, `tools/check_psc_binary.sh`, `tools/check_needed.sh` | shared helpers baked in at `/opt/ab` |
| `cmake/generate_version.cmake` | read by a caller's CMake run in the image (Dockerfile line 55: it reads the checkout's `.git`, hence `safe.directory '*'`) |
| `ci/build_retroarch.sh`, `ci/build_cores.sh` | RetroArch cross-build / libretro cores tarballs for the download site |
| `.github/workflows/` | `image.yml` (publishes the image), `retroarch.yml`, `route.yml` (runner picker) |
| `.github/actions/` | `nightly-release`, `signpath-sign`: composite actions other repos call by `autobleem2/autobleem-build/...@develop` |
| `tools/lint.sh`, `format.sh`, `make_third_party_notices.py`, `defender_exclusions.ps1` | copied from the launcher tree; they name its paths (`lib_ableem/`, `build_win`, `E:\Programming\...`) and do nothing useful here |

There is no `ci/build.sh` and no `docs/` here, although `run.sh`, `docker/README.md` and the Dockerfile header
mention `ci/build.sh` and `docs/ci-plan.md`: they belong to the caller repos.

## Toolchains per target

Target names are those of the callers' `ci/build.sh` (not in this repo). Stage order:
base, native, pi, mingw, db, psc, retroarch, pcusb, all.

| Target | Compiler | Installed at | Checked by |
|---|---|---|---|
| native | host g++, clang-format/clang-tidy 22 (apt.llvm.org) | `/usr/bin`, links in `/usr/local/bin` | `ab-validate native` |
| psc | Debian Stretch gcc-6 (extracted), wrappers `armv8-sony-linux-gnueabihf-{gcc,g++,cpp}` | `/opt/psc/{bin,gcc-6,sysroot,sdl2,host}` | `psc-compiler`, `psc` |
| rpi | Debian `arm-linux-gnueabihf-*` (crossbuild-essential-armhf) | `/usr/bin`, SDL2 in `/usr/lib/arm-linux-gnueabihf` | `pi` |
| rpi64 | Debian `aarch64-linux-gnu-*` | `/usr/bin`, SDL2 in `/usr/lib/aarch64-linux-gnu` | `pi` |
| pcusb | Debian `i686-linux-gnu-*` (crossbuild-essential-i386) | `/usr/bin`, SDL2 in `/usr/lib/i386-linux-gnu` | `pcusb` (also runs the binary) |
| win | mingw-w64 posix `x86_64-w64-mingw32-g++-posix`, SDL2 from libsdl-org devel-mingw tarballs | `/usr/bin`, `/opt/mingw-sdl2` | `mingw` |
| win (UCRT) | llvm-mingw clang | `/opt/llvm-mingw`, `/opt/win-llvm.cmake` | nothing |

Other bits: cover databases `/opt/autobleem/db/`; sccache, proot + qemu-user-static, mtools/grub/e2fsprogs
1.47.2 (in `/usr/local`), p7zip, nsis in the `all` stage; the `retroarch` stage adds armhf/arm64 runtime dev
packages. The final `ENV` sets `AB_PSC_TOOLCHAIN`, `AB_MINGW_SDL2`, `AB_COVERS_DB_DIR`, `AB_BUILD_IMAGE_STAGE`.

## Build and test locally

```bash
docker/build-image.sh --channel develop      # -> autobleem-build:develop and :<git sha>; ~1 h cold
docker/build-image.sh --target psc           # up to one stage; name must be a stage in the Dockerfile
AB_BUILD_IMAGE=autobleem-build:develop docker/run.sh ci/build.sh native   # from a caller's checkout
for f in $(git ls-files '*.sh'); do bash -n "$f"; done                    # what the lint job runs
docker run --rm autobleem-build:develop ab-validate psc                   # rerun a stage check
```

The tests are the `RUN ab-validate <stage>` lines in the Dockerfile: a stage that fails its check fails the
build. Each check compiles a small SDL2/C++14 program the way the target is built; the PSC ones also cap
`GLIBC` at 2.24 and `GLIBCXX` at 3.4.22, reject RPATH/RUNPATH, and require SDL2 `libSDL2-2.0.so.0.18.0` with
Wayland and `wl_shell`, ALSA and no X11/OSS. Needs a Docker host and network (Stretch from archive.debian.org,
GitHub releases, apt.llvm.org); cover databases come from `--covers`, `$AB_COVERS_DIR`, `../db`, the old
build-server path, else `$AB_COVERS_URL` (default `https://autobleem.retromenele.pl/db`, sha256-checked).

## How a change is published

`.github/workflows/image.yml`: `lint` (hosted runner: `bash -n` of every `*.sh`, `docker build --check`) then
`image` on the self-hosted `psc-build` runner: `docker/build-image.sh --tag ghcr.io/autobleem2/autobleem-build
--channel <c>`, then `docker push` of `:<c>` and `:<short sha>`.

- push to `develop` -> `:develop`; push to `master` -> `:latest`; any other ref -> `:develop` as well.
- Triggers: push/PR on `docker/**`, `image.yml`, `tools/check_psc_binary.sh`, `tools/check_needed.sh`,
  `toolchains/psc/**`; or `workflow_dispatch` (`no_cache`, `push`).
- A pull request runs only `lint`; the image is never built for one. Jobs need repo variable `AB_CI_ENABLED=true`.
- After a successful `develop` push, `dispatch-nightly-refresh` triggers autobleem-main's `nightly.yml` with
  `rebuild_all=true`; with `AB_ADMIN_APP_ID` unset it only prints a notice.
- So: a PR into `develop` gets lint only; the merge publishes `:develop`; `:latest` appears only when
  `master` moves.

## Traps

- **Two meanings of `AB_BUILD_IMAGE`.** `build-image.sh` takes it as the repository name (default
  `autobleem-build`, tags are appended); `run.sh` takes it as the full reference (default
  `autobleem-build:latest`). After `--channel develop`, `run.sh` still uses `:latest` unless you set
  `AB_BUILD_IMAGE=autobleem-build:develop`. The `run.sh` header example names `ghcr.io/autobleem/...`; the
  published owner is `autobleem2`.
- **Staging lists in two places.** `build-image.sh` copies the `/opt/ab` helpers into `docker/ab-src/`; the
  `paths:` of `image.yml` must list the same sources (both files say so). `docker/db/` and `docker/ab-src/`
  are git-ignored; the build context is `docker/`, so a `COPY` of anything above it fails until staged.
- **A manual run from a feature branch pushes `:develop`** (the channel is "master or not"), unless `push` is
  unticked.
- **`ab-validate` usage text** omits `pcusb`, though the case exists. No check covers the `retroarch` stage,
  `/opt/llvm-mingw` or `win-llvm.cmake`; that file's find root is llvm-mingw's sysroot only, and no UCRT SDL2
  is installed by the Dockerfile.
- **`--target` list** in `docker/README.md` and `build-image.sh` stops at `all` and misses `retroarch`, `pcusb`.
  README's cover-database search also omits the `$AB_COVERS_URL` fallback.
- **PSC stage is fragile by design.** Stretch is fetched with signature and expiry checks off. Do not point the
  host's `/usr/arm-linux-gnueabihf` at the sysroot: Bookworm's Pi libc lives there. The linker-script rewrite
  uses `sed -i` and must stay limited to regular text files (an ELF `.so` was once truncated, silencing ALSA).
  Never add `LD_LIBRARY_PATH`: gcc-6's host binaries get a RUNPATH via `patchelf` instead.
- **SDL for the console is pinned twice**: `AUTOBLEEM_SDL_REF` (a commit of autobleem_sdl) and the
  `libSDL2-2.0.so.0.18.0` assertion in `ab-validate psc`; change both. SDL 2.0.20+ needs libwayland >= 1.18.
- **Layer order matters for cache**: `pcusb`, llvm-mingw and sccache are placed late on purpose; add new
  heavy layers after them. `LLVM_MINGW_VERSION` (20260922) 404s once upstream drops it.
- **`run.sh` details**: `cd`s to the repo root, so it mounts the checkout it lives in; it mounts a sibling
  `../pcsx-ab` / `../pcsx-ab2` / `../pcsx-rearmed-develop` and `../pcsx-abnxt` if present; `--userns` and
  `--privileged` are only for image builders; `AB_NO_SCCACHE=1` disables the cache mount.
- **`retroarch.yml`** publishes only when `AB_SITE_REFRESH_PUBLISH` is true or a manual run ticks `publish`;
  `build_cores.sh` downloads buildbot nightlies, so its output changes daily.
- **`route.yml`** routes only `develop` pushes to the `ab-main` laptop runner; everything else, and all PRs,
  go to `ubuntu-24.04`. `psc-build` is deliberately not offered (it cannot start `container:` jobs).
