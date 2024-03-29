#!/usr/bin/env bash

[[ ! "${BASH_VERSION:0:2}" =~ ^([0-9])+[.] ]] && echo "unexpected bash version number '${BASH_VERSION:0:2}' in '${BASH_VERSION}'" && exit 99
[ ${BASH_REMATCH[1]} -lt 5 ] && echo "build environment requires bash V5 as a minimum" && exit 99

#set -x

# -z : we got called to build single package from a list of packages (all but th elast package in the lsit will be done like this)
# -Z : we got called with a list of packages created from --all (in this mode we ignore --all)
#
# NOTE: if both are present -z is expected to preceed -Z because they get prepended and -Z issues from --all, where as then -z
#       get prepended to it by the sub process which handles the package list 
[ "$1" = "-z" ] && declare -r BUILD_SUB=Y && shift || declare -r BUILD_SUB=N
[ "$1" = "-Z" ] && declare -r BUILD_ALL=Y && shift || declare -r BUILD_ALL=N

# Allow trapping of command not found
unset -f command_not_found_handle

declare -r RUN_DIR="$PWD"
CMD_ARGS=( "$@" )
BUILD_PACKAGE_LIST=() # package list from command line
BUILD_ARGS=()   # args of build.sh (i.e. ORIG_CMD_ARGS minus package list)
declare -r ORIG_CMD_ARGS=( "$@" )
declare -r SCRIPT=$( realpath -e "$0" ) # Get called script
declare -r BUILD_LOG="${SCRIPT}.log"
declare -r ME=$(basename "${SCRIPT}")
BUILD_ROOT=$(dirname "${SCRIPT}")
BUILD_ROOT="${BUILD_ROOT:-.}"
declare -r BUILD_ROOT=$( readlink -e "$BUILD_ROOT" )
[ -z "$BUILD_ROOT" ] && echo "error: unexpected empty BUILD_ROOT variable." && exit 99

cd "$BUILD_ROOT" || exit 1

source gglib/include errmgr
Establish

declare -r BUILD_CONFIG_DIR="${BUILD_ROOT}/conf.d"
declare -r BUILDER_DIR="${BUILD_ROOT}/builders.d"
declare -r LOG_ROOT="${BUILD_ROOT}/logs"
declare -r PACKAGE_ROOT="${BUILD_ROOT}/packages"
declare -r ARCHIVE_ROOT="${PACKAGE_ROOT}"
declare -r DISTRIBUTE_DIR="${BUILD_ROOT}/distribute.d"
declare -r PERSISTENT_STORE_DIR="${BUILD_ROOT}/persist.d"
declare PERSISTENT_VARS=( BUILD_PHASE PERSISTENT_VARS PACKAGE_DOWNLOAD_LINK PACKAGE_ARCHIVE PACKAGE_TYPE PACKAGE_DIR PREFIX )

declare -r SHELL_ENABLED_OPTS="checkwinsize cmdhist complete_fullquote extquote force_fignore globasciiranges globskipdots hostcomplete interactive_comments patsub_replacement progcomp promptvars sourcepath"
declare -r SHELL_DISABLED_OPTS="autocd assoc_expand_once cdable_vars cdspell checkhash checkjobs compat31 compat32 compat40 compat41 compat42 compat43 compat44 direxpand dirspell dotglob execfail expand_aliases extdebug extglob failglob globstar gnu_errfmt histappend histreedit histverify huponexit inherit_errexit lastpipe lithist localvar_inherit localvar_unset login_shell mailwarn no_empty_cmd_completion nocaseglob nocasematch noexpand_translation nullglob progcomp_alias restricted_shell shift_verbose varredir_close xpg_echo"
SHELL_OPTS_STACK=()

BUILD_NEED_RESTART=N

PACKAGE_DIR=""
VERBOSE_LEVEL=0

