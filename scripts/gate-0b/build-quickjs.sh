#!/usr/bin/env bash
# Build the attested upstream QuickJS archive on the requested Unix host.
set -euo pipefail

if [[ $# -ne 2 || ( "$1" != linux-x64 && "$1" != macos-x64 ) || "$2" != --verify ]]; then
  echo 'Usage: bash scripts/gate-0b/build-quickjs.sh {linux-x64|macos-x64} --verify' >&2
  exit 2
fi

target="$1"
fail() { echo "QuickJS $target build: $*" >&2; exit 1; }
[[ "$(uname -m)" == x86_64 ]] || fail 'requires an x86_64 host'
for tool in curl tar make file awk; do
  command -v "$tool" >/dev/null || fail "missing build tool: $tool"
done
if [[ "$target" == linux-x64 ]]; then
  [[ "$(uname -s)" == Linux && -f /etc/os-release ]] || fail 'requires a Linux host with /etc/os-release'
  # The Gate 0A Linux CI baseline is Ubuntu 24.04.
  . /etc/os-release
  [[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || fail "requires Ubuntu 24.04, found ${PRETTY_NAME:-unknown}"
  for tool in sha256sum gcc-13; do command -v "$tool" >/dev/null || fail "missing build tool: $tool"; done
  compiler=gcc-13
  [[ "$($compiler -dumpmachine)" == x86_64-linux-gnu ]] || fail 'gcc-13 does not target x86_64-linux-gnu'
  [[ "$($compiler -dumpfullversion)" == 13.* ]] || fail 'expected GCC 13'
  host="$PRETTY_NAME $(uname -m)"
else
  [[ "$(uname -s)" == Darwin ]] || fail 'requires a macOS host'
  for tool in shasum xcodebuild xcrun; do command -v "$tool" >/dev/null || fail "missing build tool: $tool"; done
  # Select the Xcode version installed on the macos-15-intel CI image.
  export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
  [[ -d "$DEVELOPER_DIR" ]] || fail 'Xcode 16.4 is missing'
  [[ "$(xcodebuild -version)" == $'Xcode 16.4\nBuild version 16F6' ]] || fail 'expected Xcode 16.4 build 16F6'
  [[ "$(xcrun --sdk macosx --show-sdk-version)" == 15.5 ]] || fail 'expected macOS 15.5 SDK'
  export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
  [[ -f "$SDKROOT/usr/include/stdlib.h" ]] || fail 'macOS SDK headers are missing'
  compiler="$(xcrun --find clang)"
  [[ "$($compiler -dumpmachine)" == x86_64-apple-darwin* ]] || fail 'Apple Clang does not target macOS x86_64'
  host="macOS $(sw_vers -productVersion) $(uname -m)"
fi

hash_file() {
  if [[ "$target" == linux-x64 ]]; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
archive="$repo_root/work/engine/downloads/quickjs-2026-06-04.tar.xz"
source_url='https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz'
source_hash='b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a'
build_dir="$repo_root/work/engine/build/quickjs/$target"
mkdir -p "$(dirname "$archive")" "$build_dir"
build_dir="$(cd "$build_dir" && pwd -P)"
[[ "$build_dir" == "$repo_root/work/engine/build/quickjs/$target" ]] || fail 'build directory resolves outside the workspace'
source_dir="$build_dir/quickjs-2026-06-04"
output="$build_dir/qjs"
log="$build_dir/build.log"
if [[ ! -f "$archive" ]]; then
  partial="$archive.partial.$$"
  trap 'rm -f -- "$partial"' EXIT
  curl --fail --location --silent --show-error --retry 3 --proto '=https' --proto-redir '=https' \
    --output "$partial" "$source_url"
  [[ "$(hash_file "$partial")" == "$source_hash" ]] || fail 'downloaded source SHA-256 mismatch'
  mv -- "$partial" "$archive"
  trap - EXIT
fi
[[ "$(hash_file "$archive")" == "$source_hash" ]] || fail 'source SHA-256 mismatch'

# A stable source path keeps GCC debug paths and the resulting binary hash
# identical across fresh runs. The resolved parent was checked above.
[[ "$source_dir" == "$build_dir/quickjs-2026-06-04" ]] || fail 'unsafe source path'
rm -rf -- "$source_dir"
tar -xf "$archive" -C "$build_dir"
[[ "$(cat "$source_dir/VERSION")" == 2026-06-04 ]] || fail 'source VERSION mismatch'
[[ -f "$source_dir/Makefile" ]] || fail 'upstream Makefile is missing'

make_args=("CC=$compiler" "HOST_CC=$compiler" CONFIG_LTO= CONFIG_TEMPORAL_INTL=y)
if [[ "$target" == macos-x64 ]]; then
  # Keep the upstream debug flag and ask Apple's linker for stable output.
  make_args+=("LDFLAGS=-g -Wl,-reproducible")
fi
make_args+=(qjs)
if ! make -C "$source_dir" "${make_args[@]}" >"$log" 2>&1; then
  tail -n 50 "$log" >&2
  fail "make failed; full log: $log"
fi
[[ -f "$source_dir/qjs" ]] || fail 'make did not produce qjs'
cp -- "$source_dir/qjs" "$output"
format="$(file -b "$output")"
if [[ "$target" == linux-x64 ]]; then
  [[ "$format" == *'ELF 64-bit'* && "$format" == *'x86-64'* ]] || fail "unexpected output format: $format"
else
  [[ "$format" == *'Mach-O 64-bit executable x86_64'* ]] || fail "unexpected output format: $format"
fi

# Upstream qjs reports its version on --help and exits with status 1.
set +e
help_text="$("$output" --help 2>&1)"
help_status=$?
set -e
[[ $help_status -eq 1 && "${help_text%%$'\n'*}" == 'QuickJS version 2026-06-04' ]] || fail 'qjs version check failed'
smoke="$("$output" -e 'print(1 + 1)')"
[[ "$smoke" == 2 ]] || fail "qjs smoke test failed: $smoke"

echo "Host: $host"
echo "Source SHA-256: $source_hash"
if [[ "$target" == macos-x64 ]]; then
  echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "SDK: macOS $(xcrun --sdk macosx --show-sdk-version) ($SDKROOT)"
fi
echo "Compiler: $($compiler --version | head -n 1) ($($compiler -dumpmachine))"
echo "Build tool: $(make --version | head -n 1)"
echo "Make arguments: ${make_args[*]}"
echo "Compile command: $(grep -m 1 ' -c ' "$log")"
echo "Link command: $(grep -m 1 ' -o qjs ' "$log")"
echo "Output: $output"
echo "Output bytes: $(wc -c < "$output" | tr -d ' ')"
echo "Output SHA-256: $(hash_file "$output")"
echo "Format: $format"
if [[ "$target" == macos-x64 ]]; then
  for object in qjs repl quickjs dtoa libregexp libunicode cutils quickjs-libc; do
    echo "Object SHA-256 ($object): $(hash_file "$source_dir/.obj/$object.o")"
  done
  echo "Mach-O UUID: $(xcrun dwarfdump --uuid "$output")"
fi
echo "Version: ${help_text%%$'\n'*}"
echo "Smoke script: print(1 + 1) => $smoke"
if [[ -n "${GITHUB_RUN_ID:-}" ]]; then echo "GitHub run ID: $GITHUB_RUN_ID"; fi
