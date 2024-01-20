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
  # missing: liblxc-dev
  snap_install --classic go  
  install_packages lvm2 thin-provisioning-tools
  install_packages busybox-static curl gettext jq sqlite3 socat bind9-dnsutils
  exit
}

#--------------------------------------------------------------
package_config()
{
  local BACULA_PREFIX="${PREFIX}/opt/bacula"

  local CONFIG_OPTS="--enable-bat --with-${BACULA_DBSERVER}" # Only on server
  [ "${BACULA_BUILD}" = "fd" ] && CONFIG_OPTS="--enable-client-only --disable-build-dird --disable-build-stored" && echo "building client only..." && sleep 3
  [ "${BACULA_BUILD}" = "sd" ] && CONFIG_OPTS="--disable-build-dird --enable-build-stored --with-${BACULA_DBSERVER}" && echo "building storage daemon only..." && sleep 3
  
  CFLAGS="-g -Wall"
  auto_configure \
	--sbindir=${PREFIX}/bin \
	--sysconfdir=${PREFIX}/etc \
	--docdir=${PREFIX}/html \
	--htmldir=${BACULA_PREFIX}/html \
	--with-working-dir=${BACULA_PREFIX}/working \
	--with-pid-dir=${PREFIX}/var/run \
	--with-subsys-dir=${PREFIX}/var/run \
	--with-scriptdir=${BACULA_PREFIX}/scripts \
	--with-plugindir=${BACULA_PREFIX}/plugins \
	--with-logdir=${BACULA_PREFIX}/logs \
	--mandir=${BACULA_PREFIX}/usr/man \
	--libdir=${PREFIX}/lib \
	--enable-smartalloc \
	--enable-conio \
	--with-dump-email=${BACULA_EMAIL} \
	--with-job-email=${BACULA_EMAIL} \
	--with-smtp-host=${BACULA_SMTP} \
	--with-baseport=9101 \
	--without-systemd \
        --enable-readline --disable-afs --enable-batch-insert ${CONFIG_OPTS}
  unset CFLAGS
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
package_config_files()
{
  register_config_file bacula-sd.conf
  register_config_file bacula-fd.conf
  register_config_file bacula-dir.conf
}
