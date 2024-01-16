#!/usr/bin/env bash

[ "${BASH_VERSION:0:2}" != "5." ] && echo "build environment requires bash V5 as a minimum" && exit 99

#set -x

declare -r RUN_DIR="$PWD"
CMD_ARGS=( "$@" )
declare -r SCRIPT="$0" # Get calling script
declare -r ME=$(basename "$SCRIPT")
DIR=$(dirname "$SCRIPT")
DIR="${DIR:-.}"
declare -r DIR=$( readlink -e "$DIR" )
[ -z "$DIR" ] && echo "error: unexpected empty DIR variable." && exit 99
cd "$DIR" || exit 1

declare -r CONFDIR="${DIR}/conf.d"
declare -r BUILDERDIR="${DIR}/builders.d"
declare -r LOGROOT="${DIR}/logs"
declare -r PACKAGEROOT="${DIR}/packages"
declare -r DISTRIBUTEDIR="${DIR}/distribute.d"

declare -r SHELL_ENABLED_OPTS="checkwinsize cmdhist complete_fullquote extquote force_fignore globasciiranges globskipdots hostcomplete interactive_comments patsub_replacement progcomp promptvars sourcepath"
declare -r SHELL_DISABLED_OPTS="autocd assoc_expand_once cdable_vars cdspell checkhash checkjobs compat31 compat32 compat40 compat41 compat42 compat43 compat44 direxpand dirspell dotglob execfail expand_aliases extdebug extglob failglob globstar gnu_errfmt histappend histreedit histverify huponexit inherit_errexit lastpipe lithist localvar_inherit localvar_unset login_shell mailwarn no_empty_cmd_completion nocaseglob nocasematch noexpand_translation nullglob progcomp_alias restricted_shell shift_verbose varredir_close xpg_echo"
SHELL_OPTS_STACK=()

VERBOSE=0

declare -r BUILD_PHASE_LIST="prepare,config,build,install"

# If we are a sub process of this script, we assume BUILD_ALL request (i.,e. ignore any --all option)
ps --pid $PPID -h -o cmd | fgrep -q "${ME}" 2>/dev/null && declare -r BUILD_ALL=Y || declare -r BUILD_ALL=N

#-----------------------------------------------------------------------------
# usage: print out usage information
#
# %1 : optional error message
SYNOPSIS=""
usage()
{
  if [ -n "$1" ]
  then
    echo ""
    echo "ERROR: $1"
  fi
  echo "" >&2
  echo "usage: ${ME} [<options>] <package> ${SYNOPSIS}" >&2
  echo "usage: ${ME} [<options>] -a" >&2
  echo "usage: ${ME} -e|--enable|-d|--disable <package>..." >&2
  echo "usage: ${ME} --list" >&2
  echo "usage: ${ME} -h" >&2
  echo "" >&2
  echo "options:" >&2
  echo "  -h|--help : help - display this help" >&2
  echo "  -a||--all : build all enabled packages (see --list)"
  echo "  --L|--log : log execution into logfile file ${ME}.log" >&2
  echo "              Implies -x" >&2
  echo "              This option MUST be FIRST if used" >&2
  echo "  --list    : list all builders with their status" >&2
  echo "  -P|--purge: purge local installation directory" >&2
  echo "  -v        : increases verbosity level (multiple occurences" >&2
  echo "              cumulate" >&2
  echo "  -x|--trace: switch on bash command print out for debugging" >&2
  echo "  -b|--build <phases>: select explicit build phase(s)" >&2
  echo "     <phases>: <end>         : equal to prepare-<end>" >&2
  echo "             : <start>-      : equal to <start>-install" >&2
  echo "             : <start>-<end> : executes phases <start> to <end>" >&2
  echo "  --prepare  : prepare package" >&2
  echo "  --config   : configure package" >&2
  echo "  --build    : build package" >&2
  echo "  --install  : install package into deployment area" >&2
  echo "" >&2
  [ "$( type -t usage_info )" = "function" ] && echo "builder options:" >&2 && usage_info "${ME}"
  echo ""
  exit 99
  return 0 # Paranoia allowing for && capture
}

