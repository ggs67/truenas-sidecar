#!/usr/bin/env bash

CONFIG_CHECKER_DIR=$( dirname "${BASH_SOURCE}" )

source ${CONFIG_CHECKER_DIR}/../gglib/include checks vars

source ${CONFIG_CHECKER_DIR}/../conf.d/config.sh

check_config()
{
  check_array check_absolute_path BINDIRS
  check_value_in DEFAULT_BUILD_PHASE "${BUILD_PHASE_LIST}"
  check_yes_no DEPLOY_CONFIG_DUAL_SYNC
  check_yes_no DEPLOY_CONFIG_KEEP
  check_yes_no DEPLOY_CONFIG_TOUCH
  check_yes_no DEPLOY_NO_SITE_CONFIG_FILES
  check_array check_absolute_path LIB_SEARCH_PATH
  check_absolute_path PREFIX

  make_readonly_var SIDECAR_GROUP
  check_readonly_var SIDECAR_GROUP

  make_readonly_var SIDECAR_USER
  check_readonly_var SIDECAR_USER
  check_absolute_path STAGING_AREA
  check_yes_no TRUENAS_BACKUP

  make_readonly_var TRUENAS_BACKUP_ARCHIVE $( basename "${TRUENAS_DST}" )
  check_readonly_var TRUENAS_BACKUP_ARCHIVE

  make_readonly_var TRUENAS_BACKUP_DIR $( dirname "${TRUENAS_DST}" )
  check_readonly_var TRUENAS_BACKUP_DIR
  check_absolute_path -o TRUENAS_BACKUP_DIR
  check_int_range TRUENAS_BACKUP_VERSIONS 0

  make_readonly_var TRUENAS_DST
  check_readonly_var TRUENAS_DST
  check_absolute_path TRUENAS_DST
  check_equal_vars_W TRUENAS_DST STAGING_AREA
  check_path_in_W TRUENAS_DST "/mnt" TRUENAS_DST
}

check_config

