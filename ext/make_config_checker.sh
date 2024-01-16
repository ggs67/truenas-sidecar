#!/usr/bin/env bash

#set -x

DIR=$( dirname "$0" )

CONFIG_DIR="${DIR}/../conf.d"
CONFIG="${CONFIG_DIR}/config.sh"

CHECKER_DB="${DIR}/config_checker.dat"
CHECKER_DB_BAK="${CHECKER_DB}.bak"

CHECKER="${DIR}/config_checker.sh"

[ ! -f "${CHECKER_DB}" ] && touch "${CHECKER_DB}"
 
# Backup old database
mv -f "${CHECKER_DB}" "${CHECKER_DB_BAK}"
touch "${CHECKER_DB}"

echo "updating check database ${CHECKER_DB}"
while read VARDEF
do
  [[ ! "${VARDEF}" =~ ^[[:space:]]*([a-zA-Z0-9_]+)[=](.*)$ ]] && echo "BUG: unexpected VARDEF: $VARDEF" && exit 1
  VAR="${BASH_REMATCH[1]}"
  echo "  $VAR"
  DEF="${BASH_REMATCH[2]}"
  CHECK=""
  [[ "${DEF}" =~ (.*)[#][-][\>][[:space:]]*(.+)$ ]] && CHECK="${BASH_REMATCH[2]}" && DEF="${BASH_REMATCH[1]}"
  if [ -z "${CHECK}" ]
  then
    DBCHECK=$( grep "^${VAR}[^a-zA-Z0-9_]" "${CHECKER_DB_BAK}" )
    if [ -n "${DBCHECK}" ]
    then
      [[ "${DBCHECK}" =~ [#][-][\>][[:space:]]*(.+)$ ]] && CHECK=${BASH_REMATCH[1]}
    fi
  fi
  echo "${VAR}=${DEF} #-> ${CHECK}" >> "${CHECKER_DB}"
done < <( grep -E '^[[:space:]]*[a-zA-Z0-9_]+[=]' "${CONFIG}" | sort --key=1 -t '=' -u )

echo "building checker..."

checker()
{
  echo "$@" >> "${CHECKER}"
}

echo "#!/usr/bin/env bash" > "${CHECKER}"
checker ""
checker 'DIR=$( dirname "$0" )'
checker 'source ${DIR}/../gglib/include checks'
checker ""
checker 'source ${DIR}/../conf.d/config.sh'
checker ""

while read CHK
do
  if [[ "${CHK}" =~ [[:space:]]*([^=]+)[=].*[#][-][\>][[:space:]]*(.+)$ ]]
  then
    var="${BASH_REMATCH[1]}"
    CHK="${BASH_REMATCH[2]}"
    if fgrep -q '{}' >/dev/null <<<$CHK
    then
      CHK=$( echo "${CHK}" | sed -E "s/[{][}]/${var}/" )
    else
      CHK="${CHK} ${var}"
    fi
    checker "${CHK}"
  fi  
done < <( cat "${CHECKER_DB}" | grep '#->' )

chmod 755 "${CHECKER}"
