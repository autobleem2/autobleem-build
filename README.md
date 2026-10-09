# autobleem-build

The toolchain image every AutoBleem 2 component compiles in (`docker/Dockerfile`).

- Rebuild locally: `docker/build-image.sh --channel develop` (add `--no-cache` for every layer).
- Published by `.github/workflows/image.yml` on a push to develop (`:develop`) or master (`:latest`) to `ghcr.io/autobleem2/autobleem-build`.
- Check the rootless Pi image tools: `docker run --rm autobleem-build:develop proot --version`, then the same with `qemu-aarch64-static --version` and `qemu-arm-static --version`.