#-----------------------------------------------------------------------------
isFunction()
{
  [ "$( type -t $1 )" = "function" ]
}

# First we get ony the error catcher
source ${DIR}/gglib/include errmgr
Establish

# ...and then all other libraries
source ${GGLIB_DIR}/include all

#-----------------------------------------------------------------------------

source ${DIR}/conf.d/config.sh

# Sanity checks
check_var TRUENAS_DST
check_var LOCAL_DST
check_equal_vars_W TRUENAS_DST LOCAL_DST
check_path_in_W TRUENAS_DST "/mnt"
DEFAULT_BUILD_PHASE=${DEFAULT_BUILD_PHASE:-build}
check_value_in DEFAULT_BUILD_PHASE "${BUILD_PHASE_LIST}"

need_directory "${PACKAGEROOT}"

# Default build phases
BUILD_PHASES=( prepare ${DEFAULT_BUILD_PHASE} )

#-----------------------------------------------------------------------------
list_builders()
{
local BUILDER PKG STATUS
local RED=$(tput setaf 1)
local GREEN=$(tput setaf 2)
local NORMAL=$(tput sgr0)

  echo ""
  echo "List of all builders"
  echo "--------------------"
  echo ""
  
  while read BUILDER
  do
    BUILDER=$( basename "$BUILDER" )
    PKG="${BUILDER#build_}"
    PKG="${PKG%.sh}"
    [ -x "${BUILDERDIR}/${BUILDER}" ] && STATUS="${GREEN}enabled${NORMAL}" || STATUS="${RED}disabled${NORMAL}"
    printf "%-16s (%s)\n" "${PKG}" $STATUS
  done < <( ls "${BUILDERDIR}/build_"*.sh | sort)
  echo ""
}

#-----------------------------------------------------------------------------
parse_opt_build()
{
  [ -z "$1" ] && usage "--b|--build option requires an argument" && exit 99
  if [[ "$1" =~ ([^-]*)[-]([^-]*) ]]
  then
    # we have a '-' syntax
    local _start="${BASH_REMATCH[1]}"
    local _end="${BASH_REMATCH[2]}"
    # Not documented but we allow the -<end> syntax, which is equal to <end>
    # without '-' (dosumented)
  else
    # we have no '-'
    local _start=prepare
    local _end="$1"
  fi
  [ -z "$_start" ] && _start=prepare
  [ -z "$_end" ] && _end=install
  check_value_in _start "${BUILD_PHASE_LIST}" "'${_start}' is invalid value for -b|--build"
  check_value_in _end   "${BUILD_PHASE_LIST}" "'${_end}' is invalid value for -b|--build"
  BUILD_PHASES=( $_start $_end )
  check_array_size BUILD_PHASES 2 2 "BUG: BUILD_PHASES should have 2 values"
}

#-----------------------------------------------------------------------------
parse_build_cmd()
{
local OPT
local idx=0

  set -- "${CMD_ARGS[@]}"
  while [ "${1:0:1}" = "-" ]
  do
    OPT="$1"
    idx=$((idx+1))  
    shift
    case $OPT in
	-h|--help) usage
		   exit 0
		   ;;
	-a|--all)  [ ${BUILD_ALL} = Y ] && continue # Already in build-all mode
	           _build_all
		   # Just fall through if ever _build_all returns (this indicates that we aer already in build_all mode)
		   ;;
	-P|--purge) [ ${BUILD_ALL} = Y ] && continue # was handled by parent
	            purge_directory "${LOCAL_DST}"
		    ;;
        -e|--enable|-d|--disable)
	           [ $idx -ne 1 ] && usage "enable/disable options cannot be mixed with other options" && exit 99
                   CMD_ARGS=( "$OPT" "$@" )
                   _manage_packages
		   exit 0
                   ;;
	-L|--log)
	           [ $idx -ne 1 ] && usage "option -L must be first option" && exit 99
                   echo "logging execution..." >&2
                   set -x
                   /usr/bin/env bash -x ./${ME} "$@" 2>&1 | tee ./${ME}.log
                   exit $?
		   ;;
	-b|--build) parse_opt_build "$1"
		    shift
		    ;;
	-v) VERBOSE=$((VERBOSE+1))
	    ;;
        -x|--trace)
                   set -x
                   ;;
	--list)
	    list_builders
	    exit 0
	    ;;
	*) echo "error: unknown option ${OPT} for build.sh"
	   exit 99
    esac
  done
  CMD_ARGS=( "$@" )
}

