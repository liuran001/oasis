#!/bin/sh
set -eu

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "$#" -ge 3 ] || fail "usage: $0 <directory> <ipk|apk> <package> [package...]"

DIRECTORY=$1
EXT=$2
shift 2
[ -d "$DIRECTORY" ] || fail "artifact directory not found: $DIRECTORY"
[ "$EXT" = "ipk" ] || [ "$EXT" = "apk" ] || fail "unsupported package format: $EXT"

EXPECTED_COUNT=$#
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
ZH_PACKAGE=""

for package in "$@"; do
    case "$EXT" in
        ipk) pattern="${package}_*.ipk" ;;
        apk) pattern="${package}-[0-9]*.apk" ;;
    esac

    find "$DIRECTORY" -maxdepth 1 -type f -name "$pattern" > "$TMP_DIR/matches"
    count=$(wc -l < "$TMP_DIR/matches")
    [ "$count" -gt 0 ] || fail "missing $package"
    [ "$count" -eq 1 ] || fail "duplicate $package artifacts ($count files)"

    package_file=$(cat "$TMP_DIR/matches")
    [ -s "$package_file" ] || fail "empty package: $package_file"
    if [ "$package" = "luci-i18n-oasis-zh-cn" ]; then
        ZH_PACKAGE=$package_file
    fi
done

actual_count=$(find "$DIRECTORY" -maxdepth 1 -type f -name "*.$EXT" | wc -l)
[ "$actual_count" -eq "$EXPECTED_COUNT" ] || \
    fail "expected $EXPECTED_COUNT $EXT packages, found $actual_count"

if [ "$EXT" = "ipk" ]; then
    other_format="apk"
else
    other_format="ipk"
fi
other_count=$(find "$DIRECTORY" -maxdepth 1 -type f -name "*.$other_format" | wc -l)
[ "$other_count" -eq 0 ] || fail "found $other_count unexpected $other_format files"

[ -n "$ZH_PACKAGE" ] || fail "luci-i18n-oasis-zh-cn must be included in the expected package list"

case "$EXT" in
    ipk)
        if ar p "$ZH_PACKAGE" data.tar.gz > "$TMP_DIR/data.tar.gz" 2>/dev/null; then
            :
        elif tar -xOf "$ZH_PACKAGE" ./data.tar.gz > "$TMP_DIR/data.tar.gz"; then
            :
        else
            fail "cannot extract data.tar.gz from $ZH_PACKAGE"
        fi
        if ! tar -tzf "$TMP_DIR/data.tar.gz" > "$TMP_DIR/contents"; then
            fail "cannot read data.tar.gz from $ZH_PACKAGE"
        fi
        ;;
    apk)
        if ! tar -tf "$ZH_PACKAGE" > "$TMP_DIR/contents"; then
            fail "cannot read APK package $ZH_PACKAGE"
        fi
        ;;
esac

if ! grep -Eq '(^|/)usr/lib/lua/luci/i18n/oasis\.zh-cn\.lmo$' "$TMP_DIR/contents"; then
    fail "oasis.zh-cn.lmo is missing from $ZH_PACKAGE"
fi

printf 'Verified %s %s packages in %s\n' "$EXPECTED_COUNT" "$EXT" "$DIRECTORY"
