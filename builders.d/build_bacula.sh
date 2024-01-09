#!/usr/bin/env bash

#set -x

Establish

#source "$(dirname $0)/build.common" || exit 99

#--------------------------------------------------------------
builder_default_config()
{
    cat >"$1" <<EOF

# Python version to be downloaded and built
VERSION=13.0.3

# Hard coded email address for (dump & job) notifications,
# can be overriddedn in runtime config
BACULA_EMAIL=root@localhost

# Hardcoded SMTP server for sending mails
# can be overriddedn in runtime config
BACULA_SMTP=localhost

# Build selection, can be any of fd,sd,dir,all
BACULA_BUILD=all

# Database selection for bacula server, also required for sd)
# See possible --with-{database-server} option in ./configure --help or bacula documentation
BACULA_DBSERVER=postgresql
EOF
}

#--------------------------------------------------------------
package_prepare()
{
  ARCHIVE="bacula-${VERSION}.tar.gz"
  LINK="https://sourceforge.net/projects/bacula/files/bacula/${VERSION}/${ARCHIVE}/download"

  echo "Retrieving $ARCHIVE..."
  download_archive "$LINK" "$ARCHIVE"
  
  prepare_package -D
}

#--------------------------------------------------------------
package_prerequisites()
{
  install_packages libssl-dev libreadline-dev
  install_packages pkg-config
  if [ "${BACULA_BUILD}" != "fd" ]
  then
    local DBPACKAGE=""
    case "${BACULA_DBSERVER}" in
      postgresql) DBPACKAGE="libpq-dev" ;;
      mysql) DBPACKAGE="libmysqlclient-dev" ;;
      sqlite3) DBPACKAGE="libsqlite3-dev" ;;
      *) echo "unknown bacula DB-Server type '${BACULA_DBSERVER}'"
         echo "please review ${BUILDER_CONFIG}"
         exit 1
    esac
    install_packages ${DBPACKAGE}
  fi
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
