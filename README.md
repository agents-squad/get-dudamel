# Dudamel CLI Installer

Quick installer for the [Dudamel](https://github.com/agents-squad/dudamel) CLI.

## Install

```bash
curl -fsSL https://agents-squad.github.io/get-dudamel/install.sh | bash
```

No GitHub token needed: the binaries are published as releases of this repo and the Docker
images on GHCR are public.

## What it does

1. Detects your OS (Linux/macOS) and architecture (x64/arm64)
2. Downloads the latest `dudamel` binary from this repo's releases (`cli-v*`)
3. Installs it to `/usr/local/bin` (or `~/.local/bin` if no write access)

## Next steps

```bash
dudamel install    # Interactive setup wizard
dudamel --help     # See all commands
```

## What lives here

This repo is the public face of Dudamel installs, kept in sync by the `cli-release.yml`
workflow of the (private) source repo. Do not edit these by hand:

- `install.sh`: served by GitHub Pages
- `config/`: the deploy config the in-instance updater syncs
- Releases: `cli-v*` (CLI binaries) and `vYYYY.MM.DD-N` (platform versions)
