#!/usr/bin/env bash

Establish

PACKAGE_ARCHIVE="ImageMagick.tar.gz"
PACKAGE_DOWNLOAD_LINK="https://imagemagick.org/archive/${PACKAGE_ARCHIVE}"

#--------------------------------------------------------------
package_prepare()
{
  echo "Retrieving $PACKAGE_ARCHIVE..."
  download_archive -N "$PACKAGE_DOWNLOAD_LINK"

  prepare_package -D
}

#--------------------------------------------------------------
package_prerequisites()
{
  install_packages pkg-config
  install_packages libltdl-dev libjpeg-dev
}

#--------------------------------------------------------------
package_config()
{
  auto_configure --with-modules
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
