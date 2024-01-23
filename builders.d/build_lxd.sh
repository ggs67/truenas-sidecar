#!/usr/bin/env bash

#set -x

Establish
#source "$(dirname $0)/build.common" || exit 99

#--------------------------------------------------------------
#builder_default_config()
#{
#    cat >"$1" <<EOF
#
#EOF
#}

#--------------------------------------------------------------
package_prepare()
{
  ARCHIVE="lxd"
  LINK="https://github.com/canonical/lxd"

  echo "Retrieving $ARCHIVE..."
  get_github "${LINK}"
  
  prepare_package
}

#--------------------------------------------------------------
package_prerequisites()
{
  install_packages acl attr autoconf automake dnsmasq-base git libacl1-dev libcap-dev liblxc1 libsqlite3-dev libtool libudev-dev liblz4-dev libuv1-dev make pkg-config rsync squashfs-tools tar tcl xz-utils ebtables
  install_packages lxc-dev
  snap_install --classic go
  need_restart
  install_packages lvm2 thin-provisioning-tools
  install_packages busybox-static curl gettext jq sqlite3 socat bind9-dnsutils
}

#--------------------------------------------------------------
package_config()
{
  make_deps
}

#--------------------------------------------------------------
package_build()
{
  #make_package -j
  true
}

#--------------------------------------------------------------
package_install()
{
  #make_install
  true
}

#--------------------------------------------------------------
#package_config_files()
#{
#  register_config_file bacula-sd.conf
#  register_config_file bacula-fd.conf
#  register_config_file bacula-dir.conf
#}
