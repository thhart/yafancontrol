#!/bin/bash
set -euo pipefail

# Build the yafancontrol .deb. Compiles the C implementation (yafancontrol.c)
# into /usr/bin/yafancontrol, installs the config and the systemd unit.
# NOTE: bump PACKAGE_VERSION before publishing a release with changed contents.

# Define variables
PACKAGE_NAME="yafancontrol"
PACKAGE_VERSION="1.0"
PACKAGE_MAINTAINER="Thomas Hartwig <thomas.hartwig@gmail.com>"
BUILD_DIR="build"
SCRIPT_DIR=$(pwd)
PACKAGE_DIR="${PACKAGE_NAME}_${PACKAGE_VERSION}"
PACKAGE_FILENAME="${PACKAGE_NAME}_${PACKAGE_VERSION}.deb"

# Create build directory
if [ -d "$BUILD_DIR" ]; then
  rm -rf "$BUILD_DIR"
fi
mkdir "$BUILD_DIR"

# Create package directories
mkdir -p "$BUILD_DIR/$PACKAGE_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/$PACKAGE_DIR/usr/bin"
mkdir -p "$BUILD_DIR/$PACKAGE_DIR/etc/yafancontrol"
mkdir -p "$BUILD_DIR/$PACKAGE_DIR/etc/systemd/system"

# Compile the C implementation -> /usr/bin/yafancontrol
cc -O2 -Wall -Wextra -o "$BUILD_DIR/$PACKAGE_DIR/usr/bin/yafancontrol" "$SCRIPT_DIR/yafancontrol.c"

# Copy config (read from /etc/yafancontrol/yafancontrol.cfg by the binary) and unit
cp "$SCRIPT_DIR/yafancontrol.cfg" "$BUILD_DIR/$PACKAGE_DIR/etc/yafancontrol/yafancontrol.cfg"
cp "$SCRIPT_DIR/yafancontrol.service" "$BUILD_DIR/$PACKAGE_DIR/etc/systemd/system/"

# Set permissions
chmod 755 "$BUILD_DIR/$PACKAGE_DIR/usr/bin/yafancontrol"

# Mark the config as a conffile so dpkg preserves local edits across upgrades
echo "/etc/yafancontrol/yafancontrol.cfg" > "$BUILD_DIR/$PACKAGE_DIR/DEBIAN/conffiles"

# Create control file
CONTROL_FILE="$BUILD_DIR/$PACKAGE_DIR/DEBIAN/control"
{
  echo "Package: $PACKAGE_NAME"
  echo "Version: $PACKAGE_VERSION"
  echo "Maintainer: $PACKAGE_MAINTAINER"
  echo "Architecture: $(dpkg --print-architecture)"
  echo "Depends: libc6"
  echo "Description: Yet Another Fan Control - in-process ThinkPad fan controller"
} > "$CONTROL_FILE"

# Create postinst script
POSTINST_FILE="$BUILD_DIR/$PACKAGE_DIR/DEBIAN/postinst"
{
  echo "#!/bin/bash"
  echo "systemctl daemon-reload"
  echo "systemctl enable yafancontrol.service"
  echo "systemctl restart yafancontrol.service"
} > "$POSTINST_FILE"
chmod 755 "$POSTINST_FILE"

# Build package
dpkg-deb --build "$BUILD_DIR/$PACKAGE_DIR" "$BUILD_DIR/$PACKAGE_FILENAME"

# Copy package to current directory
mv "$BUILD_DIR/$PACKAGE_FILENAME" "$SCRIPT_DIR"

# Clean build directory
rm -rf "$BUILD_DIR"

echo "built $PACKAGE_FILENAME"