#------------------------------------------------------------
_manage_packages()
{
  set -- "${CMD_ARGS[@]}"
  ENABLE=X    
  while [ -n "$1" ]
  do
    ARG="$1"
    shift      
    if [ ${ARG:0:1} = "-" ]
    then
      case $ARG in
        -d|--disable) ENABLE=N;;
        -e|--enable)  ENABLE=Y;;
        *) usage "invalid option '$ARG' - disable/enable cannot be mixed with other options"
	   exit 99
      esac
    else
      BUILDER="${BUILDERDIR}/build_${ARG}.sh"
      if [ -f "${BUILDER}" ]
      then
        [ $ENABLE = X ] && echo "BUG: unexpected unknown enabler setting" && exit 1
	[ $ENABLE = Y ] && chmod 755 "${BUILDER}" || chmod 644 "${BUILDER}"
      else
        echo "ERROR: unknown builder $( basename $BUILDER )"
        exit 1
      fi
    fi
  done
}

#------------------------------------------------------------
_build_all()
{
local BUILDER
    
  [ ${BUILD_ALL} = "Y" ] && return # allready in build all mode
  while read BUILDER
  do
    BUILDER=$( basename "$BUILDER" )
    local PACKAGE=""
    [[ "${BUILDER}" =~ ^build_(.+).sh$ ]] && PACKAGE="${BASH_REMATCH[1]}"
    echo ""
    echo "=========================================================================="
    if [ -x "${BUILDERDIR}/${BUILDER}" ]
    then
      echo "building package ${PACKAGE}..."
      ${SCRIPT} "${CMD_ARGS[@]}" "${PACKAGE}"
    else
      echo "INFO: ${PACKAGE} is disabled." >&2
    fi
  done < <( find ${BUILDERDIR} -maxdepth 1 -name "build_*.sh" | sort )
    
  exit 0
}

#------------------------------------------------------------
# %1 : Link
# %2 : oprional archive name
#
# Output:
#  LINK=%1 & ARCHIVE=%2 or extracted arhgive name
download_archive() 
{
  pushd .
  cd "${PACKAGEROOT}"
  parse_func_options "download_archive" "N=new" "$@"
  set -- "${OPT_ARGS[@]}"
  
declare -g LINK="$1"
declare -g ARCHIVE="$2"

  local LA="${LINK##*/}"
  LA="${LA%%\?*}"

  # Need extract arcive name
  if [ -z "$ARCHIVE" -o "${ARCHIVE}" = "${LA}" ]
  then
    ARCHIVE="${LA}"
    OPTS="-N"
  else
    OPTS="-O ${ARCHIVE}" # cannot use -N
    [ -f "${ARCHIVE}" ] && popd && return 0 # ...so we simply do not download existing
  fi

  [ -z "$ARCHIVE" ] && echo "no archive name in download_archive()" && exit 1
  
  # Use uf/then to aboid error trap if archive exists
  #if [ ! -f ${ARCHIVE} -o "${PARSED_OPTS[new]}" = "Y" ]
  #then
  echo "Retrieving $ARCHIVE..."
  wget -c $OPTS $LINK
  #else
  #  echo "Keeping existing $ARCHIVE"
  #fi
  popd
}

#------------------------------------------------------------
# Get package directory from archive
#
# %1 = Archive
#
# Output PACKAGE_DIR
get_package_dir()
{
local ARC="$1"
 
  [ -z "$ARC" ] && ARC="${ARCHIVE}"
  ARC="${PACKAGEROOT}/${ARC}"
  local SRC=$( tar tvf "${ARC}" | head -1 )
  if [[ "$SRC" =~ [[:space:]]([^/[:space:]]+)[/][[:space:]]*$ ]] 
  then
    declare -g PACKAGE_DIR="${PACKAGEROOT}/${BASH_REMATCH[1]}"
  else
    echo "ERROR: archive directory not found" >&2
    exit 1
  fi
}

