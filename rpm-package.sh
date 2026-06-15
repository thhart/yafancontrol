#!/bin/bash
set -euo pipefail

# Build the yafancontrol .rpm from yafancontrol.spec. Run on an RPM host
# (openSUSE/Fedora) with rpmbuild + gcc installed. Mirrors debian-package.sh.
# NOTE: bump Version in yafancontrol.spec before publishing changed contents.

NAME="yafancontrol"
VERSION="1.3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(rpm --eval %{_topdir} 2>/dev/null || echo "$HOME/rpmbuild")"

mkdir -p "$TOP"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}

# Assemble the source tarball expected by the spec (%{name}-%{version}/...)
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/$NAME-$VERSION"
cp "$SCRIPT_DIR"/yafancontrol.c \
   "$SCRIPT_DIR"/yafancontrol.cfg \
   "$SCRIPT_DIR"/yafancontrol.service \
   "$SCRIPT_DIR"/LICENSE \
   "$SCRIPT_DIR"/README.md \
   "$STAGE/$NAME-$VERSION/"
tar -C "$STAGE" -czf "$TOP/SOURCES/$NAME-$VERSION.tar.gz" "$NAME-$VERSION"
rm -rf "$STAGE"

cp "$SCRIPT_DIR/yafancontrol.spec" "$TOP/SPECS/"
rpmbuild -bb "$TOP/SPECS/yafancontrol.spec"

echo "built RPM(s) under $TOP/RPMS/"
