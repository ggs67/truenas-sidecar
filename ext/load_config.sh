#!/usr/bin/env bash

CHECKER_DIR=$( dirname "${BASH_SOURCE}" )

source ${CHECKER_DIR}/../gglib/include checks

source ${CHECKER_DIR}/../conf.d/config.sh

check_config()
{
  check_array check_absolute_path BINDIRS
  check_value_in DEFAULT_BUILD_PHASE "prepare,config,build,install"
  check_yes_no DEPLOY_CONFIG_KEEP
  check_yes_no DEPLOY_CONFIG_REVERSE_SYNC
  check_yes_no DEPLOY_CONFIG_TOUCH
  check_array check_absolute_path LIBDIRS
  check_absolute_path LOCAL_DST
  check_absolute_path PREFIX
  check_yes_no TRUENAS_BACKUP
  check_absolute_path -o TRUENAS_BACKUP_DIR
  check_int_range TRUENAS_BACKUP_VERSIONS 0

  check_absolute_path TRUENAS_DST
  check_equal_vars_W TRUENAS_DST LOCAL_DST
  check_path_in_W TRUENAS_DST "/mnt" TRUENAS_DST
}

check_config

