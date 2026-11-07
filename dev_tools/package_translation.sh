#!/bin/sh
set -eu

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "$#" -eq 4 ] || fail "usage: $0 <sdk-directory> <ja|zh_Hans> <ipk|apk> <output-directory>"

SDK_DIR=$1
LANGUAGE=$2
FORMAT=$3
OUT_DIR=$4
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_DIR=$(CDPATH= cd -- "$SDK_DIR" && pwd -P)
mkdir -p "$OUT_DIR"
OUT_DIR=$(CDPATH= cd -- "$OUT_DIR" && pwd -P)

case "$LANGUAGE" in
    ja)
        PKG_NAME=luci-i18n-oasis-ja
        PKG_VERSION=1.0.0-r17
        PO_FILE="$ROOT/lang/luci-i18n-oasis-ja/po/ja/luci-app-oasis.po"
        LMO_FILE=oasis.ja.lmo
        DESCRIPTION="Japanese translation for luci-app-oasis"
        ;;
    zh_Hans)
        PKG_NAME=luci-i18n-oasis-zh-cn
        PKG_VERSION=1.0.0-r1
        PO_FILE="$ROOT/lang/luci-i18n-oasis-zh-cn/po/zh_Hans/luci-app-oasis.po"
        LMO_FILE=oasis.zh-cn.lmo
        DESCRIPTION="Simplified Chinese translation for luci-app-oasis"
        ;;
    *) fail "unsupported language: $LANGUAGE" ;;
esac
[ "$FORMAT" = "ipk" ] || [ "$FORMAT" = "apk" ] || fail "unsupported package format: $FORMAT"
[ -f "$PO_FILE" ] || fail "PO file not found: $PO_FILE"

PO2LMO=$(find "$SDK_DIR/staging_dir" -type f -path '*/bin/po2lmo' | head -n 1)
[ -n "$PO2LMO" ] || fail "po2lmo not found in $SDK_DIR/staging_dir"
IPKG_BUILD="$SDK_DIR/scripts/ipkg-build"
[ -f "$IPKG_BUILD" ] || fail "ipkg-build not found: $IPKG_BUILD"

WORK_DIR="$OUT_DIR/.translation-$PKG_NAME"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/usr/lib/lua/luci/i18n"
"$PO2LMO" "$PO_FILE" "$WORK_DIR/usr/lib/lua/luci/i18n/$LMO_FILE"

if [ "$FORMAT" = "ipk" ]; then
    mkdir -p "$WORK_DIR/CONTROL"
    cat > "$WORK_DIR/CONTROL/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Architecture: all
Maintainer: liuran001
Section: utakamo
Priority: optional
Depends: luci-app-oasis
Description: $DESCRIPTION
EOF
    "$SDK_DIR/scripts/ipkg-build" "$WORK_DIR" "$OUT_DIR"
else
    APK_TOOL=$(find "$SDK_DIR/staging_dir" -type f -path '*/bin/apk' | head -n 1)
    [ -n "$APK_TOOL" ] || fail "apk not found in $SDK_DIR/staging_dir"
    "$APK_TOOL" mkpkg \
        --info "name:$PKG_NAME" \
        --info "version:$PKG_VERSION" \
        --info "description:$DESCRIPTION" \
        --info "arch:noarch" \
        --info "license:MIT" \
        --info "origin:$PKG_NAME" \
        --info "url:https://github.com/liuran001/oasis" \
        --info "maintainer:liuran001" \
        --info "depends:luci-app-oasis" \
        --files "$WORK_DIR" \
        --output "$OUT_DIR/$PKG_NAME-$PKG_VERSION.apk"
fi

rm -rf "$WORK_DIR"
printf 'Built %s %s in %s\n' "$PKG_NAME" "$PKG_VERSION" "$OUT_DIR"