#------------------------------------------------------------
# %1 : package directory (defaults to PACKAGE_DIR)
#
# options:
#   -D : distclean using makefile if present
#   -F : force rextraction
prepare_package()
{
local SRC="" OPT
local DISTCLEAN=N
local FORCE=N

  while [ "${1:0:1}" = "-" ]
  do
    OPT="$1"
    shift
    case $OPT in
	-D) DISTCLEAN=Y
	    ;;
        -F) FORCE=Y
	    ;;
        *) echo "ERROR: invalid option $OPT for prepare_package"
    esac
  done
  
  [ -z "$SRC" ] && SRC="${PACKAGE_DIR}"
  [ -z "$SRC" ] && get_package_dir && SRC="${PACKAGE_DIR}"
  [ -z "$SRC" ] && echo "ERROR: no PACKAGE_DIR in prepare_package()" && exit 1

  # Force extractzion if archive newer than package directory
  [ "${ARCHIVEROOT}/${ARCHIVE}" -nt "${SRC}" ] && FORCE=Y
  
  if [ -d "$SRC" ]
  then
    if [ $FORCE = Y ]
    then
      rm -Rf "$SRC"
    fi
    if [ -d "$SRC" -a $DISTCLEAN = Y -a $FORCE != Y ]
    then
      echo "Resetting environment..."
      catch_log distclean.log cd $SRC ";" [ ! -f Makefile ] "||" make distclean
      return
    fi
  fi
  echo "Extracting..."
  pushd .
  cd "${PACKAGEROOT}"
  tar xf "$ARCHIVE"
  popd
}

#------------------------------------------------------------
install_packages()
{
  sudo apt install -y "$@"
}

#------------------------------------------------------------
install_build_deps()
{
local pkg=$1
  #  sudo apt build-dep -y "$@"
  dpkg --list -a|grep -E -i -q "ii[[:space:]]+${pkg}-build-deps[[:space:]]" || mk-build-deps ${pkg} --install --root-cmd sudo --remov
}

#------------------------------------------------------------
# PACKAGE_DIR -> directory where configure is to be found
# %1... : configure options
auto_configure()
{
  echo "configuring package ${PACKAGE_DIR}..."
  if [ -z "${PREFIX}" ]
  then
    echo "auto_configure requires prefix to be defined !"
    exit 1
  fi
  catch_log configure.log "cd ${PACKAGE_DIR} ; ./configure $* --prefix=${PREFIX}"
}

#------------------------------------------------------------
# make package using make with passed argument
make_package()
{
  echo "building package ${PACKAGE_DIR}..."
  catch_log make.log "cd ${PACKAGE_DIR} ; make $*"
}

#------------------------------------------------------------
make_install()
{
  echo "installing package to ${PREFIX}..."
  catch_log install.log "cd ${PACKAGE_DIR} ; make install"
}

[ -f "${BUILDER_CONFIG}" ] && echo "reading ${BUILDER}.conf..." && source "${BUILDER_CONFIG}"

#------------------------------------------------------------
build_begin()
{
  true
}

#------------------------------------------------------------
build_end()
{
  echo ""
  echo "${TARGET} build complete"
  echo ""
  echo "Log files con be found in ${LOGDIR}"
  echo ""
}

#-----------------------------------------------------------------------------
reset_shell_options()
{
  [ -n "${SHELL_ENABLED_OPTS}" ] && shopt -s ${SHELL_ENABLED_OPTS}
  [ -n "${SHELL_DISABLED_OPTS}" ] && shopt -s ${SHELL_DISABLED_OPTS}
  SHELL_OPTS_STACK=() # clear stack
}

