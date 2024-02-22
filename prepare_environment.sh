#!/usr/bin/env bash

MIN_PYTHON_MAJOR=3
MIN_PYTHON_MINOR=8

#set -x

MINARGS=0
MAXARGS=0 # Use N for no limit

SCRIPT="$0"
ME=$(basename "$SCRIPT")
DIR=$(dirname "$SCRIPT")
DIR="${DIR:-.}"
DIR=$( readlink -e "$DIR" )

#-----------------------------------------------------------------------------
usage()
{
    echo "" >&2
    echo "usage: ${ME} [-O]" >&2
    echo "" >&2
    echo "  -O : install optional packages"
    exit 99
    return 0 # Paranoia allowing for && capture
}

#-----------------------------------------------------------------------------
# %1 : status code
# %2 : line number
catch()
{
    L=$2
    L1=$((L-5))
    L2=$((L+2))

    echo "" >&2
    echo "error code $1 returned on line $2" >&2
    echo "---------------------------------------------------------------------"
    sed "$L1,$L2!d;s/^/    /;${L}s/^   /->>/" "$SCRIPT" >&2
    echo "---------------------------------------------------------------------" >&2
    exit $1
}


trap 'catch $? $LINENO' ERR

OPTIONAL=N

while [ "${1:0:1}" = "-" ]
do
    OPT="$1"
    shift
    case $OPT in
	-O|--optional) OPTIONAL=Y
		       ;;
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

check_command()
{
  if ! command -v "$1" >/dev/null 2>&1
  then
    echo ""
    command_not_found_handle "$1"
    echo ""
    echo "ERROR: required commend '$1' is not available. Please install."
  fi
}

sudo apt update
sudo apt install -y build-essential gdb lcov pkg-config git wget curl rsync command-not-found chrony python3 devscripts
sudo apt install -y systemd-container mmdebstrap

[ $OPTIONAL = Y ] && sudo apt install -y emacs
sudo apt update # update database for command-not-found

systemctl is-enabled --quiet systemd-networkd || sudo systemctl enable systemd-networkd
systemctl is-active --quiet systemd-networkd || { sudo systemctl start systemd-networkd ; sleep 5 ; }
systemctl is-active --quiet systemd-networkd || { echo "ERROR: unable to start systemd-networkd" ; exit 1 ; }

command_not_found_handle()
{
    if [ -x /usr/lib/command-not-found ]; then
	/usr/lib/command-not-found -- "$1";
	return $?;
    else
	if [ -x /usr/share/command-not-found/command-not-found ]; then
	    /usr/share/command-not-found/command-not-found -- "$1";
	    return $?;
	else
	    printf "%s: command not found\n" "$1" 1>&2;
	    return 127;
	fi;
    fi
}

check_command readlink
check_command realpath
check_command rsync
check_command tar
check_command sleep
check_command sed
check_command awk
check_command tput
check_command mk-build-deps
check_command python3

PYOK=$( python3 -c "import sys; print('OK' if sys.version_info >= (${MIN_PYTHON_MAJOR},${MIN_PYTHON_MINOR}) else 'NOK')" )
[ "$PYOK" != "OK" ] && echo "ERROR: we need python V{MIN_PYTHON_MAJOR}.{MIN_PYTHON_MINOR} as a minimum" && exit 1

#[ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 600 ~/.ssh

TRY=3

while [ $TRY -gt 0 ]
do
  TRY=$((TRY-1))
  while read PUBKEY
  do
    PRVKEY="${PUBKEY%.pub}"
    if [ -f "${PUBKEY}" -a -f "${PRVKEY}" ]
    then
      echo ""
      echo "Add public key (for example ${PUBKEY}) to ~/.ssh/authorized_keys of root on the NAS"
      echo ""
      break     
    fi
    PUBKEY=""
  done < <( find ~/.ssh -maxdepth 1 -name "id_*.pub" -type f )
  [ -n "${PUBKEY}" -o $TRY -lt 2 ] && break
  ssh-keygen
done

[ -z "${PUBKEY}" ] && echo "ERROR: could not generate ssh key" && exit 1

