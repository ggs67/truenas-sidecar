#!/usr/bin/env bash

#set -x

SCRIPT="$0"
ME=$(basename "$SCRIPT")
DIR=$(dirname "$SCRIPT")
DIR="${DIR:-.}"
DIR=$( readlink -e "$DIR" )

source ${DIR}/gglib/include errmgr
Establish

cd "$DIR" || exit 99
source ${DIR}/ext/load_config.sh || exit 99

SRC="${LOCAL_DST}"
URI="root@$NAS"

VAULT="${DIR}/config_vault.d"

SEP=":"

gglib_include present checks files

#-----------------------------------------------------------------------------
require()
{
  [ -n "$1" ] && return 0
  echo "ERROR: $2 required in $3" >&2
  exit 99
}


#-----------------------------------------------------------------------------
# %1 : variable
# %2 : alias (can be empty) 
# %3 : command or command path, relative or absolute
# %4... : command options
define_command()
{
  local VAR="$1"
  local ALIAS="$2"
  local CMD="$3"
  local CMDPATH=""
  shift 3
  
  require "${VAR}" "variable name" "define_command"
  require "${CMD}" "command name or path" "define_command"

  if [ "${CMD:0:1}" = "@" ]
  then
    CMD="${CMD:1}"
    CMDPATH=$( find -L "${SRC}" -type f -executable -name "${CMD}" 2>/dev/null ) || true
    local FOUND=$( echo "$CMDPATH" | wc -l )
    [ -z "$CMDPATH" ] && return 0
    [ $FOUND -gt 1 ] && echo "ERROR: more than one match found for command ${CMD}" %% exit 1
  else
    CMDPATH=$( cd "${LOCAL_DST}" ; realpath -m "${CMD}" )
  fi
  [ ! -f "${CMDPATH}" ] && return 0
  if [ -z "$1" ]
  then  
    echo export ${VAR}=\"${CMDPATH}\"
    [ -n "$ALIAS" ] && echo "[ \$ALIASES = Y ] && alias ${ALIAS}=\"${CMDPATH}\" || true" 
  else
    echo export ${VAR}=\"${CMDPATH} $*\"
    [ -n "$ALIAS" ] && echo "[ \$ALIASES = Y ] && alias ${ALIAS}=\"${CMDPATH} $*\" || true"
  fi
}

#-----------------------------------------------------------------------------
collect_all_libs()
{
  while read FILE
  do
   [[ "$FILE" =~ ^([^:]+)[:] ]] || continue
   FILE="${BASH_REMATCH[1]}"     
   objdump -p "${FILE}" | grep NEEDED | grep -E -o '[^[:space:]]+$'
  done < <( find "$SRC" -type f -executable -exec file {} + | grep -E '^[^:]*[:][[:space:]]*ELF[[:space:]]' )
}

#-----------------------------------------------------------------------------
collect_libs()
{
  collect_all_libs | sort -u
}

#-----------------------------------------------------------------------------
# This function transforms a local library path to its library root if possible
# i.e path /usr/lib/subdir/subdir2/lib.so is changed to /usr/lib/lib.so
#
# %1 : var
# %2 : lib path
root_lib()
{
local ROOT
local L

  for ROOT in "${LIBDIRS[@]}"
  do
    ROOT="${ROOT%/}/" # Make sure it ends with / to avoid partial matches
    L="${2:0:${#ROOT}}"
    if [ "$L" = "$ROOT" ]
    then
      L=$( basename "$2" )
      eval $1="${ROOT}${L}"
      return 0
    fi    
  done
  eval $1="$2" # If no root identified, use full path
  return 1
}