declare -r BUILD_PHASE_LIST="prepare,prerequisites,config,build,saveconfig,install,deploy,restoreconfig"
declare -r BUILD_PHASE_COMMON=deploy # Here the common part starts
declare -r BUILD_PHASE_LAST_INDIVIDUAL=install
declare -r FIRST_BUILD_PHASE=${BUILD_PHASE_LIST%%,*}
declare -r LAST_BUILD_PHASE=${BUILD_PHASE_LIST##*,}
BUILD_PHASE=none

#-----------------------------------------------------------------------------
# usage: print out usage information
#
# %1 : optional error message
usage()
{
  if [ -n "$1" ]
  then
    echo ""
    echo "ERROR: $1"
  fi
  echo "" >&2
  echo "usage: ${ME} [<options>] <package>..." >&2
  echo "usage: ${ME} [<options>] -a" >&2
  echo "usage: ${ME} -e|--enable|-d|--disable <package>..." >&2
  echo "usage: ${ME} --list" >&2
  echo "usage: ${ME} -h" >&2
  echo "" >&2
  echo "options:" >&2
  echo "  -h|--help : help - display this help" >&2
  echo "  -a|--all  : build all enabled packages (see --list)"
  echo "  -l|--log  : log execution into logfile file ${ME}.log" >&2
  echo "  -L|--trace: log execution with trace into logfile file ${ME}.log" >&2
  echo "              Implies -x" >&2
  echo "  --list    : list all builders with their status" >&2
  echo "  -P|--purge: purge local installation directory" >&2
  echo "  -v        : increases verbosity level (multiple occurences" >&2
  echo "              cumulate" >&2
  echo "  -x|--debug: switch on bash command print out for debugging" >&2
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
#source ${BUILD_ROOT}/gglib/include errmgr
#Establish

# ...and then all other libraries
gglib_include all

#-----------------------------------------------------------------------------

#source ${BUILD_ROOT}/conf.d/config.sh
# Load and check config
source "${BUILD_ROOT}/ext/load_config.sh"

# Config variable enforcing
make_readonly_var TRUENAS_BACKUP_DIR $( dirname "${TRUENAS_DST}" )


# Sanity checks
check_equal_vars_W TRUENAS_DST STAGING_AREA
check_path_in_W TRUENAS_DST "/mnt"

DEFAULT_BUILD_PHASE=${DEFAULT_BUILD_PHASE:-build}
check_value_in DEFAULT_BUILD_PHASE "${BUILD_PHASE_LIST}"

need_directory "${PACKAGE_ROOT}"
need_directory "${PERSISTENT_STORE_DIR}"

# Default build phases
BUILD_PHASES=( ${FIRST_BUILD_PHASE} ${DEFAULT_BUILD_PHASE} )

#-----------------------------------------------------------------------------
list_builders()
{
local BUILDER PKG STATUS

  echo ""
  echo "List of all builders"
  echo "--------------------"
  echo ""

  while read BUILDER
  do
    BUILDER=$( basename "$BUILDER" )
    PKG="${BUILDER#build_}"
    PKG="${PKG%.sh}"
    [ -x "${BUILDER_DIR}/${BUILDER}" ] && STATUS="${TTY_COLOR_GREEN}enabled${TTY_NORMAL}" || STATUS="${TTY_COLOR_RED}disabled${TTY_NORMAL}"
    printf "%-16s (%s)\n" "${PKG}" $STATUS
  done < <( ls "${BUILDER_DIR}/build_"*.sh | sort)
  echo ""
}

#-----------------------------------------------------------------------------
check_not_logged()
{
  # We log through FD4 to make it detectable
  [ ! -e /proc/$$/fd/4 ] && return 0 # FD4 is not open
  local FD1=$( readlink /proc/$$/fd/1 )
  local FD2=$( readlink /proc/$$/fd/2 )
  local FD4=$( readlink /proc/$$/fd/4 )
  [ "${FD1}" != "${FD4}" ] && return 0
  [ "${FD2}" != "${FD4}" ] && return 0
  error "you cannot specify -l and -L multiple times or together"
  exit 99
}

#-----------------------------------------------------------------------------
parse_opt_build()
{
  [ -z "$1" ] && usage "--b|--build option requires an argument" && exit 99
  if [[ "$1" =~ ^([^-]*)([-]([^-]*))? ]]
  then
    # we have a valid syntax
    # end       : [1]=end [2]="" [3]=""
    # start-    : [1]=start [2]="-" [3]=""
    # -end      : [1]= [2]=-end [3]=end
    # start-end : [1]=start [2]=-end [3]=end
    if [ -n "${BASH_REMATCH[2]}" ]
    then # We have a dash
      local _start="${BASH_REMATCH[1]}"
      local _end="${BASH_REMATCH[3]}"
      # Not documented but we allow the -<end> syntax, which is equal to <end>
      # without '-' (dosumented)
    else
      # we have no '-'
      local _start=prepare
      local _end="${BASH_REMATCH[1]}"
    fi
  else
    error "invalid build phase(s) specififcation (--build $1)"
  fi

  [ -z "$_start" ] && _start=${FIRST_BUILD_PHASE}
  [ -z "$_end" ] && _end=${LAST_BUILD_PHASE}
  check_value_in _start "${BUILD_PHASE_LIST}" "'${_start}' is invalid value for -b|--build"
  check_value_in _end   "${BUILD_PHASE_LIST}" "'${_end}' is invalid value for -b|--build"
  BUILD_PHASES=( $_start $_end )
  list_item_since "${BUILD_PHASE_LIST}" "${_end}" "${_start}" || error "the end phase '${_end}' cannot be before the start '${_start}'"
  check_array_size BUILD_PHASES 2 2 "BUG: BUILD_PHASES should have 2 values"
  verbose 1 "  processing phases ${_start} to ${_end}..."
}

#-----------------------------------------------------------------------------
BUILD_OPT_ALL=N # Presence of --all
parse_build_cmd()
{
local OPT
local idx=0
declare -g BUILD_ARGS=()
local oo=0 # Counts operational options

  set -- "${CMD_ARGS[@]}"
  while [ "${1:0:1}" = "-" ]
  do
    OPT="$1"
    BUILD_ARGS+=( ${OPT} )
    idx=$((idx+1))
    oo=$((oo+1))
    shift
    case $OPT in
        -h|--help) usage
                   exit 0
                   ;;
        -a|--all)  [ ${BUILD_ALL} = Y ] && continue # Already in build-all mode
                   BUILD_OPT_ALL=Y
                   ;;
        -P|--purge) [ ${BUILD_ALL} = Y ] && continue # was handled by parent
                    purge_directory "${STAGING_AREA}"
                    ;;
        -e|--enable|-d|--disable)
                   [ ${oo} -gt 1 ] && usage "enable/disable options cannot be mixed with other operational options" && exit 99
                   BUILD_ARGS+=( "$@" )
                   CMD_ARGS=( "$OPT" "$@" )
                   _manage_packages
                   exit 0
                   ;;
        -l|--log)
                   echo "logging execution..." >&2
	           check_not_logged
	           unset BUILD_ARGS[-1] # Do not propagate -l
		   exec 4> >(tee "${BUILD_LOG}") 1>&4 2>&4
                   ;;
        -L|--trace)
                   echo "logging execution trace..." >&2
	           check_not_logged
	           unset BUILD_ARGS[-1] # Do not propagate -L
		   BUILD_ARGS+=( "-x" ) # But replace by --trace (aka. -x)
                   set -x
                   /usr/bin/env bash -x "${SCRIPT}" "${BUILD_ARGS[@]}"  "$@" 4> >( tee "${BUILD_LOG}" ) 1>&4 2>&4
                   exit $?
                   ;;
        -b|--build) parse_opt_build "$1"
                    BUILD_ARGS+=( "$1" )
                    shift
                    ;;
        -v) VERBOSE_LEVEL=$((VERBOSE_LEVEL+1))
            oo=$((oo-1)) # Not  operational
            ;;
        -x|--debug)
            oo=$((oo-1)) # Not  operational
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
  BUILD_PACKAGE_LIST=( "$@" )
}

