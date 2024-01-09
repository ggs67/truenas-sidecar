#!/usr/bin/env bash

#set -x

MINARGS=0
MAXARGS=0 # Use N for no limit

SCRIPT="$0"
ME=$(basename "$SCRIPT")
DIR=$(dirname "$SCRIPT")
DIR="${DIR:-.}"
DIR=$( readlink -e "$DIR" )

cd "$DIR" || exit 1

#-----------------------------------------------------------------------------
usage()
{
    echo "" >&2
    echo "usage: ${ME}" >&2
    echo "" >&2
    exit 99
    return 0 # Paranoia allowing for && capture
}

source ../gglib/include errmgr
Establish

while [ "${1:0:1}" = "-" ]
do
    OPT="$1"
    shift
    case $OPT in
	-h|--help) usage
		   exit 0
		   ;;
	*) echo "error: unknown option $OPT"
	   usage
	   exit 99
    esac
done

[ $# -lt $MINARGS ] && echo "error: not enough arguments (got $#, expect min $MINARGS)" && usage && exit 99
[ $MAXARGS != N -a $# -gt $MAXARGS ] && echo "error: too many arguments (got $#, expect max $MAXARGS)" && usage && exit 99

translate()
{
local VAR=$1
local N=()
local X
local O

  eval O=\( "\${${VAR}[@]}" \)
  for X in "${O[@]}"
  do
    N+=( "${LOCAL_DST}${X}" )
  done
  eval $VAR=\( "${N[@]}" \)
}


source ../conf.d/config.sh

FILE=setup_path.sh
TEMPLATE=${FILE}.template
DEST="${LOCAL_DST}/${FILE}"
translate BINDIRS
translate LIBDIRS

sed -e '/^[[:space:]]*###SETUP###[[:space:]]*$/,$d' "${TEMPLATE}" > "$DEST"

echo "setup_path_add_paths PATH ${BINDIRS[@]}" >> "$DEST"
echo "setup_path_add_paths LD_LIBRARY_PATH ${LIBDIRS[@]}" >> "$DEST"
echo ""

sed -n -e '/^[[:space:]]*###SETUP###[[:space:]]*$/,$p' "${TEMPLATE}" | tail +2 >> "$DEST"