#-----------------------------------------------------------------------------
# %1 : local lib path
# %2 : [lib link] (internal use only)
install_lib()
{
local LIB="$1"
local LIBINSTDIR="$2" # is ${SRC}/${ROOT} (actually without / as $ROOT has a leading one)

  local LIBNAME=$( basename "${LIB}" )
  local LIBINST="${LIBINSTDIR}/${LIBNAME}"

  # Is link, then process actually library first
  if [ -L "$LIB" ]
  then
    local LIBFILE=$( readlink -e "${LIB}" )
    if [ $? -ne 0 ]
    then
      echo "ERROR: orphaned library link ${LIB}"
      exit 6
    fi

    root_lib LIBFILEINST "${LIBFILE}" || echo "WARNING: ${LIBFILE} not located in LIBDIRS, using full path"
    LIBFILEINST="${SRC}${LIBFILEINST}" # Build full installation path
    local LIBFILEINSTDIR=$( dirname "${LIBFILEINST}" )

    install_lib "${LIBFILE}" "${LIBFILEINSTDIR}"
    # Here we can assume that the regular lib already has been installed
    [ ! -d "$LIBINSTDIR" ] && mkdir -p "$LIBINSTDIR"

    [ -e "${LIBINST}" -a ! -L "${LIBINST}" ] && rm "${LIBINST}" # Delete potenmtial file (not expected link)
    if [ -L "${LIBINST}" ]
    then
      # Link already exists so lets see if it points to the corre ct file
      local POINTER=$( readlink -m "${LIBINST}" )
      [ "${POINTER}" =	"${LIBFILEINST}" ] && return # Link OK
      rm "${LIBINST}" # Non-matching link, recreate
    fi
    RELPATH=$( realpath "--relative-to=${LIBINSTDIR}" "${LIBFILEINST}" )
    ln -s -v "${RELPATH}" "${LIBINST}"
  else
    [ ! -d "$LIBINSTDIR" ] && mkdir -p "$LIBINSTDIR"
    cp -v -u -p "$LPATH" "$LIBINST"
  fi
}

#-----------------------------------------------------------------------------
usage()
{
    echo "" >&2
    echo "usage: ${ME} [-s|--save-config]" >&2
    echo "" >&2
    echo "  -s : only save config and exit" >&2
    echo "" >&2
    exit 99
    return 0 # Paranoia allowing for && capture
}

SAVE_CONFIG_MODE=N

while [ "${1:0:1}" = "-" ]
do
    OPT="$1"
    shift
    case $OPT in
      -h|--help) usage
	         exit 0
		 ;;
      -s|--save-config)
           SAVE_CONFIG_MODE=Y
           ;;
      *) echo "error: unknown option $OPT"
         usage
         exit 99
    esac
done

