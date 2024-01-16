#!/usr/bin/env bash

set -x

DIR=$( dirname "$0" )
source ${DIR}/../gglib/include checks

source ${DIR}/../conf.d/config.sh

check_array check_absolute_path BINDIRS
check_value_in DEFAULT_BUILD_PHASE "prepare,config,build,install"
check_yes_no DEPLOY_CONFIG_KEEP
check_yes_no DEPLOY_CONFIG_REVERSE_SYNC
check_yes_no DEPLOY_CONFIG_TOUCH
check_array check_absolute_path LIBDIRS
check_absolute_path LOCAL_DST
check_absolute_path PREFIX
check_absolute_path -o TRUENAS_BACKUP_DIR
check_int_range TRUENAS_BACKUP_VERSIONS 0
check_yes_no TRUENAS_BACKUP
check_absolute_path TRUENAS_DST