#------------------------------------------------------------
_manage_packages()
{
local ARG ENABLE=X

  set -- "${CMD_ARGS[@]}"
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
      BUILDER="${BUILDER_DIR}/build_${ARG}.sh"
      if [ -f "${BUILDER}" -o -f "${BUILDER}.disabled" ]
      then
        [ $ENABLE = X ] && echo "BUG: unexpected unknown enabler setting" && exit 1
        [ $ENABLE = Y -a ! -f "${BUILDER}.disabled" ] && verbose 1  "  ${ARG} builder already enabled..."
        [ $ENABLE = N -a ! -f "${BUILDER}" ] && verbose 1  "  ${ARG} builder already disabled..."
        [ $ENABLE = Y -a -f "${BUILDER}.disabled" ] && verbose 1  "  enabling ${ARG} builder..." && mv "${BUILDER}.disabled" "${BUILDER}"
        [ $ENABLE = N -a -f "${BUILDER}" ] && verbose 1  "  disabling ${ARG} builder..." && mv "${BUILDER}" "${BUILDER}.disabled"
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

  BUILD_PACKAGE_LIST=()
  
  while read -u 3 BUILDER
  do
    BUILDER=$( basename "$BUILDER" )
    local PACKAGE_NAME=""
    [[ "${BUILDER}" =~ ^build_(.+)[.]sh([.]disabled)?$ ]] && PACKAGE_NAME="${BASH_REMATCH[1]}"
    echo ""
    echo "=========================================================================="
    if [ -z "${BASH_REMATCH[2]}" ]
    then
      echo "selecting package ${PACKAGE_NAME}..."
      BUILD_PACKAGE_LIST+=( ${PACKAGE_NAME} )
    else
      echo "INFO: ${PACKAGE_NAME} is disabled." >&2
    fi
  done 3< <( find ${BUILDER_DIR} -maxdepth 1 -name "build_*.sh" -o -name "build_*.sh.disabled"| sort )

  ${SCRIPT} -Z "${BUILD_ARGS[@]}" "${BUILD_PACKAGE_LIST[@]}"
  exit $?
}

