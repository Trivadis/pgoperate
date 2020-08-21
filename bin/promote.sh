#!/usr/bin/env bash


# Copyright 2020 Trivadis AG <info@trivadis.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#  Created on 07.2019 by Aychin Gasimov
#
# Change log:
#   06.07.2020: Aychin: Initial version created



#
# Script to promote standby to primary.
# 
# This script will use parameters from parameters.conf file. Parameters file must be in the same directory as the script itself.
#


help(){
echo "
  Script to promote standby PostgreSQL cluster to Primary.

  No arguments required.

  If cluster is not standby, then just try to start it.

"
}


declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"
[[ -z $PGBASENV_ALIAS ]] && error "Set the alias for the current cluster first." && exit 1
echo -e "\nCurrent cluster: ${PGBASENV_ALIAS}"

[[ -z $PGBASENV_ALIAS ]] && error "PG_BIN_HOME is not defined. Set the environment for cluster home."
PG_BIN_HOME=$TVD_PGHOME/bin


PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf
[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
source $PARAMETERS_FILE

# Default port
[[ -z $PG_PORT ]] && PG_PORT=5432


GRE='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

printheader() {
  echo -e "$GRE"
  echo -e "> $1"
  echo -e "$NC"

}

error() {
  echo -e "$RED"
  echo -e "ERROR: $1"
  echo -e "$NC"
}

info() {
  echo -e "INFO: $1"
}



while (( "$#" )); do
  case "$1" in
    help) help
          exit 0
          ;;
    -*|--*=) # unsupported flags
      echo "ERROR: Unsupported flag $1" >&2
      help
      exit 1
      ;;
    *) echo "ERROR: Illegal argument."
       help
       exit 1
      ;;
  esac
done




if [[ $(id -u) -eq 0 ]]; then
  SU_PREFIX="su -l postgres -c"
else
  SU_PREFIX="eval"
fi


standby_mode=$(grep standby_mode $PGSQL_BASE/data/recovery.conf | cut -d"=" -f2 | xargs)
shopt -s nocasematch
if [[ $standby_mode == "on" ]]; then
  IS_STANDBY="STANDBY"
else
  IS_STANDBY="NOTSTANDBY"
fi
shopt -u nocasematch



get_master_connectinfo(){
  local tmp="$(grep primary_conninfo $PGSQL_BASE/data/recovery.conf | grep -oE "'.+'")"
  tmp="${tmp//\'/}"
  tmp="${tmp//\!/\\!}"
  echo "$tmp replication=yes connect_timeout=5"
}



if [[ $IS_STANDBY == "NOTSTANDBY" ]]; then
  printheader "Starting the cluster"
  echo "INFO: Cluster was not in standby mode."
  echo "INFO: Staring the Cluster."
  sudo systemctl start postgresql-${PGBASENV_ALIAS}
  exit $?

elif [[ $IS_STANDBY == "STANDBY" ]]; then
  master_conninfo="$(get_master_connectinfo)"
  connect=$($PG_BIN_HOME/psql "$master_conninfo" -c "\conninfo" 2>&1)
  if [[ $? -gt 0 ]]; then
    echo "INFO: Master unreachable."
  else
    echo "INFO: Master reachable."
    echo "CRITICAL: Master server is still reachable. Stop master before promoting standby."
    exit 1
  fi
  printheader "Promoting to master."
  $SU_PREFIX "$PG_BIN_HOME/pg_ctl promote"
  [[ $? -gt 0 ]] && exit 1
  printheader "Preparing as master."
  $PGOPERATE_BASE/bin/preparemaster.sh

else 
  exit 1

fi

exit 0