#-----------------------------------------------------------------------------
set_shell_options()
{
local OPT
local OPTS=""

  for OPT in $*
  do
    # We need a negative test, to avoid error trapping
    shopt -u | grep -q "^$OPT " 2>/dev/null || continue
    echo "setting option $OPT"
    OPTS="${OPTS} $OPT"
    shopt -s $OPT
  done
  [ -n "$OPTS" ] && SHELL_OPTS_STACK+=( "+ ${OPTS:1}" ) || SHELL_OPTS_STACK+=( "" )
}

#-----------------------------------------------------------------------------
unset_shell_options()
{
local OPT
local OPTS=""

  for OPT in $*
  do
    # We need a negative test, to avoid error trapping
    shopt -s | grep -q "^$OPT " 2>/dev/null || continue
    echo "unsetting option $OPT"
    OPTS="${OPTS} $OPT"
    shopt -u $OPT
  done
  [ -n "$OPTS" ] && SHELL_OPTS_STACK+=( "- ${OPTS:1}" ) || SHELL_OPTS_STACK+=( "" )
}

#-----------------------------------------------------------------------------
# %1 : number of shell option manipulations to undo
pop_shell_options()
{
local n=${1:-1}
local OPTS=

  while [ $n -gt 0 ]
  do
    n=$((n+1))
    OPTS="${SHELL_OPTS_STACK[-1]}"
    unset SHELL_OPTS_STACK[-1]
    [ "${OPTS:0:1}" = "-" ] && shopt -s ${OPTS:2} && continue
    [ "${OPTS:0:1}" = "+" ] && shopt -u ${OPTS:2} && continue
  done
  return 0
}


reset_shell_options # Bring script to expected behaviors

parse_build_cmd # Parse build.sh options command only

declare -r TARGET="${CMD_ARGS[0]}"
[ -z "$TARGET" ] && usage "package name missing" && exit 99
unset 'CMD_ARGS[0]'
declare -r BUILDER="build_${TARGET}"
declare -r BUILDER_SCRIPT="${BUILDERDIR}/${BUILDER}.sh"
declare -r BUILDER_CONFIG="${CONFDIR}/${BUILDER}.conf"

declare -r LOGDIR="${LOGROOT}/${BUILDER}"
[ ! -d "$LOGDIR" ] && mkdir "$LOGDIR"

if [ ! -f "${BUILDER_SCRIPT}" ]
then
  echo "ERROR: no builder (${BUILDER}) available for target ${TARGET}."
  exit 1   
fi

echo "reading builder file ${BUILDER}.sh"
source "${BUILDER_SCRIPT}" "${CMD_ARGS[@]}"

echo "reading config file ${BUILDER}.conf"
if [ -f ${BUILDER_CONFIG} ]
then
  source "${BUILDER_CONFIG}"
else
  if isFunction builder_default_config
  then
    builder_default_config "${BUILDER_CONFIG}"
    [ ! -f ${BUILDER_CONFIG} ] && echo "ERROR: builder_default_config was unable to create config file ${BUILDER_CONFIG}" && exit 1
    source "${BUILDER_CONFIG}"
  fi
fi

#-----------------------------------------------------------------------------
start_phase()
{
  list_item_since "${BUILD_PHASE_LIST}" "$1" "${BUILD_PHASES[0]}" || return 1
  list_item_until "${BUILD_PHASE_LIST}" "$1" "${BUILD_PHASES[1]}" && return 0

  echo ""
  echo "Build process aborted (by request) before '$1' phase"
  echo "You may continue the process using '${ME} --build ${1}- ${TARGET}'"
  echo ""
  exit 0 # This is not an error
}

#################################################################################

title "" "Building $TARGET" ""

if start_phase prepare
then  
  title2 "Preparing $TARGET"
  package_prepare
fi

if start_phase config
then  
  if isFunction package_prerequisites
  then
    title2 "Installing/preparing prerequisites for $TARGET"
    package_prerequisites
  fi

  if isFunction package_config
  then
    title2 "Configuring $TARGET"
    package_config
  fi
fi

if start_phase build
then  
  title2 "Building $TARGET"
  package_build
fi

if start_phase install
then  
  title2 "Preparing $TARGET deployment..."
  package_install
fi