#------------------------------------------------------------
# %1 : Link
# Output:
#  PACKAGE_DOWNLOAD_LINK=%1 & PACKAGE_ARCHIVE=%2 or extracted arhgive name
#  PACKAGE_DIR : path to package diorectory
#  PACKAGE_TYPE=github
get_github()
{
  declare -g PACKAGE_DOWNLOAD_LINK="$1"
  declare -g PACKAGE_ARCHIVE="${1##*/}"
  declare -g PACKAGE_TYPE=github

  PACKAGE_ARCHIVE="${PACKAGE_ARCHIVE%.git}"
  declare -g PACKAGE_DIR="${PACKAGE_ROOT}/${PACKAGE_ARCHIVE}"
  check_directory -o "${PACKAGE_DIR}"
  if [ -d "${PACKAGE_DIR}" ]
  then
    echo "  fetching ${PACKAGE_ARCHIVE}..."
    ( cd "${PACKAGE_DIR}" ; git fetch )
  else
    echo "  cloning ${PACKAGE_ARCHIVE}..."
    ( cd "${PACKAGE_ROOT}" ; git clone "$1" )
  fi
}

#------------------------------------------------------------
# %1 : Link
# %2 : oprional archive name
#
# Output:
#  PACKAGE_DOWNLOAD_LINK=%1 & PACKAGE_ARCHIVE=%2 or extracted arhgive name
# PACKAGE_TYPE=archive
download_archive()
{
  local OPTS
  pushd . >/dev/null
  cd "${PACKAGE_ROOT}"
  parse_func_options "download_archive" "N=new" "$@"
  set -- "${GGLIB_OPT_ARGS[@]}"

declare -g PACKAGE_DOWNLOAD_LINK="$1"
declare -g PACKAGE_ARCHIVE="$2"
declare -g PACKAGE_TYPE=archive

  local LA="${PACKAGE_DOWNLOAD_LINK##*/}"
  LA="${LA%%\?*}"

  # Need extract arcive name
  if [ -z "$PACKAGE_ARCHIVE" -o "${PACKAGE_ARCHIVE}" = "${LA}" ]
  then
    PACKAGE_ARCHIVE="${LA}"
    OPTS="-N"
  else
    OPTS="-O ${PACKAGE_ARCHIVE}" # cannot use -N
    [ -f "${PACKAGE_ARCHIVE}" ] && popd >/dev/null && return 0 # ...so we simply do not download existing
  fi

  [ -z "$PACKAGE_ARCHIVE" ] && echo "no archive name in download_archive()" && exit 1

  # Use uf/then to aboid error trap if archive exists
  #if [ ! -f ${PACKAGE_ARCHIVE} -o "${BUILD_PARSED_OPTS[new]}" = "Y" ]
  #then
  echo "Retrieving ${PACKAGE_ARCHIVE}..."
  wget -c $OPTS $PACKAGE_DOWNLOAD_LINK
  #else
  #  echo "Keeping existing $PACKAGE_ARCHIVE"
  #fi
  popd >/dev/null
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

  if [ "${PACKAGE_TYPE}" = "github" ]
  then
    check_var PACKAGE_DIR "get_github() should have set PACKAGE_DIR"
    return 0
  fi


  [ -z "$ARC" ] && ARC="${PACKAGE_ARCHIVE}"
  ARC="${PACKAGE_ROOT}/${ARC}"
  local SRC=$( tar tvf "${ARC}" | head -1 )
  if [[ "$SRC" =~ [[:space:]]([^/[:space:]]+)[/][[:space:]]*$ ]]
  then
    declare -g PACKAGE_DIR="${PACKAGE_ROOT}/${BASH_REMATCH[1]}"
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
#   -G : github package (no extraction required)
prepare_package()
{
local SRC="" OPT
local distclean=N
local FORCE=N
local github=N

  while [ "${1:0:1}" = "-" ]
  do
    OPT="$1"
    shift
    case $OPT in
        -D) BUILD_MAKE_DISTCLEAN=Y
            ;;
        -F) FORCE=Y
            ;;
        -G) github=Y
            ;;
        *) echo "ERROR: invalid option $OPT for prepare_package"
    esac
  done

  SRC="$1"
  [ -z "$SRC" ] && SRC="${PACKAGE_DIR}"
  [ -z "$SRC" ] && get_package_dir && SRC="${PACKAGE_DIR}"
  [ -z "$SRC" ] && echo "ERROR: no PACKAGE_DIR in prepare_package()" && exit 1

  # Force extractzion if archive newer than package directory
  [ "${PACKAGE_TYPE}" = "archive" -a "${ARCHIVE_ROOT}/${PACKAGE_ARCHIVE}" -nt "${SRC}" ] && FORCE=Y
  [ "${PACKAGE_TYPE}" != "archive" ] && FORCE=N # Never force non-archive

  if [ -d "$SRC" ]
  then
    if [ $FORCE = Y ]
    then
      rm -Rf "$SRC"
    fi
    if [ -d "$SRC" -a ${distclean} = Y -a $FORCE != Y ]
    then
      echo "Resetting environment..."
      catch_log distclean.log cd "$SRC" ";" [ ! -f Makefile ] "||" make distclean
      return
    fi
  fi
  if [ "${PACKAGE_TYPE}" = "archive" ]
  then
    echo "Extracting..."
    pushd . >/dev/null
    cd "${PACKAGE_ROOT}"
    tar xf "$PACKAGE_ARCHIVE"
    popd >/dev/null
  fi
}

