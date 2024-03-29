#!/usr/bin/env bash

# TRUENAS is the ip address or FQDN of the TrueNAS Scale server
declare -r TRUENAS="nas.example.net"

# TRUENAS_DST is the prefix path used for installation of the packages
#
# IMPORTANT NOTE:
#
# The path specified here should be solely used for installation of packaged via the TrueNAS
# sidecar tool. Placing external files into this path (including aLL all its subdirectories)
# may lead to unpredictible behaviors and most probably loss of these files
#
declare -r TRUENAS_DST="/mnt/data/admin/opt"
#-> make_readonly_var
#-> check_readonly_var
#-> check_absolute_path
#-> check_equal_vars_W {} STAGING_AREA
#-> check_path_in_W TRUENAS_DST "/mnt"

#<># declare -r DST_USER=admin
declare -r SIDECAR_USER=admin
#-> make_readonly_var
#-> check_readonly_var
#<># declare -r DST_GROUP=admin
declare -r SIDECAR_GROUP=admin
#-> make_readonly_var
#-> check_readonly_var

# The default build phase executed when build is called without
# manually spcifying the phase
# prepare | config | build | install
DEFAULT_BUILD_PHASE=saveconfig
#-> check_value_in {} "${BUILD_PHASE_LIST}"

# Enbale Backup of current state of deploymentares on NAS
# Y = Enable
# N = Disable
TRUENAS_BACKUP=Y
#-> check_yes_no

# Destination directory of the backup archive
# MUST be an absolute path !!!
# If not set, the parent directory of the deployment
# area is chosen
TRUENAS_BACKUP_DIR=
#-> make_readonly_var {} $( dirname "${TRUENAS_DST}" )
#-> check_readonly_var
#-> check_absolute_path -o

# Archive name without extension
TRUENAS_BACKUP_ARCHIVE=
#-> make_readonly_var {} $( basename "${TRUENAS_DST}" )
#-> check_readonly_var

# Backup bersions to keep (each deployment creates a new one)
TRUENAS_BACKUP_VERSIONS=5
#-> check_int_range {} 0

# A very sensible part of the deployment process are the configuration files.
# This is highly sensible because we have no control over the build ands installation
# process
#
# The package scripts may install configuration files in the process. It should
# avoid to overwrite existing config files however.
#
# In theory 3 scenarios may occur:
#   1. the config files are overwritten each time
#   2. existing config files are never overwritten
#   3. existing config files are only not overwritten if they are
#      newer than the binary
#
# The following settings allow control over how the deply script will handle these
# situations:

# DEPLOY_CONFIG_KEEP must be Y for the script to attempt saving  any config files
#
# CAUTION: THINK TWICE BEFORE DISABLING
#
#          Deployment to the NAS is doen with rsync --delete to allow for removing
#          packages by purging the staging area and not building the package
#          to be removed. On the other hand you may have packages that allow for
#          config includes, i.e. the main config file including user config files which
#          are not part of the initial installation (for example site config files in
#          apache). In such scenarios the package deployment will delete these user config
#          files resulting in data/functionality loss.
#
#          This can be avoided with DEPLOY_CONFIG_KEEP=Y (see documentation for more information)
DEPLOY_CONFIG_KEEP=Y
#-> check_yes_no

# The following setting instructs the deployment process not to expect any site-specific
# config files. I.e. files added to the NAS sidecar by the user (this does not impact the
# editing of existing files iunitially installed by the package)
#
# CAUTION WHEN ENABLING THIS !!!
#
# If a user adds any file to the NAS sidecar which are not present in any installed package
# (i.e. not present in the staging area) these files WILL BE DELETED if the following setting is
# 'Y'
#
# Caution also with side-effects (see docs)
DEPLOY_NO_SITE_CONFIG_FILES=N
#-> check_yes_no

# Reverse sync is a fallback sync (i.e. an additional safty net) in order to avoid overwriting of
# config files on deployment. Overwritten config files should be recovered through the 3-way
# config syncs as well.
#
# Note that this setting does only sync back modified config files existing in the staging area
# (i.e. part of the initial package install).
DEPLOY_CONFIG_REVERSE_SYNC=Y

# This setting increases the probably to keep configuration files safe (in scenarios 1&3),
# while  having the side effect of updating the concerned files creation time to the current
# time.
#
DEPLOY_CONFIG_TOUCH=Y
#-> check_yes_no

# By default config syncing is done by checking which files have been changed since last
# deployment. This does however only work if the config file in the staging (local) area
# has not been altered since last deployment  (either scenario 2 or deploy.sh in save-config
# mode before any new build is staged)
#
# Dual sync can be used to reduce the overwriting probability of config files. The primary sync
# copies files on the NAS modified after the file in the staging area to the distribute.d
#
# The secondary (dual) sync then additionally forces syncs of any file existing in the distribute.d
# directory.
#
# The idea behind this is that any file once detected as config file, will always remain a
# config file
DEPLOY_CONFIG_DUAL_SYNC=Y
#-> check_yes_no

# DEPLOY_CONFIG_CLEANUP controls how config files deleted on the NAS but present in the
# config vault are handled.
DEPLOY_CONFIG_CLEANUP=Y

# List of known config directories
DEPLOY_CONFIG_DIRS=( "/etc" "/usr/local/etc" )

#-----------------------------------------------------------------------------

# Source and destination must be same as some builds hardcode installation path information
# STAGING_AREA is local destination path (i.e. same as TRUENAS_DST)
#<># LOCAL_DST="${TRUENAS_DST}"
STAGING_AREA="${TRUENAS_DST}"
#-> check_absolute_path

#<># PREFIX="${LOCAL_DST}"
PREFIX="${STAGING_AREA}"
#-> check_absolute_path

#<># LIBDIRS=( /lib /lib64 /usr/lib /usr/lib64 /usr/local/lib /usr/local/lib64 )
LIB_SEARCH_PATH=( /lib /lib64 /usr/lib /usr/lib64 /usr/local/lib /usr/local/lib64 )
#-> check_array check_absolute_path
BINDIRS=( /bin /usr/bin /usr/local/bin /sbin /usr/sbin )
#-> check_array check_absolute_path

##############################################################################

DEV_USER=$( id -un )
DEV_UID=$( id -u )
DEV_GID=$( id -g )

[ ${DEV_USER} = root -o ${DEV_UID} -eq 0 -o ${DEV_GID} -eq 0 ] && echo "ERROR: this script is not expected to run under root (or other superuser)" && exit 99
#<># if [ ! -d "${LOCAL_DST}" ]
if [ ! -d "${STAGING_AREA}" ]
then
#<>#   sudo mkdir -p "${LOCAL_DST}" && sudo chown ${DEV_USER} "${LOCAL_DST}"
  sudo mkdir -p "${STAGING_AREA}" && sudo chown ${DEV_USER} "${STAGING_AREA}"
  [ $? -ne 0 ] && exit 99 # Error output expected form commands above
fi
true # Make sure status is OK
