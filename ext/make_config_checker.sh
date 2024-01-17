#!/usr/bin/env bash

DIR=$( dirname "$0" )

#cd "${DIR}" || exit 1

python3 "${DIR}/make_config_checker.py" --checker "${DIR}/load_config.sh" --function --call --gglib "${DIR}/../gglib" "${DIR}/../conf.d/config.sh"
