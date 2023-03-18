#!/bin/bash

# Copyright (c) 2023 Thomas Hartwig
#
# Disclaimer: This script is provided "as is" without warranty of any kind. The author and
# copyright holder, Thomas Hartwig, is not responsible for any damages or issues that may arise
# from using this script. Use this script at your own risk.

set -e

# Set variables
PACKAGE_NAME="yafancontrol"
VERSION="1.0"
MAINTAINER_NAME="Thomas Hartwig"
MAINTAINER_EMAIL="thomas.hartwig@gmail.com"
SCRIPT_NAME="yafancontrol.sh"
CONFIG_NAME="yafancontrol.cfg"
INSTALL_DIR="/usr/bin"
CONFIG_DIR="/etc/$PACKAGE_NAME"
SYSTEMD_DIR="/etc/systemd/system"

# Create the temporary directory for the package files
temp_dir=$(mktemp -d)

# Copy the script and config file to the temporary directory
cp "$SCRIPT_NAME" "$temp_dir/$SCRIPT_NAME"
cp "$CONFIG_NAME" "$temp_dir/$CONFIG_NAME"

# Create the DEBIAN directory and control file
mkdir -p "$temp_dir/DEBIAN"
cat <<EOF >"$temp_dir/DEBIAN/control"
Package: $PACKAGE_NAME
Version: $VERSION
Architecture: all
Maintainer: $MAINTAINER_NAME <$MAINTAINER_EMAIL>
Description: Yet Another Fan Control
EOF

# Create the preinst script
cat <<EOF >"$temp_dir/DEBIAN/preinst"
#!/bin/bash
set -e

# Create the config directory if it doesn't exist
if [ ! -d "$CONFIG_DIR" ]; then
  mkdir -p "$CONFIG_DIR"
  chown root:root "$CONFIG_DIR"
  chmod 755 "$CONFIG_DIR"
fi
EOF
chmod 755 "$temp_dir/DEBIAN/preinst"

# Create the postinst script
cat <<EOF >"$temp_dir/DEBIAN/postinst"
#!/bin/bash
set -e

# Copy the config file to the config directory
cp "$CONFIG_NAME" "$CONFIG_DIR/$CONFIG_NAME"
chown root:root "$CONFIG_DIR/$CONFIG_NAME"
chmod 644 "$CONFIG_DIR/$CONFIG_NAME"

# Copy the systemd service file
cp "${PACKAGE_NAME}.service" "$SYSTEMD_DIR/${PACKAGE_NAME}.service"
systemctl enable "${PACKAGE_NAME}.service"
systemctl start "${PACKAGE_NAME}.service"
EOF
chmod 755 "$temp_dir/DEBIAN/postinst"

# Build the package and clean up
dpkg-deb --build "$temp_dir" "${PACKAGE_NAME}_${VERSION}.deb"
rm -r "$temp_dir"

echo "Package created: ${PACKAGE_NAME}_${VERSION}.deb"
