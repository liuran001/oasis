#!/bin/sh
set -eu

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "$#" -eq 6 ] || fail "usage: $0 <version> <target> <subtarget> <package-arch> <ipk|apk> <work-directory>"

VERSION=$1
TARGET=$2
SUBTARGET=$3
PACKAGE_ARCH=$4
FORMAT=$5
WORK_DIR=$6
[ "$FORMAT" = "ipk" ] || [ "$FORMAT" = "apk" ] || fail "unsupported package format: $FORMAT"
[ -n "${PACKAGES:-}" ] || fail "PACKAGES must contain the packages to build"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE_DIR=${OASIS_SDK_CACHE:-"$WORK_DIR/sdk-cache"}
DOWNLOAD_DIR="$WORK_DIR/download"
SDK_ROOT="$WORK_DIR/sdk"
OUT_DIR="$WORK_DIR/out"
BASE_URL="https://downloads.openwrt.org/releases/$VERSION/targets/$TARGET/$SUBTARGET"
SUMS_FILE="$CACHE_DIR/sha256sums-$VERSION-$TARGET-$SUBTARGET"

mkdir -p "$CACHE_DIR" "$DOWNLOAD_DIR" "$OUT_DIR"
curl --fail --location --retry 3 --retry-delay 5 --silent --show-error \
    "$BASE_URL/sha256sums" -o "$SUMS_FILE"

SDK_FILE=$(awk '$2 ~ /^\*?openwrt-sdk-.*Linux-x86_64[.]tar[.]zst$/ {
    sub(/^\*/, "", $2); print $2
}' "$SUMS_FILE")
[ -n "$SDK_FILE" ] || fail "no SDK archive found in $BASE_URL/sha256sums"
[ "$(printf '%s\n' "$SDK_FILE" | wc -l)" -eq 1 ] || fail "multiple SDK archives found in $SUMS_FILE"

EXPECTED_HASH=$(awk -v file="$SDK_FILE" '$2 == file || $2 == "*" file { print $1 }' "$SUMS_FILE")
[ -n "$EXPECTED_HASH" ] || fail "no SHA-256 found for $SDK_FILE"
ARCHIVE="$CACHE_DIR/$SDK_FILE"

if [ -f "$ARCHIVE" ]; then
    if ! printf '%s  %s\n' "$EXPECTED_HASH" "$ARCHIVE" | sha256sum --check - >/dev/null 2>&1; then
        echo "Cached SDK checksum mismatch; downloading again: $SDK_FILE"
        rm -f "$ARCHIVE"
    fi
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading $BASE_URL/$SDK_FILE"
    curl --fail --location --retry 3 --retry-delay 5 --show-error \
        "$BASE_URL/$SDK_FILE" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$EXPECTED_HASH" "$ARCHIVE" | sha256sum --check -

rm -rf "$SDK_ROOT"
mkdir -p "$SDK_ROOT"
tar --zstd -xf "$ARCHIVE" -C "$SDK_ROOT"
SDK_DIR=$(find "$SDK_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'openwrt-sdk-*' | head -n 1)
[ -n "$SDK_DIR" ] || fail "SDK archive did not contain an openwrt-sdk directory"

cd "$SDK_DIR"
sed \
    -e 's,https://git.openwrt.org/feed/,https://github.com/openwrt/,' \
    -e 's,https://git.openwrt.org/openwrt/,https://github.com/openwrt/,' \
    -e 's,https://git.openwrt.org/project/,https://github.com/openwrt/,' \
    feeds.conf.default > feeds.conf
printf 'src-link oasis %s\n' "$ROOT" >> feeds.conf

./scripts/feeds update -a
make defconfig

sh ./scripts/config --enable CONFIG_LUCI_LANG_ja
sh ./scripts/config --enable CONFIG_LUCI_LANG_zh_Hans
TARGETS=""
for package in $PACKAGES; do
    ./scripts/feeds install -p oasis -f "$package"
    sh ./scripts/config --enable "CONFIG_PACKAGE_$package"
    TARGETS="$TARGETS package/$package/compile"
done
make defconfig

# Build only the repository packages and their required dependencies.
make -j"$(nproc)" $TARGETS
make -j1 V=s package/index CONFIG_SIGNED_PACKAGES=n

ARTIFACT_DIR=$(find "$SDK_DIR/bin/packages" -type d -path "*/$PACKAGE_ARCH/oasis" 2>/dev/null | head -n 1 || true)
if [ -z "$ARTIFACT_DIR" ]; then
    echo "Package output directories under $SDK_DIR/bin:" >&2
    find "$SDK_DIR/bin" -maxdepth 5 -type d | sort >&2
    echo "Package files under $SDK_DIR/bin:" >&2
    find "$SDK_DIR/bin" -maxdepth 5 -type f | sort >&2
    fail "package output directory not found for $PACKAGE_ARCH/oasis"
fi
sh "$ROOT/dev_tools/verify_packages.sh" "$ARTIFACT_DIR" "$FORMAT" $PACKAGES

# Copy only this feed's packages; dependencies from other feeds are not release artifacts.
find "$ARTIFACT_DIR" -maxdepth 1 -type f -name "*.$FORMAT" -exec cp -f '{}' "$OUT_DIR/" ';'
printf 'Packages ready in %s\n' "$OUT_DIR"
