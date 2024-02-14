#!/usr/bin/env bash

#set -x

Establish

#source "$(dirname $0)/build.common" || exit 99

#--------------------------------------------------------------
builder_default_config()
{
    cat >"$1" <<EOF

# Python version to be downloaded and built
VERSION=29.1
EOF
}

#--------------------------------------------------------------
package_prepare()
{
  PACKAGE_ARCHIVE="emacs-${VERSION}.tar.gz"
  PACKAGE_DOWNLOAD_LINK="https://ftp.gnu.org/gnu/emacs/${PACKAGE_ARCHIVE}"

  echo "Retrieving $PACKAGE_ARCHIVE..."
  download_archive "$PACKAGE_DOWNLOAD_LINK"

  prepare_package -D
}

#--------------------------------------------------------------
package_prerequisites()
{
  install_packages libssl-dev libreadline-dev
  install_build_deps python3
  install_packages pkg-config
  install_packages build-essential gdb lcov pkg-config \
     libbz2-dev libffi-dev libgdbm-dev libgdbm-compat-dev liblzma-dev \
     libncurses5-dev libreadline6-dev libsqlite3-dev libssl-dev \
     lzma lzma-dev tk-dev uuid-dev zlib1g-dev
  install_latest_dev libgnutls
}

#--------------------------------------------------------------
package_config()
{
  auto_configure  --with-x-toolkit=no --with-x=no
}

#--------------------------------------------------------------
package_build()
{
  make_package -j
}

#--------------------------------------------------------------
package_install()
{
  make_install
}

