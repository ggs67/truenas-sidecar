#!/usr/bin/env bash

# NOTE: This script file together with it's sister python file are only meant to be used for development of
#       the sidecar for the automatic generation of config (config.sh) loading validating

DIR=$( dirname "$0" )

#cd "${DIR}" || exit 1

python3 "${DIR}/make_config_checker.py" --checker "${DIR}/load_config.sh" --function --call --gglib "${DIR}/../gglib" "${DIR}/../conf.d/config.sh"
