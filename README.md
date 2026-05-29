# Dudamel CLI Installer

Quick installer for the [Dudamel](https://github.com/agents-squad/dudamel) CLI.

## Install

```bash
curl -fsSL https://agents-squad.github.io/get-dudamel/install.sh | GITHUB_TOKEN=YOUR_TOKEN bash
```

> `GITHUB_TOKEN` requires `repo` scope (classic token) or `Contents: Read-only` (fine-grained token). [Create one here](https://github.com/settings/tokens/new?scopes=repo).

## What it does

1. Detects your OS (Linux/macOS) and architecture (x64/arm64)
2. Downloads the latest `dudamel` binary from GitHub Releases
3. Installs it to `/usr/local/bin` (or `~/.local/bin` if no write access)

## Next steps

```bash
dudamel install    # Interactive setup wizard
dudamel --help     # See all commands
```
