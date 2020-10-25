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

[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PGOPERATE_BASE/lib/shared.lib


# Define log file
prepare_logdir
declare -r LOGFILE="$PGSQL_BASE/log/tools/$(basename $0)_$(date +"%Y%m%d_%H%M%S").log"


# Default port
[[ -z $PGPORT ]] && echo "ERROR: PGPORT is undefined. Set environment for the cluster before execution." && exit 1
PG_PORT=$PGPORT



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


get_master_connectinfo(){
  local ver=$1
  if [[ $ver -ge 12 ]]; then
    local tmp="$(grep primary_conninfo $PGSQL_BASE/etc/postgresql.conf | grep -oE "'.+'")"
  else
    local tmp="$(grep primary_conninfo $PGSQL_BASE/data/recovery.conf | grep -oE "'.+'")"
  fi
  tmp="${tmp//\'/}"
  tmp="${tmp//\!/\\!}"
  echo "$tmp replication=yes connect_timeout=5"
}



# Script main part begins here. Everything in curly braces will be logged in logfile
{

echo "Command line arguments: $@" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE



if [[ $(id -u) -eq 0 ]]; then
  SU_PREFIX="su -l postgres -c"
else
  SU_PREFIX="eval"
fi

if [[ $TVD_PGVERSION -ge 12 ]]; then
  [[ -f $PGSQL_BASE/data/standby.signal ]] && standby_mode="on" || standby_mode="off"
else
  standby_mode=$(grep standby_mode $PGSQL_BASE/data/recovery.conf | cut -d"=" -f2 | xargs)
fi
shopt -s nocasematch
if [[ $standby_mode == "on" ]]; then
  IS_STANDBY="STANDBY"
else
  IS_STANDBY="NOTSTANDBY"
fi
shopt -u nocasematch



if [[ $IS_STANDBY == "NOTSTANDBY" ]]; then
  printheader "Starting the cluster"
  echo "INFO: Cluster was not in standby mode."
  echo "INFO: Staring the Cluster."
  start_cluster
  exit $?

elif [[ $IS_STANDBY == "STANDBY" ]]; then
  master_conninfo="$(get_master_connectinfo $TVD_PGVERSION)"
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
  $PGOPERATE_BASE/bin/prepare_master.sh

else 
  exit 1

fi

echo -e "\nLogfile of this execution: $LOGFILE\n"
exit 0

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}
