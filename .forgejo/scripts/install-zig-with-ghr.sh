#!/usr/bin/env bash

set -euo pipefail

readonly GHR_VERSION="v0.8.1"
readonly GHR_LINUX_X64_SHA256="3c517e5d6feb891830a6c4a425181b5da04490f553373e5aef0688003a7451ff"
readonly GHR_LINUX_ARM64_SHA256="715188751ab2893d4478abd9cfc061f0a0547caec44af4fd7bdb4b937d577269"
readonly ZIG_MINISIGN_KEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

fail() {
    echo "error: $*" >&2
    exit 1
}

download() {
    local download_url="$1"
    local destination="$2"

    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --retry 3 \
            --output "$destination" "$download_url"
    elif command -v wget >/dev/null 2>&1; then
        wget --quiet --output-document="$destination" "$download_url"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$download_url" "$destination" <<'PY'
import sys
import urllib.request

url, destination = sys.argv[1:]
with urllib.request.urlopen(url) as response, open(destination, "wb") as output:
    while chunk := response.read(1024 * 1024):
        output.write(chunk)
PY
    elif command -v node >/dev/null 2>&1; then
        node - "$download_url" "$destination" <<'JS'
const fs = require("node:fs");
const { Readable } = require("node:stream");
const { pipeline } = require("node:stream/promises");

(async () => {
    const [url, destination] = process.argv.slice(2);
    const response = await fetch(url, { redirect: "follow" });
    if (!response.ok || !response.body) {
        throw new Error(`download failed: ${response.status} ${response.statusText}`);
    }
    await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(destination));
})().catch((error) => {
    console.error(error);
    process.exit(1);
});
JS
    else
        fail "curl, wget, Python 3, or Node.js is required to download ghr"
    fi
}

sha256() {
    local path="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$path" | awk '{print $NF}'
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$path" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as source:
    while chunk := source.read(1024 * 1024):
        digest.update(chunk)
print(digest.hexdigest())
PY
    elif command -v node >/dev/null 2>&1; then
        node - "$path" <<'JS'
const fs = require("node:fs");
const crypto = require("node:crypto");

(async () => {
    const digest = crypto.createHash("sha256");
    for await (const chunk of fs.createReadStream(process.argv[2])) {
        digest.update(chunk);
    }
    console.log(digest.digest("hex"));
})().catch((error) => {
    console.error(error);
    process.exit(1);
});
JS
    else
        fail "a SHA-256 implementation is required to verify ghr"
    fi
}

extract_archive() {
    local archive_path="$1"
    local destination_dir="$2"

    if command -v tar >/dev/null 2>&1; then
        if tar -tzf "$archive_path" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
            fail "ghr archive contains an unsafe path"
        fi
        tar -xzf "$archive_path" -C "$destination_dir"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$archive_path" "$destination_dir" <<'PY'
import inspect
import pathlib
import sys
import tarfile

archive, destination = sys.argv[1:]
root = pathlib.Path(destination).resolve()
with tarfile.open(archive, "r:gz") as package:
    for member in package.getmembers():
        target = (root / member.name).resolve()
        if root not in target.parents and target != root:
            raise RuntimeError(f"unsafe archive path: {member.name}")
    if "filter" in inspect.signature(package.extractall).parameters:
        package.extractall(root, filter="data")
    else:
        package.extractall(root)
PY
    else
        fail "tar or Python 3 is required to extract ghr"
    fi
}

case "$(uname -s)" in
    Linux) ;;
    *) fail "the zig-ci runner must use Linux" ;;
esac

case "$(uname -m)" in
    x86_64 | amd64)
        readonly GHR_TARGET="linux-musl-x64"
        readonly GHR_BUILD_TARGET="linux-x86_64-musl"
        readonly GHR_SHA256="$GHR_LINUX_X64_SHA256"
        ;;
    aarch64 | arm64)
        readonly GHR_TARGET="linux-musl-arm64"
        readonly GHR_BUILD_TARGET="linux-aarch64-musl"
        readonly GHR_SHA256="$GHR_LINUX_ARM64_SHA256"
        ;;
    *) fail "ghr v0.8.1 does not publish a Linux archive for $(uname -m)" ;;
esac

zig_version="$(
    sed -nE \
        's/^[[:space:]]*\.minimum_zig_version = "([^"]+)".*/\1/p' \
        build.zig.zon
)"
[[ "$zig_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] ||
    fail "could not derive one valid minimum_zig_version from build.zig.zon"

readonly workspace="${GITHUB_WORKSPACE:-$PWD}"
readonly state_root="$workspace/.ghr-ci"
readonly bootstrap_dir="$state_root/bootstrap"
readonly archive="$bootstrap_dir/ghr.tar.gz"
readonly extract_dir="$bootstrap_dir/extracted"
readonly version="${GHR_VERSION#v}"
readonly asset="ghr-${version}-${GHR_TARGET}.tar.gz"
readonly ghr_url="https://github.com/cataggar/ghr/releases/download/${GHR_VERSION}/${asset}"
readonly ghr="$extract_dir/ghr-${version}-${GHR_TARGET}/bin/ghr"

rm -rf "$state_root"
mkdir -p "$extract_dir"
download "$ghr_url" "$archive"

actual_sha256="$(sha256 "$archive")"
[[ "$actual_sha256" == "$GHR_SHA256" ]] ||
    fail "ghr archive SHA-256 mismatch: expected $GHR_SHA256, got $actual_sha256"

extract_archive "$archive" "$extract_dir"
[[ -x "$ghr" ]] || fail "verified ghr archive did not contain $ghr"
[[ "$("$ghr" version)" == "$version" ]] ||
    fail "bootstrapped ghr did not report version $version"
[[ "$("$ghr" version --target)" == "$GHR_BUILD_TARGET" ]] ||
    fail "bootstrapped ghr did not report target $GHR_BUILD_TARGET"

export GHR_TOOL_DIR="$state_root/tools"
export GHR_BIN_DIR="$state_root/bin"
export GHR_CACHE_DIR="$state_root/cache"
mkdir -p "$GHR_TOOL_DIR" "$GHR_BIN_DIR" "$GHR_CACHE_DIR"

# Forgejo's automatic GITHUB_TOKEN is not a GitHub credential.
unset GH_TOKEN GITHUB_TOKEN
"$ghr" install \
    "cataggar/zig@v${zig_version}" \
    "$ZIG_MINISIGN_KEY"

[[ -x "$GHR_BIN_DIR/zig" ]] || fail "ghr did not install Zig"
[[ "$("$GHR_BIN_DIR/zig" version)" == "$zig_version" ]] ||
    fail "installed Zig did not report version $zig_version"

path_file="${FORGEJO_PATH:-${GITHUB_PATH:-}}"
[[ -n "$path_file" ]] || fail "Forgejo did not provide a PATH environment file"
printf '%s\n' "$GHR_BIN_DIR" >> "$path_file"
