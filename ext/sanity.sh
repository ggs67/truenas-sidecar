#!/usr/bin/env bash

#set -x

#<># source ${BUILD_DIR}/gglib/include errmgr checks present
source ${BUILD_ROOT}/gglib/include errmgr checks present
Establish

# This script does pre-installation sanity checks in an attempt top avoid common problems, especially with time differences

# First lets check for same time zone
do_sanity_checks()
{
#<># local SSH=( "ssh" "root@${NAS}" )
local SSH=( "ssh" "root@${TRUENAS}" )
local LTZ=$( timedatectl | grep -E -i 'time[[:space:]]*zone[[:space:]]*[:]' ) || true
local RTZ=$( "${SSH[@]}" timedatectl | grep -E -i 'time[[:space:]]*zone[[:space:]]*[:]' ) || true
local _status="OK"
local _local _remote

  title "" "Sanity checks" "Avoiding synch and compatibility issues" ""

  # 1. CHECK TIMEZONES

  check_var LTZ "local timezone could not be retrieved"
  check_var RTZ "remote timezone could not be retrieved"

  verbose 1 "Checking local and NAS timezone match"

  [[ "$LTZ" =~ [:][[:space:]]*([^[:space:]]+) ]] && LTZ="${BASH_REMATCH[1]}" || true
  [[ "$RTZ" =~ [:][[:space:]]*([^[:space:]]+) ]] && RTZ="${BASH_REMATCH[1]}" || true

#<>#   [ "$RTZ" != "$LTZ" ] && error "local timezone and NAS MUST be identical, local=${LTZ} NAS=${RTZ}" || true
  [ "$RTZ" != "$LTZ" ] && error "local timezone and NAS MUST be identical, local=${LTZ} TRUENAS=${RTZ}" || true

#<>#   verbose 1 "  timezones match: local=${LTZ} NAS=${RTZ}"
  verbose 1 "  timezones match: local=${LTZ} NAS=${RTZ}"

  # 2. CHECK TIME DIFFERENCE
  local _warn=10
  local _allow=30
  verbose 1 "Checking local and NAS time difference"

  # NOTE: The easiest and most precise way would have been to use NTP tools
  #       to query the time difference. chrony (the NTP server) on TrueNAS
  #       is however configured by default not to allow remote queries,
  #       so we revert to command line tools

  # SSH first for lowest delay between commands as connection, login
  #     and command start are expected to be longer than the command
  #     rundown and ssh disconnect after the output of the time
  local _rt=$( "${SSH[@]}" date \"+%d-%m-%Y %H:%M:%S\|%s\")
  local _lt=$( date "+%d-%m-%Y %H:%M:%S|%s" )

  local _lts=$( echo "$_lt" | cut -d '|' -f 2 )
        _lt=$( echo "$_lt" | cut -d '|' -f 1 )

  local _rts=$( echo "$_rt" | cut -d '|' -f 2 )
        _rt=$( echo "$_rt" | cut -d '|' -f 1 )

  local _diff=$((rts-lts))
  local _dir="in advance"
  [ $_diff -lt 0 ] && _dir="late" && _diff=$((-_diff))

  _status=OK
  [ ${_diff} -gt ${_warn} ] && _status="WARN"
  [ ${_diff} -gt ${_allow} ] && _status="ERROR"
#<>#   verbose 1 "  time difference ${_status}: local=${_lt} NAS=${_rt}"
  verbose 1 "  time difference ${_status}: local=${_lt} TRUENAS=${_rt}"

  if [ $_diff -eq 0 ]
  then
    verbose 1 "  time between the NAS and local system is perfectly synchronized"
  else
    verbose 1 "  NAS is ${_dir} by ${_diff} seconds to local system"

    [ ${_diff} -gt ${_allow} ] && error "the time difference between the NAS and the local system is to high (${_diff} > ${_allow})"
    [ ${_diff} -gt ${_warn} ] && warn "the time difference between the NAS and the local system is to high (${_diff} > ${_warn})\n  PLEASE MAKE SURE TO SPACE CONSECUTIVE INSTALLATIONS AT LEAST BY $((_allow+5)) seconds\n  OR BETTER abort now and synchronize time before installing" 15
  fi

  # 3. CHECK OS VERSIONS
  verbose 1 "checking local and NAS distribution versions"
  _local=$( cat /etc/os-release )
  _remote=$( "${SSH[@]}" cat /etc/os-release )

  local _local_version=$( echo "$_local" | grep '^VERSION_ID=' )
  local _local_dist=$( echo "$_local" | grep '^ID=' )
  [[ "${_local_version}" =~ ^VERSION[_]ID[=][\"]?([^\"]+) ]] && _local_version="${BASH_REMATCH[1]}" || true
  [[ "${_local_dist}" =~ ^ID[=][\"]?([^\"]+) ]] && _local_dist="${BASH_REMATCH[1]}" || true

  [ -z "${_local_version}" ] && error "local distribution version could not be identified for sanity check" || true
  [ -z "${_local_dist}" ] && error "local distribution could not be identified for sanity check" || true

  local _remote_version=$( echo "$_remote" | grep '^VERSION_ID=' )
  local _remote_dist=$( echo "$_remote" | grep '^ID=' )
  [[ "${_remote_version}" =~ ^VERSION[_]ID[=][\"]?([^\"]+) ]] && _remote_version="${BASH_REMATCH[1]}" || true
  [[ "${_remote_dist}" =~ ^ID[=][\"]?([^\"]+) ]] && _remote_dist="${BASH_REMATCH[1]}" || true

  [ -z "${_remote_version}" ] && error "remote distribution version could not be identified for sanity check" || true
  [ -z "${_remote_dist}" ] && error "remote distribution could not be identified for sanity check" || true

  [ "${_local_dist}" != "${_remote_dist}" -o "${_local_version}" != "${_remote_version}" ] && \
      warn "the local linux version '${_local_dist} ${_local_version}' should match the remote version '${_remote_dist} ${_remote_version}'" || true
  verbose 1 "  both versions match (${_remote_dist} ${_remote_version})"
}

do_sanity_checks

unset -f do_sanity_checks
