#!/usr/bin/env bash

#set -x

Establish

#source "$(dirname $0)/build.common" || exit 99

#--------------------------------------------------------------
builder_default_config()
{
    cat >"$1" <<EOF

# Python version to be downloaded and built
VERSION=3.12.1
EOF
}

#--------------------------------------------------------------
package_prepare()
{
  declare -g PACKAGE_ARCHIVE="Python-${VERSION}.tgz"
  PACKAGE_DOWNLOAD_LINK="https://www.python.org/ftp/python/${VERSION}/${PACKAGE_ARCHIVE}"

  echo "Retrieving $PACKAGE_ARCHIVE..."
  download_archive "$PACKAGE_DOWNLOAD_LINK"

  prepare_package -D
}

#--------------------------------------------------------------
package_prerequisites()
{
  echo "installing dependencies..."
  install_packages libssl-dev libreadline-dev
  install_build_deps  python3
  install_packages pkg-config
  install_packages build-essential gdb lcov pkg-config \
     libbz2-dev libffi-dev libgdbm-dev libgdbm-compat-dev liblzma-dev \
     libncurses5-dev libreadline6-dev libsqlite3-dev libssl-dev \
     lzma lzma-dev tk-dev uuid-dev zlib1g-dev

}

#--------------------------------------------------------------
package_config()
{
  auto_configure --with-pydebug
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

#--------------------------------------------------------------
package_define_commands()
{
  define_command PYTHON3 python3 @python3
  define_command PIP3 pip3 @pip3
}
