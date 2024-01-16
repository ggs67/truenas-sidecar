
# NAS is the ip address or FQDN of the TrueNAS Scale server
NAS="nas.example.net"

# TRUENAS_DST is the prefix path used for installation of the packages
#
# IMPORTANT NOTE:
#
# The path specified here should be solely used for installation of packaged via the TrueNAS
# sidecar tool. Placing external files into this path (including aLL all its subdirectories)
# may lead to unpredictible behaviors and most probably loss of these files
# 
TRUENAS_DST="/mnt/data/admin/opt" #-> check_absolute_path

DST_USER=admin
DST_GROUP=admin

# The default build phase executed when build is called without
# manually spcifying the phase
# prepare | config | build | install
DEFAULT_BUILD_PHASE=build #-> check_value_in {} "prepare,config,build,install"

# Enbale Backup of current state of deploymentares on NAS
# Y = Enable
# N = Disable
TRUENAS_BACKUP=Y #-> check_yes_no

# Destination directory of the backup archive
# MUST be an absolute path !!!
# If not set, the parent directory of the deployment
# area is chosen
TRUENAS_BACKUP_DIR= #-> check_absolute_path -o

# Archive name without extension
TRUENAS_BACKUP_ARCHIVE=$(basename "${TRUENAS_DST}")

# Backup bersions to keep (each deployment creates a new one)
TRUENAS_BACKUP_VERSIONS=5 #-> check_int_range {} 0

# A very sensible part of the deployment process are the configuration files.
# This is highly sensible because we have no control over the build ands installation
# process
#
# The package scripts may install configuration files in the process. It should
# avoid to overwrite existing config files however.
#
# In theory 3 scenarios may occur:
#   - the config files are overwritten each time
#   - existing config files are never overwritten
#   - existing config files are only not overwritten if they are
#     newer than the binary
#
DEPLOY_CONFIG_KEEP=Y #-> check_yes_no
DEPLOY_CONFIG_TOUCH=N #-> check_yes_no
DEPLOY_CONFIG_REVERSE_SYNC=Y  #-> check_yes_no

#-----------------------------------------------------------------------------

# Source and destination must be same as some builds hardcode installation path information
# LOCAL_DST is local destination path (i.e. same as DST)
LOCAL_DST="${TRUENAS_DST}"  #-> check_absolute_path

PREFIX="${LOCAL_DST}" #-> check_absolute_path

LIBDIRS=( /lib /lib64 /usr/lib /usr/lib64 /usr/local/lib /usr/local/lib64 ) #-> check_array check_absolute_path
BINDIRS=( /bin /usr/bin /usr/local/bin /sbin /usr/sbin ) #-> check_array check_absolute_path

##############################################################################

DEV_USER=$( id -un )
DEV_UID=$( id -u )
DEV_GID=$( id -g )

[ ${DEV_USER} = root -o ${DEV_UID} -eq 0 -o ${DEV_GID} -eq 0 ] && echo "ERROR: this script is not expected to run under root (or other superuser)" && exit 99
if [ ! -d "${LOCAL_DST}" ]
then
  sudo mkdir -p "${LOCAL_DST}" && sudo chown ${DEV_USER} "${LOCAL_DST}"
  [ $? -ne 0 ] && exit 99 # Error output expected form commands above
fi
true # Make sure status is OK