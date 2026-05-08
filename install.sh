#!/usr/bin/env bash
# Dudamel CLI installer — downloads the correct binary for your platform.
#
# Usage (public repo):
#   curl -fsSL https://raw.githubusercontent.com/agents-squad/dudamel/main/packages/cli/scripts/install.sh | bash
#
# Usage (private repo):
#   curl -fsSL -H "Authorization: token YOUR_GITHUB_PAT" \
#     https://raw.githubusercontent.com/agents-squad/dudamel/main/packages/cli/scripts/install.sh | GITHUB_TOKEN=YOUR_GITHUB_PAT bash

set -euo pipefail

REPO="agents-squad/dudamel"
BINARY_NAME="dudamel"
INSTALL_DIR="/usr/local/bin"
FALLBACK_DIR="${HOME}/.local/bin"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf "\033[1;34m→\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
err()   { printf "\033[1;31m✗\033[0m %s\n" "$1" >&2; }
die()   { err "$1"; exit 1; }

auth_header() {
  if [ -n "$GITHUB_TOKEN" ]; then
    echo "Authorization: token ${GITHUB_TOKEN}"
  else
    echo ""
  fi
}

# ── Detect OS and architecture ───────────────────────────────────────────────

detect_platform() {
  local os arch

  case "$(uname -s)" in
    Linux*)   os="linux" ;;
    Darwin*)  os="darwin" ;;
    *)        die "Unsupported OS: $(uname -s). Only Linux and macOS are supported." ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64)   arch="x64" ;;
    aarch64|arm64)   arch="arm64" ;;
    *)               die "Unsupported architecture: $(uname -m). Only x64 and arm64 are supported." ;;
  esac

  echo "${os}-${arch}"
}

# ── Resolve latest version ───────────────────────────────────────────────────

get_latest_version() {
  local url="https://api.github.com/repos/${REPO}/releases/latest"
  local header version

  header=$(auth_header)

  if command -v curl >/dev/null 2>&1; then
    if [ -n "$header" ]; then
      version=$(curl -fsSL -H "$header" "$url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    else
      version=$(curl -fsSL "$url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$header" ]; then
      version=$(wget -qO- --header="$header" "$url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    else
      version=$(wget -qO- "$url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    fi
  else
    die "Neither curl nor wget found. Please install one of them."
  fi

  if [ -z "$version" ]; then
    die "Could not determine the latest version. Check https://github.com/${REPO}/releases"
  fi

  echo "$version"
}

# ── Download binary ──────────────────────────────────────────────────────────

download_binary() {
  local platform="$1"
  local version="$2"
  local dest="$3"
  local filename="${BINARY_NAME}-${platform}"
  local header

  header=$(auth_header)

  info "Downloading ${filename} (${version})..."

  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT

  if [ -n "$GITHUB_TOKEN" ]; then
    # Private repo: resolve asset download URL via API
    local api_url="https://api.github.com/repos/${REPO}/releases/tags/${version}"
    local asset_url

    if command -v curl >/dev/null 2>&1; then
      asset_url=$(curl -fsSL -H "$header" "$api_url" \
        | grep -A 4 "\"name\": \"${filename}\"" \
        | grep '"url"' | head -1 \
        | sed 's/.*"url": *"\([^"]*\)".*/\1/')
    else
      asset_url=$(wget -qO- --header="$header" "$api_url" \
        | grep -A 4 "\"name\": \"${filename}\"" \
        | grep '"url"' | head -1 \
        | sed 's/.*"url": *"\([^"]*\)".*/\1/')
    fi

    if [ -z "$asset_url" ]; then
      die "Could not find asset ${filename} in release ${version}"
    fi

    # Download via API asset endpoint (follows redirect to S3)
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL -H "$header" -H "Accept: application/octet-stream" -o "$tmp" "$asset_url" \
        || die "Download failed. Asset: $filename"
    else
      wget -qO "$tmp" --header="$header" --header="Accept: application/octet-stream" "$asset_url" \
        || die "Download failed. Asset: $filename"
    fi
  else
    # Public repo: direct download
    local url="https://github.com/${REPO}/releases/download/${version}/${filename}"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL -o "$tmp" "$url" || die "Download failed. URL: $url"
    else
      wget -qO "$tmp" "$url" || die "Download failed. URL: $url"
    fi
  fi

  chmod +x "$tmp"
  mv "$tmp" "$dest"
  trap - EXIT
}

# ── Install ──────────────────────────────────────────────────────────────────

install_binary() {
  local dest

  if [ -w "$INSTALL_DIR" ]; then
    dest="${INSTALL_DIR}/${BINARY_NAME}"
  elif command -v sudo >/dev/null 2>&1; then
    info "Installing to ${INSTALL_DIR} (requires sudo)..."
    local tmp
    tmp=$(mktemp)
    download_binary "$1" "$2" "$tmp"
    sudo mv "$tmp" "${INSTALL_DIR}/${BINARY_NAME}"
    sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    return
  else
    mkdir -p "$FALLBACK_DIR"
    dest="${FALLBACK_DIR}/${BINARY_NAME}"
    info "No write access to ${INSTALL_DIR}, installing to ${FALLBACK_DIR}"
  fi

  download_binary "$1" "$2" "$dest"
}

# ── Check PATH ───────────────────────────────────────────────────────────────

check_path() {
  local dir="$1"
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$dir"; then
    echo ""
    printf "\033[1;33m⚠\033[0m  %s is not in your PATH.\n" "$dir"
    echo "   Add it to your shell profile:"
    echo ""
    echo "     export PATH=\"${dir}:\$PATH\""
    echo ""
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║     Dudamel — CLI Installer          ║"
  echo "  ╚══════════════════════════════════════╝"
  echo ""

  if [ -z "$GITHUB_TOKEN" ]; then
    info "No GITHUB_TOKEN set. If this is a private repo, export GITHUB_TOKEN first."
  fi

  local platform version
  platform=$(detect_platform)
  version=$(get_latest_version)

  ok "Platform: ${platform}"
  ok "Version:  ${version}"
  echo ""

  install_binary "$platform" "$version"

  # Verify
  local installed_path
  installed_path=$(command -v "$BINARY_NAME" 2>/dev/null || true)

  if [ -n "$installed_path" ]; then
    ok "Installed: ${installed_path}"
    echo ""
    "${BINARY_NAME}" --version 2>/dev/null || true
  else
    # Check if it's in the fallback dir
    if [ -x "${FALLBACK_DIR}/${BINARY_NAME}" ]; then
      ok "Installed: ${FALLBACK_DIR}/${BINARY_NAME}"
      check_path "$FALLBACK_DIR"
    elif [ -x "${INSTALL_DIR}/${BINARY_NAME}" ]; then
      ok "Installed: ${INSTALL_DIR}/${BINARY_NAME}"
    fi
  fi

  echo ""
  echo "  Next steps:"
  echo "    dudamel install    # Set up Dudamel"
  echo "    dudamel --help     # See all commands"
  echo ""
}

main
