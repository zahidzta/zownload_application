# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "$(realpath "$0")")/../.." && pwd)"
task_work_root="$repository_root/work/android/gate-5a/5a-03-cpython"
source_document="$repository_root/docs/engine-sources.md"
lock_file="$task_work_root/runtime-lock.json"
build_log="$task_work_root/python-runtime-build.log"
target="aarch64-linux-android"
abi="arm64-v8a"
runtime_version="3.14.10"
runtime_api="24"
ndk_version="30.0.16248370"

mkdir -p "$task_work_root/source-inputs" "$task_work_root/native-sources" "$task_work_root/package-sources"
: > "$build_log"

on_error() {
    result=$?
    printf 'FAIL: CPython runtime build stopped at line %s (exit %s).\n' "$1" "$result" >&2
    tail -n 50 "$build_log" >&2 || true
    exit "$result"
}
trap 'on_error "$LINENO"' ERR

for command_name in bash curl git make patch python3 sha256sum tar wget; do
    command -v "$command_name" >/dev/null || { printf 'Missing host command: %s\n' "$command_name" >&2; exit 1; }
done

python3 - "$source_document" "$lock_file" <<'PY'
import json
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"(?ms)^```json android-python-runtime-lock\s*(.*?)^```", source)
if not match:
    raise SystemExit("Missing android-python-runtime-lock JSON fence")
lock = json.loads(match.group(1))
pathlib.Path(sys.argv[2]).write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
PY

lock_value() {
    python3 - "$lock_file" "$1" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1], encoding="utf-8"))
for key in sys.argv[2].split("."):
    value = value[int(key)] if isinstance(value, list) else value[key]
if isinstance(value, (dict, list)):
    raise SystemExit("Expected a scalar lock value")
print(value)
PY
}

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
[[ -n "$sdk_root" && -d "$sdk_root" ]] || { echo 'ANDROID_HOME or ANDROID_SDK_ROOT must point to the pinned SDK.' >&2; exit 1; }
export ANDROID_HOME="$sdk_root"
export ANDROID_SDK_ROOT="$sdk_root"
export ANDROID_API_LEVEL="$runtime_api"
export ANDROID_NDK_HOME="$sdk_root/ndk/$ndk_version"
export NDK_HOME="$ANDROID_NDK_HOME"
export HOST="$target"

ndk_properties="$ANDROID_NDK_HOME/source.properties"
[[ -f "$ndk_properties" ]] || { echo "Missing pinned NDK: $ndk_properties" >&2; exit 1; }
grep -Eq "^Pkg.Revision[[:space:]]*=[[:space:]]*$ndk_version$" "$ndk_properties" || {
    echo "Android NDK revision differs from $ndk_version." >&2
    exit 1
}

command_line_tools="$ANDROID_HOME/cmdline-tools/22.0"
[[ -x "$command_line_tools/bin/sdkmanager" ]] || { echo 'Pinned Command-Line Tools 22.0 are missing.' >&2; exit 1; }

