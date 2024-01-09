#!/usr/bin/env bash

SCRIPT="$0"
DIR=$( dirname "$SCRIPT" )
[ -z "$DIR" ] && DIR="."
DIR=$( realpath -e "$DIR/.." )
VERBOSE=9

source "${DIR}/conf.d/config.sh"

source "${DIR}/ext/sanity.sh"
