#!/usr/bin/env bash
# Provision a GitHub-hosted Apple Silicon runner. Xcode is already installed.
set -euo pipefail

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  echo "ERROR: this workflow requires an Apple Silicon macOS runner" >&2
  exit 1
}
MODE="${1:?usage: setup-macos.sh llvm|app}"
case "$MODE" in
  llvm|app) ;;
  *) echo "ERROR: expected llvm or app" >&2; exit 1 ;;
esac

xcodebuild -version
xcrun --sdk iphoneos --show-sdk-path
df -h .

# LLVM 15 and the vendored dependencies predate CMake 4's policy removals.
# Keep this isolated from Homebrew's CMake and the system Python installation.
BUILD_TOOLS="${RUNNER_TEMP:?}/madeira-build-tools"
python3 -m venv "$BUILD_TOOLS"
"$BUILD_TOOLS/bin/python" -m pip install --disable-pip-version-check 'cmake==3.31.6'
echo "$BUILD_TOOLS/bin" >> "${GITHUB_PATH:?}"

if [[ "$MODE" == app ]]; then
  brew install ninja meson pkgconf autoconf automake libtool bison flex sevenzip llvm xxd
  echo 'MADEIRA_DEPS_READY=1' >> "${GITHUB_ENV:?}"
fi
command -v ninja

