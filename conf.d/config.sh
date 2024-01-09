
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
TRUENAS_DST="/mnt/data/admin/opt"


DST_USER=admin
DST_GROUP=admin

# The default build phase executed when build is called without
# manually spcifying the phase
# prepare | config | build | install
DEFAULT_BUILD_PHASE=build

#-----------------------------------------------------------------------------

# Source and destination must be same as some builds hardcode installation path information
# LOCAL_DST is local destination path (i.e. same as DST)
LOCAL_DST="${TRUENAS_DST}" 

PREFIX="${LOCAL_DST}"

LIBDIRS=( /lib /lib64 /usr/lib /usr/lib64 /usr/local/lib /usr/local/lib64 ) 
BINDIRS=( /bin /usr/bin /usr/local/bin /sbin /usr/sbin )

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