safe_remove_task_output() {
    output_path="$(realpath -m "$1")"
    allowed_root="$(realpath -m "$task_work_root")"
    case "$output_path" in
        "$allowed_root"/*) rm -rf -- "$output_path" ;;
        *) echo "Refusing to remove output outside the task work directory: $output_path" >&2; exit 1 ;;
    esac
}

# CPython uses cmdline-tools/latest directly. Build through an isolated SDK
# view so an existing runner or developer SDK is left untouched.
android_sdk_view="$task_work_root/android-sdk-view"
safe_remove_task_output "$android_sdk_view"
mkdir -p "$android_sdk_view/cmdline-tools"
ln -s "$command_line_tools" "$android_sdk_view/cmdline-tools/latest"
for sdk_package in "build-tools/36.0.0" licenses "ndk/$ndk_version" platform-tools 'platforms/android-36'; do
    [[ -d "$sdk_root/$sdk_package" ]] || { echo "Pinned Android SDK package is missing: $sdk_root/$sdk_package" >&2; exit 1; }
    mkdir -p "$android_sdk_view/$(dirname "$sdk_package")"
    ln -s "$sdk_root/$sdk_package" "$android_sdk_view/$sdk_package"
done
export ANDROID_HOME="$android_sdk_view"
export ANDROID_SDK_ROOT="$android_sdk_view"

download_verified() {
    input_name="$1"
    input_url="$2"
    expected_sha="$3"
    input_path="$task_work_root/source-inputs/$input_name"
    if [[ ! -f "$input_path" ]]; then
        curl --fail --location --retry 5 --retry-all-errors --silent --show-error \
            --output "$input_path" "$input_url" >> "$build_log" 2>&1
    fi
    printf '%s  %s\n' "$expected_sha" "$input_path" | sha256sum --check --status
    printf '%s\n' "$input_path"
}

replace_once() {
    patch_file="$1"
    original_text="$2"
    replacement_text="$3"
    python3 - "$patch_file" "$original_text" "$replacement_text" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
old, new = sys.argv[2], sys.argv[3]
if content.count(old) != 1:
    raise SystemExit(f"Expected one occurrence of {old!r} in {path}")
path.write_text(content.replace(old, new), encoding="utf-8")
PY
}

printf 'Host: %s\n' "$(uname -a)" >> "$build_log"
printf 'Java: ' >> "$build_log"
java -version >> "$build_log" 2>&1
printf 'Python: %s\n' "$(python3 --version 2>&1)" >> "$build_log"
printf 'NDK: %s\n' "$ndk_version" >> "$build_log"

python_source_url="$(lock_value python.sourceUrl)"
python_source_sha="$(lock_value python.sha256)"
python_archive="$(download_verified "$(basename "$python_source_url")" "$python_source_url" "$python_source_sha")"
setuptools_source_url="$(lock_value pythonBuildTools.0.sourceUrl)"
setuptools_source_sha="$(lock_value pythonBuildTools.0.sha256)"
setuptools_source_archive="$(download_verified "$(basename "$setuptools_source_url")" "$setuptools_source_url" "$setuptools_source_sha")"
setuptools_wheel_url="$(lock_value pythonBuildTools.0.wheelUrl)"
setuptools_wheel_sha="$(lock_value pythonBuildTools.0.wheelSha256)"
setuptools_wheel="$(download_verified "$(basename "$setuptools_wheel_url")" "$setuptools_wheel_url" "$setuptools_wheel_sha")"

native_records="$task_work_root/native-dependencies.tsv"
python3 - "$lock_file" > "$native_records" <<'PY'
import json
import sys

lock = json.load(open(sys.argv[1], encoding="utf-8"))
for item in lock["nativeDependencies"]:
    print("\t".join(str(item[key]) for key in (
        "name", "version", "build", "sourceUrl", "sha256", "recipeTag", "recipeCommit", "recipeNdkFrom"
    )))
PY

python_source_root="$task_work_root/cpython/Python-$runtime_version"
if [[ ! -f "$python_source_root/Android/android.py" ]]; then
    mkdir -p "$task_work_root/cpython"
    tar -xJf "$python_archive" -C "$task_work_root/cpython" >> "$build_log" 2>&1
fi
[[ -f "$python_source_root/Android/android.py" ]] || { echo 'Pinned CPython source archive has an unexpected layout.' >&2; exit 1; }
if [[ ! -d "$python_source_root/.git" ]]; then
    git -C "$python_source_root" init --quiet >> "$build_log" 2>&1
fi
git -C "$python_source_root" add Android >> "$build_log" 2>&1

git -C "$python_source_root" restore --worktree -- Android/android-env.sh >> "$build_log" 2>&1
cpyt_nkd_old="$(lock_value python.ndkPatch.from)"
cpyt_nkd_new="$(lock_value python.ndkPatch.to)"
python_ndk_patch="$(lock_value python.ndkPatch.file)"
replace_once "$python_source_root/$python_ndk_patch" "$cpyt_nkd_old" "$cpyt_nkd_new"

dependency_ndk_new="$(lock_value sourceDependenciesRepository.ndkPatch.to)"
dependency_ndk_patch="$(lock_value sourceDependenciesRepository.ndkPatch.file)"
dependency_url="$(lock_value sourceDependenciesRepository.url)"
native_output_hashes="$task_work_root/native-output-hashes.tsv"
: > "$native_output_hashes"

recipe_tool_dir="$task_work_root/recipe-tools"
safe_remove_task_output "$recipe_tool_dir"
mkdir -p "$recipe_tool_dir"
cat > "$recipe_tool_dir/wget" <<'WGET'
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
set -euo pipefail
url="${!#}"
archive="$(basename "${url%%\?*}")"
if [[ -f "$PWD/$archive" ]]; then
    printf 'Using checksum-verified source archive %s\n' "$PWD/$archive"
    exit 0
fi
exec /usr/bin/wget "$@"
WGET
chmod +x "$recipe_tool_dir/wget"
export PATH="$recipe_tool_dir:$PATH"

while IFS=$'\t' read -r name version build source_url source_sha recipe_tag recipe_commit recipe_ndk_old; do
    [[ -n "$name" ]] || continue
    source_archive="$(download_verified "$(basename "$source_url")" "$source_url" "$source_sha")"
    recipe_root="$task_work_root/native-sources/$recipe_tag"
    if [[ ! -d "$recipe_root/.git" ]]; then
        git clone --filter=blob:none --depth 1 --branch "$recipe_tag" "$dependency_url" "$recipe_root" >> "$build_log" 2>&1
    else
        git -C "$recipe_root" restore --worktree --staged -- . >> "$build_log" 2>&1
        git -C "$recipe_root" fetch --depth 1 origin "refs/tags/$recipe_tag:refs/tags/$recipe_tag" >> "$build_log" 2>&1
        git -C "$recipe_root" checkout --detach "$recipe_commit" >> "$build_log" 2>&1
    fi
    actual_recipe_commit="$(git -C "$recipe_root" rev-parse HEAD)"
    [[ "$actual_recipe_commit" == "$recipe_commit" ]] || {
        echo "$recipe_tag resolved to $actual_recipe_commit, expected $recipe_commit." >&2
        exit 1
    }
    actual_tag_commit="$(git -C "$recipe_root" rev-parse "$recipe_tag^{commit}")"
    [[ "$actual_tag_commit" == "$recipe_commit" ]] || {
        echo "$recipe_tag tag does not match the approved recipe commit." >&2
        exit 1
    }

    recipe_env="$recipe_root/$dependency_ndk_patch"
    replace_once "$recipe_env" "$recipe_ndk_old" "$dependency_ndk_new"
    recipe_source_dir="$recipe_root/$name/build/$version"
    mkdir -p "$recipe_source_dir"
    recipe_source="$recipe_source_dir/$(basename "$source_url")"
    cp -- "$source_archive" "$recipe_source"
    printf 'Build source recipe %s at %s from %s\n' "$recipe_tag" "$recipe_commit" "$(basename "$source_url")"
    if (
        cd "$recipe_root" &&
        ./build.sh "$name" "$version" "$build" "$target"
    ) >> "$build_log" 2>&1; then
        :
    else
        printf 'Source recipe %s failed; last build log lines:\n' "$recipe_tag" >&2
        tail -n 50 "$build_log" >&2
        exit 1
    fi
    printf '%s  %s\n' "$source_sha" "$recipe_source" | sha256sum --check --status

    generated_archive="$recipe_root/$name/build/$version/$target/$recipe_tag-$target.tar.gz"
    [[ -f "$generated_archive" ]] || { echo "Source recipe did not emit $generated_archive." >&2; exit 1; }
    generated_sha="$(sha256sum "$generated_archive" | awk '{print $1}')"
    printf '%s\t%s\t%s\n' "$recipe_tag" "$generated_archive" "$generated_sha" >> "$native_output_hashes"
    cache_directory="$python_source_root/cross-build/downloads"
    mkdir -p "$cache_directory"
    cp -- "$generated_archive" "$cache_directory/$recipe_tag-$target.tar.gz"
done < "$native_records"

cross_build="$python_source_root/cross-build"
safe_remove_task_output "$cross_build/build"
safe_remove_task_output "$cross_build/$target"
mkdir -p "$cross_build/downloads"

printf 'Build pinned CPython %s for %s with the six source-built Android libraries.\n' "$runtime_version" "$target"
(
    cd "$python_source_root/Android"
    ./android.py build "$target"
) >> "$build_log" 2>&1

build_python="$cross_build/build/python"
target_prefix="$cross_build/$target/prefix"
[[ -x "$build_python" ]] || { echo 'CPython host build Python is missing.' >&2; exit 1; }
[[ -f "$target_prefix/lib/libpython3.14.so" ]] || { echo 'Android libpython3.14.so is missing.' >&2; exit 1; }
[[ "$("$build_python" --version 2>&1)" == "Python $runtime_version" ]] || { echo 'Host build Python version differs from the pin.' >&2; exit 1; }

"$build_python" -m ensurepip --upgrade --default-pip >> "$build_log" 2>&1
"$build_python" -m pip install --no-index --no-deps --no-compile "$setuptools_wheel" >> "$build_log" 2>&1
export PIP_NO_INDEX=1
export PIP_NO_DEPS=1
export _PYTHON_HOST_PLATFORM="android_${runtime_api}_arm64_v8a"

# Use CPython's patched Android compiler environment for every package build.
source "$python_source_root/Android/android-env.sh"
python_include="$target_prefix/include/python3.14"
export CFLAGS="$CFLAGS -I$python_include"
export CXXFLAGS="$CXXFLAGS -I$python_include"
export LDFLAGS="$LDFLAGS -L$target_prefix/lib -lpython3.14"
export LDSHARED="$CC -shared $LDFLAGS"

package_records="$task_work_root/python-packages.tsv"
python3 - "$lock_file" > "$package_records" <<'PY'
import json
import sys

lock = json.load(open(sys.argv[1], encoding="utf-8"))
for item in lock["pythonPackages"]:
    print("\t".join((item["name"], item["version"], item["sourceUrl"], item["sha256"])))
for key, name in (("ejs", "yt-dlp-ejs"), ("ytDlp", "yt-dlp")):
    item = lock[key]
    print("\t".join((name, item["version"], item["sourceUrl"], item["sha256"])))
PY

target_site="$target_prefix/lib/python3.14/site-packages"
mkdir -p "$target_site"
while IFS=$'\t' read -r package_name package_version package_url package_sha; do
    [[ -n "$package_name" ]] || continue
    package_archive="$(download_verified "$(basename "$package_url")" "$package_url" "$package_sha")"
    package_directory="$task_work_root/package-sources/$package_name-$package_version"
    safe_remove_task_output "$package_directory"
    mkdir -p "$package_directory"
    tar -xf "$package_archive" -C "$package_directory" >> "$build_log" 2>&1
    package_source="$(find "$package_directory" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    [[ -n "$package_source" ]] || { echo "No source directory found for $package_name." >&2; exit 1; }
    printf 'Install pinned source package %s %s without dependency resolution.\n' "$package_name" "$package_version"
    "$build_python" -m pip install --no-index --no-deps --no-build-isolation --no-compile \
        --target "$target_site" "$package_source" >> "$build_log" 2>&1
done < "$package_records"

python3 - "$lock_file" "$target_site" <<'PY'
import json
import pathlib
import re
import sys

lock = json.load(open(sys.argv[1], encoding="utf-8"))
site = pathlib.Path(sys.argv[2])
expected = {re.sub(r"[-_.]+", "-", p["name"]).lower(): p["version"] for p in lock["pythonPackages"]}
expected["yt-dlp-ejs"] = lock["ejs"]["version"]
expected["yt-dlp"] = lock["ytDlp"]["version"]
actual = {}
for metadata in site.glob("*.dist-info/METADATA"):
    fields = {}
    for line in metadata.read_text(encoding="utf-8", errors="replace").splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            if key in {"Name", "Version"}:
                fields[key] = value
    if "Name" in fields and "Version" in fields:
        actual[re.sub(r"[-_.]+", "-", fields["Name"]).lower()] = fields["Version"]
for name, version in expected.items():
    if actual.get(name) != version:
        raise SystemExit(f"Expected installed {name} {version}; found {actual.get(name)!r}")
print(f"Verified {len(expected)} pinned Python distributions in target site-packages.")
PY

python_extension_suffix="$("$build_python" -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))')"
python3 - "$target_site" "$python_extension_suffix" <<'PY'
import pathlib
import sys

site = pathlib.Path(sys.argv[1])
suffix = sys.argv[2]
if not suffix:
    raise SystemExit("The pinned host Python has no extension suffix")
for path in site.rglob("*.so"):
    if path.name.endswith(suffix):
        path.rename(path.with_name(path.name[:-len(suffix)] + ".so"))
PY

package_archive="$(find "$cross_build/$target/dist" -maxdepth 1 -type f -name "python-$runtime_version-$target.tar.gz" -print -quit)"
if [[ -z "$package_archive" ]]; then
    (
        cd "$python_source_root/Android"
        ./android.py package "$target"
    ) >> "$build_log" 2>&1
    package_archive="$(find "$cross_build/$target/dist" -maxdepth 1 -type f -name "python-$runtime_version-$target.tar.gz" -print -quit)"
fi
[[ -n "$package_archive" && -f "$package_archive" ]] || { echo 'CPython Android package archive was not produced.' >&2; exit 1; }

runtime_package="$task_work_root/runtime-package"
android_package="$task_work_root/android-package"
safe_remove_task_output "$runtime_package"
safe_remove_task_output "$android_package"
mkdir -p "$runtime_package" "$android_package/jniLibs/$abi" "$android_package/assets/python-runtime/lib"
tar -xzf "$package_archive" -C "$runtime_package" >> "$build_log" 2>&1

packaged_prefix="$runtime_package/prefix"
[[ -d "$packaged_prefix/lib/python3.14" ]] || { echo 'Packaged CPython standard library is missing.' >&2; exit 1; }
cp -a "$packaged_prefix/lib/python3.14" "$android_package/assets/python-runtime/lib/"
if [[ -d "$runtime_package/Android/python" ]]; then
    cp -a "$runtime_package/Android/python" "$android_package/assets/python-runtime/Android-python"
fi
find "$android_package/assets/python-runtime" -name '*.so*' -delete
find "$android_package/assets/python-runtime" -type d -name __pycache__ -prune -exec rm -rf -- {} +

while IFS= read -r -d '' native_file; do
    relative_path="$(python3 - "$native_file" "$packaged_prefix/lib" <<'PY'
import os
import sys
print(os.path.relpath(sys.argv[1], sys.argv[2]))
PY
)"
    install -D -m 755 "$native_file" "$android_package/jniLibs/$abi/$relative_path"
done < <(find "$packaged_prefix/lib" \( -type f -o -type l \) -name '*.so*' -print0)

readelf="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
[[ -x "$readelf" ]] || { echo 'Pinned NDK llvm-readelf is missing.' >&2; exit 1; }
native_libraries="$task_work_root/native-libraries.tsv"
: > "$native_libraries"
declare -A available_libraries=()
while IFS= read -r -d '' native_file; do
    available_libraries["$(basename "$native_file")"]=1
done < <(find "$packaged_prefix/lib" \( -type f -o -type l \) -name '*.so*' -print0)

system_libraries='libandroid.so libc.so libdl.so liblog.so libm.so libz.so libatomic.so libc++_shared.so libjnigraphics.so'
while IFS= read -r -d '' native_file; do
    header="$($readelf --file-header "$native_file")"
    grep -q 'Machine:.*AArch64' <<< "$header" || { echo "Non-arm64 native library: $native_file" >&2; exit 1; }
    needed="$($readelf --dynamic-table "$native_file" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')"
    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        case " $system_libraries " in
            *" $dependency "*) ;;
            *) [[ -n "${available_libraries[$dependency]:-}" ]] || { echo "$native_file needs unbundled $dependency." >&2; exit 1; } ;;
        esac
    done <<< "$needed"
    relative_path="$(python3 - "$native_file" "$packaged_prefix/lib" <<'PY'
import os
import sys
print(os.path.relpath(sys.argv[1], sys.argv[2]))
PY
)"
    native_sha="$(sha256sum "$native_file" | awk '{print $1}')"
    printf '%s\t%s\t%s\n' "$relative_path" "$native_sha" "$(tr '\n' ' ' <<< "$needed" | sed 's/[[:space:]]*$//')" >> "$native_libraries"
done < <(find "$packaged_prefix/lib" -type f -name '*.so*' -print0)

python3 - "$lock_file" "$package_archive" "$packaged_prefix" "$native_libraries" "$native_output_hashes" "$task_work_root/runtime-manifest.json" "$task_work_root" <<'PY'
import hashlib
import json
import pathlib
import sys

lock_path, archive_path, prefix_path, native_path, output_path, manifest_path, task_work_path = sys.argv[1:]
lock = json.load(open(lock_path, encoding="utf-8"))
archive = pathlib.Path(archive_path)
prefix = pathlib.Path(prefix_path)
task_work = pathlib.Path(task_work_path).resolve()

def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

native = []
for line in pathlib.Path(native_path).read_text(encoding="utf-8").splitlines():
    relative, sha, needed = line.split("\t", 2)
    native.append({"path": relative, "sha256": sha, "needed": needed.split() if needed else []})

native_outputs = []
for line in pathlib.Path(sys.argv[5]).read_text(encoding="utf-8").splitlines():
    tag, path, sha = line.split("\t")
    relative_path = pathlib.Path(path).resolve().relative_to(task_work)
    native_outputs.append({"recipeTag": tag, "path": str(relative_path), "sha256": sha})

packages = [{"name": p["name"], "version": p["version"], "sha256": p["sha256"]} for p in lock["pythonPackages"]]
packages.extend([
    {"name": "yt-dlp-ejs", "version": lock["ejs"]["version"], "sha256": lock["ejs"]["sha256"]},
    {"name": "yt-dlp", "version": lock["ytDlp"]["version"], "sha256": lock["ytDlp"]["sha256"]},
])
manifest = {
    "pythonVersion": lock["python"]["version"],
    "target": lock["python"]["androidHost"],
    "abi": lock["buildTools"]["abi"],
    "apiLevel": lock["python"]["apiLevel"],
    "ndk": lock["buildTools"]["ndk"],
    "packages": packages,
    "nativeOutputs": native_outputs,
    "nativeLibraries": native,
    "runtimeArchive": {"path": archive.name, "bytes": archive.stat().st_size, "sha256": digest(archive)},
}
pathlib.Path(manifest_path).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

cp "$task_work_root/runtime-manifest.json" "$android_package/assets/python-runtime/runtime-manifest.json"
runtime_sha="$(sha256sum "$package_archive" | awk '{print $1}')"
runtime_bytes="$(stat -c '%s' "$package_archive")"
printf 'PASS python-runtime: CPython %s, yt-dlp %s, EJS %s, ABI %s.\n' \
    "$runtime_version" "$(lock_value ytDlp.version)" "$(lock_value ejs.version)" "$abi"
printf 'Runtime archive %s bytes=%s sha256=%s\n' "$(basename "$package_archive")" "$runtime_bytes" "$runtime_sha"
printf 'Staged native libraries: %s\n' "$(wc -l < "$native_libraries" | tr -d ' ')"
printf 'Evidence manifest: %s\n' "$task_work_root/runtime-manifest.json"
