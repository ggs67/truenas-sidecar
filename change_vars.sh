#!/usr/bin/env bash

DIR=$( dirname "$0" )
ME=$( basename "$0" )

cd "$DIR" || exit 1

VARDEFS=(
  "DIR->BUILD_DIR"
  )

OPTS=""

[ "$1" = "do" ] && OPTS="--exec"

if [ $1 = "collect" ]
then
echo "collecting variables..."
script_var_changer/script_change_var.py -B \
					-i packages \
					-i prepare_environment.sh \
					-i ${ME} \
					-N make_setup_path.sh \
                                        -N setup_path.sh.template \
                                        -N make_config_checker.sh \
                                        -i ./backup.sh \
                                        -N "*.store" \
					-N "test*" \
				        --collect --lines --var '[A-Z][A-Z0-9_]+' .
  exit 0
fi


script_var_changer/script_change_var.py -B -c \
					-i packages \
					-i prepare_environment.sh \
					-i ${ME} \
					-N make_setup_path.sh \
                                        -N setup_path.sh.template \
                                        -N make_config_checker.sh \
                                        -i ./backup.sh -i .git \
                 -l changed_vars.lis -V -N "*.store" $OPTS . @vars.lis #"${VARDEFS[@]}"

echo ""
cat changed_vars.lis
echo ""
