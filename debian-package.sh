#!/bin/bash

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
mkdir -p "$BUILD_DIR/$PACKAGE_DIR/etc/systemd/system"

# Copy files
cp "$SCRIPT_DIR/yafancontrol.sh" "$BUILD_DIR/$PACKAGE_DIR/usr/bin/yafancontrol"
cp "$SCRIPT_DIR/yafancontrol.cfg" "$BUILD_DIR/$PACKAGE_DIR/etc/yafancontrol.cfg"
cp "$SCRIPT_DIR/yafancontrol.service" "$BUILD_DIR/$PACKAGE_DIR/etc/systemd/system/"

# Set permissions
chmod 755 "$BUILD_DIR/$PACKAGE_DIR/usr/bin/yafancontrol"

# Create control file
CONTROL_FILE="$BUILD_DIR/$PACKAGE_DIR/DEBIAN/control"
echo "Package: $PACKAGE_NAME" >> "$CONTROL_FILE"
echo "Version: $PACKAGE_VERSION" >> "$CONTROL_FILE"
echo "Maintainer: $PACKAGE_MAINTAINER" >> "$CONTROL_FILE"
echo "Architecture: $(dpkg --print-architecture)" >> "$CONTROL_FILE"
echo "Description: Yet Another Fan Control" >> "$CONTROL_FILE"

# Create postinst script
POSTINST_FILE="$BUILD_DIR/$PACKAGE_DIR/DEBIAN/postinst"
echo "#!/bin/bash" >> "$POSTINST_FILE"
echo "systemctl daemon-reload" >> "$POSTINST_FILE"
echo "systemctl enable yafancontrol.service" >> "$POSTINST_FILE"
echo "systemctl restart yafancontrol.service" >> "$POSTINST_FILE"
chmod 755 "$POSTINST_FILE"

# Build package
dpkg-deb --build "$BUILD_DIR/$PACKAGE_DIR" "$BUILD_DIR/$PACKAGE_FILENAME"

# Copy package to current directory
mv "$BUILD_DIR/$PACKAGE_FILENAME" "$SCRIPT_DIR"

# Clean build directory
rm -rf "$BUILD_DIR"