#------------------------------------------------------------
snap_install()
{
  command -v snap || install_packages snapd
  sudo snap install "$@"
}

#------------------------------------------------------------
install_packages()
{
  sudo apt install -y "$@"
  Establish # For some reason above command may disables trap
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
  catch_log configure.log "cd ${PACKAGE_DIR} ; ./configure $@ --prefix=${PREFIX}"
}

#------------------------------------------------------------
# make package using make with passed argument
make_deps()
{
  echo "resolving package deps in ${PACKAGE_DIR}..."
  catch_log make_deps.log "cd ${PACKAGE_DIR} ; make deps"
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
  echo "Log files can be found in ${LOG_DIR}"
  echo ""
}

#-----------------------------------------------------------------------------
reset_shell_options()
{
  [ -n "${SHELL_ENABLED_OPTS}" ] && eval shopt -s ${SHELL_ENABLED_OPTS}
  [ -n "${SHELL_DISABLED_OPTS}" ] && eval shopt -u ${SHELL_DISABLED_OPTS}
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
#echo "BUILD_ARGS  =${BUILD_ARGS}"
#echo "BUILD_PACKAGE_LIST=${BUILD_PACKAGE_LIST}"

# Handle --all
if [ ${BUILD_OPT_ALL} = Y ]
then
  [ -n "${BUILD_PACKAGE_LIST[0]}" ] && error "--all option does not allow package name"
  _build_all
  exit $?
fi

if [ ${#BUILD_PACKAGE_LIST[@]} -gt 1 ]
then
  # Multi package build, either on users explicit request or as call back from --all (BUILD_ALL=Y)
  # We build all but the last one by calling a supprocess. We also limit the build process up to the
  # last not-common part

  # Of the 2 words passed returns the one (in specified var) which is earliest in the list
  # %1 : list
  # %2 : word1
  # %3 : word2
  # %4 : var (for result)
  # %5 : sep (optional)
  if list_item_since "${BUILD_PHASE_LIST}" "${BUILD_PHASES[0]}" "${BUILD_PHASE_COMMON}"
  then
    # If we start at the common part, we do not have to repeat it for each package
    printf "Start phase ${BUILD_PHASES[0]} being common to all packages, the following packages are not processed (no need):\n  "
    while [ ${#BUILD_PACKAGE_LIST[@]} -gt 1 ]
    do
      printf "%s" "${BUILD_PACKAGE_LIST[0]}"
      BUILD_PACKAGE_LIST=( "${BUILD_PACKAGE_LIST[@]:1}" )
      [ ${#BUILD_PACKAGE_LIST[@]} -gt 1 ] && printf ", "
    done
    printf "\n"
  else    
    get_earliest_of "${BUILD_PHASE_LIST}" "${BUILD_PHASE_LAST_INDIVIDUAL}" "${BUILD_PHASES[1]}" _build_to
    # Add --build if we hasve to shorten the run
    [ "${_build_to}" != "${BUILD_PHASES[1]}" ] && BUILD_ARGS+=( "--build" "${BUILD_PHASES[0]}-${_build_to}" )
    echo "Package build list: ${BUILD_PACKAGE_LIST[@]} "
    while [ ${#BUILD_PACKAGE_LIST[@]} -gt 1 ]
    do
      PACKAGE="${BUILD_PACKAGE_LIST[0]}"
      BUILD_PACKAGE_LIST=( "${BUILD_PACKAGE_LIST[@]:1}" )
      ${SCRIPT} -Z "${BUILD_ARGS[@]}" "${PACKAGE}"
    done
  fi
  # Now we run through to process the last package using the initial phases
fi

declare -r TARGET="${BUILD_PACKAGE_LIST[0]}"
[ -z "$TARGET" ] && usage "package name missing" && exit 99
unset 'CMD_ARGS[0]'
declare -r BUILDER="build_${TARGET}"
declare -r BUILDER_SCRIPT="${BUILDER_DIR}/${BUILDER}.sh"
declare -r BUILDER_CONFIG="${BUILD_CONFIG_DIR}/${BUILDER}.conf"
declare -r PERSISTENT_STORE="${PERSISTENT_STORE_DIR}/${BUILDER}.store"

declare -r LOG_DIR="${LOG_ROOT}/${BUILDER}"
[ ! -d "$LOG_DIR" ] && mkdir "$LOG_DIR"

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
  declare -g BUILD_PHASE="$1"
  list_item_since "${BUILD_PHASE_LIST}" "$1" "${BUILD_PHASES[0]}" || return 1
  list_item_until "${BUILD_PHASE_LIST}" "$1" "${BUILD_PHASES[1]}" && return 0

  local _args=( "${BUILD_ARGS[@]}" )
  delete_option_from_array _args "--build" 1
  delete_option_from_array _args "-b" 1
  _args=( "${_args[@]}" "${BUILDER_ARGS[@]}" )
  # We do not have to show follow-up command for any sub-build
  if [ ${BUILD_SUB} = N ]
  then    
    echo ""
    echo "Build process aborted (by request) before '$1' phase"
    echo "You may continue the process using '${SCRIPT} --build ${1}- ${_args[@]}'"
    echo ""
  fi
  build_end
  exit 0 # This is not an error
}

#-----------------------------------------------------------------------------
need_restart()
{
  [ "${BUILD_PHASE}" != "prerequisites" ] && echo "ERROR: need_restart is only allowed in prerequisites phase" >&2 && exit 1
  verbose 1 "build restart requested"
  BUILD_NEED_RESTART=Y
}

#-----------------------------------------------------------------------------
purge_persist()
{
  [ -f "${PERSISTENT_STORE}" ] && rm -f "${PERSISTENT_STORE}"
  make_persist
}

#-----------------------------------------------------------------------------
make_persist()
{
  [ -f "${PERSISTENT_STORE}" ] && return 0
  echo "#!/usr/bin/env bash" > "${PERSISTENT_STORE}"
}

#-----------------------------------------------------------------------------
# %1... : var defs
persist()
{
  [ ! -f "${PERSISTENT_STORE}" ] && touch "${PERSISTENT_STORE}"
  while [ -n "$1" ]
  do
    echo "$1" >> "${PERSISTENT_STORE}"
    shift
  done
}

#-----------------------------------------------------------------------------
# %1... : var
add_persist_vars()
{
  while [ -n "$1" ]
  do
    [[ " ${PERSISTENT_VARS[*]} " =~ [[:space:]]$1[[:space:]] ]] && shift && continue
    PERSISTENT_VARS+=( $1 )
    shift
  done
}

#-----------------------------------------------------------------------------
save_vars()
{
local _v _e

  purge_persist
  for _v in ${PERSISTENT_VARS[*]}
  do
    eval [ -z \"\${$_v+x}\" ] && continue # Variable unset
    declare -p ${_v} >> "${PERSISTENT_STORE}"
  done
}


#################################################################################

title "" "Building $TARGET" ""

if [ "${BUILD_PHASES[0]}" != "${FIRST_BUILD_PHASE}" ]
then
  [ ! -f "${PERSISTENT_STORE}" ] && error "no persisten store found for ${BUILDER}, build must start at '${FIRST_BUILD_PHASE}' phase"
  echo "  resuming build process at ${BUILD_PHASES[0]}"
  [ -f "${PERSISTENT_STORE}" ] && echo "loading saved variables..." && source "${PERSISTENT_STORE}"
fi

# We have a build phase from last run
if [ "${BUILD_PHASE}" != none ]
then
  _p=$( get_list_item_after "${BUILD_PHASE_LIST},end" "${BUILD_PHASE}" )
  [ "${BUILD_PHASES[0]}" = "unknown" ] && BUILD_PHASES[0]="${_p}"
  if ! list_item_until "${BUILD_PHASE_LIST}" "${BUILD_PHASE[0]}" "${_p}"
  then
    info "the prior run ended at phase '${BUILD_PHASE}'"
    error "start phase could therefor be no more than '${_p}'"
  fi
  unset _p
else
  BUILD_PHASES[0]="${FIRST_BUILD_PHASE}"
fi

build_begin

#--------------------------------------
if start_phase prepare
then
  title2 "Preparing $TARGET"
  purge_persist
  Establish
  package_prepare
  save_vars
fi

#--------------------------------------
if start_phase prerequisites
then
  if isFunction package_prerequisites
  then
    title2 "Installing/preparing prerequisites for $TARGET"
    Establish
    package_prerequisites
    Establish
    save_vars
  fi
fi

if [ "${BUILD_NEED_RESTART}" = "Y" ]
then
  # Note we cannot append --build because it would be a builder option, so we have to prepend it
  # and thus delete any --b|--build in th eoriginal arguments
  ARGS=( "${ORIG_CMD_ARGS[@]}" )
  delete_option_from_array ARGS "-b" 1
  delete_option_from_array ARGS "--build" 1
  verbose 1 "restarting build script upon builder request"
  verbose 2  bash -i "${SCRIPT}" --build config-${BUILD_PHASES[1]} "${ARGS[@]}"
  save_vars
  exec bash -l -i "${BUILD_ROOT}/${ME}" --build config-${BUILD_PHASES[1]} "${ARGS[@]}"
  echo "BUG: This line should never be reached !!!"
  exit 0
fi

#--------------------------------------
if start_phase config
then
  if isFunction package_config
  then
    title2 "Configuring $TARGET"
    Establish
    package_config
    save_vars
  fi
fi

#--------------------------------------
if start_phase build
then
  title2 "Building $TARGET"
  Establish
  package_build
  save_vars
fi

# Starting here we need the deployment part
cd "${BUILD_ROOT}"
source ext/deploy.sh

#--------------------------------------
start_phase saveconfig && deploy saveconfig

#--------------------------------------
if start_phase install
then
  title2 "Preparing $TARGET deployment..."
  Establish
  package_install
  save_vars
  cd "${BUILD_ROOT}"
fi

#--------------------------------------
start_phase deploy && deploy deploy

#--------------------------------------
start_phase restoreconfig && deploy restoreconfig

build_end