if [ ${SAVE_CONFIG_MODE} = N ]
then
  echo "Collecting libraries..."
  LIBS=( $( collect_libs ) )
  LIBSP=()  # local lib paths

  echo "Getting TRUENAS available libraries..."
  #ssh $URI for DIR in $LIBDIR ; do find \$DIR -type f 

  # Find local library paths
  for LIB in "${LIBS[@]}"
  do
    FOUND=N
    for LD in "${LIBDIRS[@]}"
    do
      [ ! -d "$LD" ] && continue
      P="$( find -L "$LD" -name "${LIB}" -type f | head -1 )"
      if [ -n "$P" ]
      then
        # Check for remote path
        RP="$( ssh $URI for LD in "${LIBDIRS[@]}" \; do [ -d "\$LD" ] \&\& find -L "\$LD" -name "${LIB}" -type f \; done | head -1 )"
        LIBSP+=( "${LD}${SEP}${LIB}${SEP}${P}${SEP}${RP}" ) && FOUND=Y && break
      fi
    
    done
    if [ $FOUND != Y ]
    then
      # Try to find in destination (packlage lib)
      P="$( find -L "$SRC" -name "${LIB}" -type f | head -1 )"
      [ -n "$P" ] && LIBSP+=( "*${SEP}${LIB}${SEP}${P}:" ) && FOUND=Y && break
      [ $FOUND != Y ] && echo "ERROR: library $LIB not found on local system (but expected)" && exit 4
    fi
  done

  for P in "${LIBSP[@]}"
  do
    ROOT=$(echo "$P"|cut -f 1 -d ':')
    LIB=$(echo "$P"|cut -f 2 -d ':')
    LPATH=$(echo "$P"|cut -f 3 -d ':')
    RPATH=$(echo "$P"|cut -f 4 -d ':')
    echo -n "$P"
    [ "${LPATH:0:1}" != "/" ] && echo -e "\nBUG: expect local library path to be absolute" && exit 5
    [ "${ROOT}" = "*" ] && echo "(included in package)" && continue
    [ -n "$RPATH" ] && echo "(available)" && continue # Already exist in TrueNAS
    echo "(copying to installation)"

    install_lib "${LPATH}" "${SRC}${ROOT}"
  done

  echo "updating setup_path.sh..."
  ${DIR}/ext/make_setup_path.sh

  echo "requesting separate package commands"
  while read BUILDER
  do
    unset -f package_define_commands    
    source "$BUILDER"
    OPTS=""
    [ ! -x "$BUILDER" ] && OPTS="-D" # Pass -D optioon if builder was disabled
    BUILDER=$( basename "$BUILDER" )
    PACKAGE=${BUILDER#build_}
    PACKAGE=${PACKAGE%.sh}
    if [ "$( type -t package_define_commands )" = "function" ]
    then
      echo "  - defining additional commands for $BUILDER"
      package_define_commands $OPTS | sed -e '1i\\n# Commands for package $PACKAGE' >> "${LOCAL_DST}/setup_path.sh"
    else
      echo "  - no additional commands for $BUILDER"
    fi
  done < <(find "$DIR/builders.d" -maxdepth 1 -name "build_*.sh" | sort)

  [ -z "${TRUENAS_DST}" ] && echo "DANGEROUS ERROR - TRUENAS_DST is empty. Aborting..." && exit 1
  [ -z "${SRC}" ] && echo "DANGEROUS ERROR - SRC is empty. Aborting..." && exit 1

  if [ "${TRUENAS_BACKUP}" = "Y" ]
  then
    alias -p
    title1 "NAS deployment backup"

    [ -z "${TRUENAS_BACKUP_DIR}" ] && TRUENAS_BACKUP_DIR=$( dirname "${TRUENAS_DST}" )
  
    check_var TRUENAS_BACKUP_DIR
    check_absolute_path TRUENAS_BACKUP_DIR
    check_var TRUENAS_BACKUP_VERSIONS
    ssh ${URI} $( remote_file_version ${TRUENAS_BACKUP_VERSIONS} "${TRUENAS_BACKUP_DIR}/${TRUENAS_BACKUP_ARCHIVE}.tar.bz2" )
    ssh ${URI} tar cfj "${TRUENAS_BACKUP_DIR}/${TRUENAS_BACKUP_ARCHIVE}.tar.bz2" "${TRUENAS_DST}/"
  fi
fi


# DEPLOY_CONFIG_KEEP=Y
# DEPLOY_CONFIG_TOUCH=N
# DEPLOY_CONFIG_DUAL_SYNC=Y
# DEPLOY_CONFIG_CLEANUP=Y

# rsync:
# -a -> -rlptgoD
#   -r : recursive
#   -l : copy links as links
#   -p : preserve permissions
#   -t : preserve modification times
# -v : verbose
# -z : compress
# -h : human readable
#
# -u : update (skip newer files on receiver)
if [ ${DEPLOY_CONFIG_KEEP} = Y ]
then  
  echo "syncing back to $( basename "${VAULT}" ) ..."
  rsync -azhv --existing -u -e ssh --info=copy --dry-run -i "${URI}:${TRUENAS_DST}/" "$SRC" | grep '^[>f]'| sed -E 's/^[>]f.+[[:space:]]//' | rsync -azhv -e ssh --files-from - "${URI}:${TRUENAS_DST}/" "${VAULT}"

  if [ ${DEPLOY_CONFIG_CLEANUP} = Y ]
  then
    echo "cleaning-up deleted configuration files..."
    rsync --recursive --delete --ignore-existing --existing --prune-empty-dirs --verbose "${URI}:${TRUENAS_DST}/" "${VAULT}"
  fi
    
  if [ ${DEPLOY_CONFIG_DUAL_SYNC} = Y ]
  then
    echo "syncing known config files..."
    rsync --recursive --existing --verbose "${URI}:${TRUENAS_DST}/" "${VAULT}"
  fi
    
else
  [ ${SAVE_CONFIG_MODE} != N ] && echo "WARNING: save-config mode requested, but config saving disabled in config.sh" >&2
fi

[ ${SAVE_CONFIG_MODE} != N ] && exit 0

#echo "syncing NAS..."
#rsync -avzh -e ssh --chown ${DST_USER}:${DST_GROUP} --delete "${SRC}/" "${URI}:${TRUENAS_DST}"


