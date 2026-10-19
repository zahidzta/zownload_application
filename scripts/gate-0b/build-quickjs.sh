#!/usr/bin/env bash
# Build the attested upstream QuickJS archive on the requested Unix host.
set -euo pipefail

if [[ $# -ne 2 || "$1" != linux-x64 || "$2" != --verify ]]; then
  echo 'Usage: bash scripts/gate-0b/build-quickjs.sh linux-x64 --verify' >&2
  exit 2
fi

fail() { echo "QuickJS Linux build: $*" >&2; exit 1; }
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail 'requires a Linux x86_64 host'
[[ -f /etc/os-release ]] || fail 'cannot identify the Linux distribution'
# The Gate 0A Linux CI baseline is Ubuntu 24.04.
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || fail "requires Ubuntu 24.04, found ${PRETTY_NAME:-unknown}"
for tool in curl sha256sum tar make gcc-13 file; do
  command -v "$tool" >/dev/null || fail "missing build tool: $tool"
done
[[ "$(gcc-13 -dumpmachine)" == x86_64-linux-gnu ]] || fail 'gcc-13 does not target x86_64-linux-gnu'
[[ "$(gcc-13 -dumpfullversion)" == 13.* ]] || fail 'expected GCC 13'

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
archive="$repo_root/work/engine/downloads/quickjs-2026-06-04.tar.xz"
source_url='https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz'
source_hash='b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a'
build_dir="$repo_root/work/engine/build/quickjs/linux-x64"
mkdir -p "$(dirname "$archive")" "$build_dir"
build_dir="$(cd "$build_dir" && pwd -P)"
[[ "$build_dir" == "$repo_root/work/engine/build/quickjs/linux-x64" ]] || fail 'build directory resolves outside the workspace'
source_dir="$build_dir/quickjs-2026-06-04"
output="$build_dir/qjs"
log="$build_dir/build.log"
if [[ ! -f "$archive" ]]; then
  partial="$archive.partial.$$"
  trap 'rm -f -- "$partial"' EXIT
  curl --fail --location --silent --show-error --retry 3 --proto '=https' --proto-redir '=https' \
    --output "$partial" "$source_url"
  echo "$source_hash  $partial" | sha256sum --check --status || fail 'downloaded source SHA-256 mismatch'
  mv -- "$partial" "$archive"
  trap - EXIT
fi
echo "$source_hash  $archive" | sha256sum --check --status || fail 'source SHA-256 mismatch'

# A stable source path keeps GCC debug paths and the resulting binary hash
# identical across fresh runs. The resolved parent was checked above.
[[ "$source_dir" == "$build_dir/quickjs-2026-06-04" ]] || fail 'unsafe source path'
rm -rf -- "$source_dir"
tar -xf "$archive" -C "$build_dir"
[[ "$(cat "$source_dir/VERSION")" == 2026-06-04 ]] || fail 'source VERSION mismatch'
[[ -f "$source_dir/Makefile" ]] || fail 'upstream Makefile is missing'

make_args=(CC=gcc-13 HOST_CC=gcc-13 CONFIG_LTO= CONFIG_TEMPORAL_INTL=y qjs)
if ! make -C "$source_dir" "${make_args[@]}" >"$log" 2>&1; then
  tail -n 50 "$log" >&2
  fail "make failed; full log: $log"
fi
[[ -f "$source_dir/qjs" ]] || fail 'make did not produce qjs'
cp -- "$source_dir/qjs" "$output"
format="$(file -b "$output")"
[[ "$format" == *'ELF 64-bit'* && "$format" == *'x86-64'* ]] || fail "unexpected output format: $format"

# Upstream qjs reports its version on --help and exits with status 1.
set +e
help_text="$("$output" --help 2>&1)"
help_status=$?
set -e
[[ $help_status -eq 1 && "${help_text%%$'\n'*}" == 'QuickJS version 2026-06-04' ]] || fail 'qjs version check failed'
smoke="$("$output" -e 'print(1 + 1)')"
[[ "$smoke" == 2 ]] || fail "qjs smoke test failed: $smoke"

echo "Host: $PRETTY_NAME $(uname -m)"
echo "Source SHA-256: $source_hash"
echo "Compiler: $(gcc-13 --version | head -n 1) ($(gcc-13 -dumpmachine))"
echo "Build tool: $(make --version | head -n 1)"
echo "Make arguments: ${make_args[*]}"
echo "Compile command: $(grep -m 1 ' -c ' "$log")"
echo "Link command: $(grep -m 1 ' -o qjs ' "$log")"
echo "Output: $output"
echo "Output bytes: $(wc -c < "$output" | tr -d ' ')"
echo "Output SHA-256: $(sha256sum "$output" | cut -d ' ' -f 1)"
echo "Format: $format"
echo "Version: ${help_text%%$'\n'*}"
echo "Smoke script: print(1 + 1) => $smoke"
if [[ -n "${GITHUB_RUN_ID:-}" ]]; then echo "GitHub run ID: $GITHUB_RUN_ID"; fi
