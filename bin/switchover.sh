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
#  Created on 12.2020 by Aychin Gasimov
#
# Change log:
#   02.12.2020: Aychin: Initial version created



#
# Script to switchover in replication environment. First sync standby will be used to switchover,
# if no sync standbys configured then first async standby will be used.
#
# This script will use parameters from parameters.conf file. Parameters file must be in the same directory as the script itself.
#


help(){
echo "
  Script to perform switchover to the standby site. Script can be executed on master or standby site.

  If it will be executed on standby site, then script will identify master and execute on master site.
  
  If there is more than one standby configured then following rules will be used:
    1. If there is synchronous standby configured, then it will be used.
    2. Asynchronous standbys will be sorted by lag, the standby with smallest lag will be used.

  Available options:

    -f              Force to recreate new standby from scratch if old master will not be able to sync with new master.
                    Check the help of the reinstate.sh script.
  
  Example:
   $(basename $0) -f
   $(basename $0)
"
}


declare STANDBY_HOSTNAME
declare MASTER_HOSTNAME

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


for i in $@; do
  [[ "$i" =~ -h|help ]] && help && exit 0
done


FORCE=0
while getopts f option
do
 case "${option}"
 in
  f) FORCE=1;;
  h) help && exit 0;;
  ?) help && exit 1;;
 esac
done


if [[ $(id -u) -eq 0 ]]; then
  SU_PREFIX="su -l postgres -c"
else
  SU_PREFIX="eval"
fi

standby_db_host() {
 local standby standby_type

local sync_standby="$(psql -x -c "select client_addr, client_hostname, state, pg_wal_lsn_diff(replay_lsn,sent_lsn) diff from pg_stat_replication where sync_state='sync' limit 1" -t)"
if [[ -z $sync_standby ]]; then
  local async_standby="$(psql -x -c "select client_addr, client_hostname, state, pg_wal_lsn_diff(replay_lsn,sent_lsn) diff from pg_stat_replication where sync_state='async' order by diff asc limit 1" -t)"
  if [[ -z $async_standby ]]; then
    echo "INFO: No standby databases found."
    exit 0
  else
    standby="$async_standby"
    standby_type="ASYNC"
  fi
else
  standby="$sync_standby"
  standby_type="SYNC"
fi

local client_addr=$(echo "$standby" | grep client_addr | cut -d"|" -f2 | xargs)
local client_hostname=$(echo "$standby" | grep client_hostname | cut -d"|" -f2 | xargs)
local state=$(echo "$standby" | grep state | cut -d"|" -f2 | xargs)
local diff=$(echo "$standby" | grep diff | cut -d"|" -f2 | xargs)

[[ -z $client_hostname ]] && client_hostname=$(getent hosts $client_addr | head -1 | awk '{print $2}' | xargs)

echo "Standby type: $standby_type"
echo "Standby hostname: $client_hostname"
echo "Standby state: $state"
echo "Standby lag in bytes: $diff"

if [[ $diff -gt 0 && $state != "streaming" ]]; then
  echo "INFO: Standby has $diff bytes lag and its not in streaming mode. Switchover cannot be executed."
  exit 0
fi

STANDBY_HOSTNAME=$client_hostname

}



master_db_host() {
 local master

master="$(psql -x -c "select status, sender_host, conninfo from pg_stat_wal_receiver limit 1" -t)"
if [[ -z $master ]]; then
    echo "INFO: No master databases found."
    exit 0
fi

local status=$(echo "$master" | grep status | cut -d"|" -f2 | xargs)
local sender_host=$(echo "$master" | grep sender_host | cut -d"|" -f2 | xargs)
local conninfo=$(echo "$master" | grep conninfo | cut -d"|" -f2 | xargs)

echo "Master hostname: $sender_host"
echo "WAL receiver status: $status"

if [[ $status != "streaming" ]]; then
  echo "WARNING: WAL receiver is not in streaming mode."
  exit 0
fi

MASTER_HOSTNAME=$sender_host

}

is_connection_possible() {
  local host=$1
  ssh -o PasswordAuthentication=no -o StrictHostKeyChecking=no $host "echo -n"
  local RC=$?
  return $RC
}

# Script main part begins here. Everything in curly braces will be logged in logfile
{

echo "Command line arguments: $@" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE


printheader "Identifying muster and standby sites"

if [[ ! $TVD_PGSTATUS == "UP" ]]; then
   echo "ERROR: Instance on $(hostname) is in status DOWN. It must be UP to execute switchover."
   exit 1
fi

if [[ $TVD_PGIS_STANDBY == "YES" ]]; then
  # We are on standby side
  master_db_host
  is_connection_possible $MASTER_HOSTNAME
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Cannot establish passwordless connection to the master host $MASTER_HOSTNAME"
    exit 1
  fi

  echo "INFO: Executing switchover on master host $MASTER_HOSTNAME."
  ssh $MASTER_HOSTNAME ". .pgbasenv_profile; pgsetenv $PGBASENV_ALIAS; $PGOPERATE_BASE/bin/switchover.sh"

else
  # We are on master side
  standby_db_host
  is_connection_possible $STANDBY_HOSTNAME
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Cannot establish passwordless connection to the standby host $STANDBY_HOSTNAME"
    exit 1
  fi
  
  printheader "Stopping master."
  $PGOPERATE_BASE/bin/control.sh stop
  RC=$?
  [[ $RC -gt 0 ]] && exit 1

  printheader "Promoting standby to new master."
  ssh $STANDBY_HOSTNAME ". .pgbasenv_profile; pgsetenv $PGBASENV_ALIAS; $PGOPERATE_BASE/bin/promote.sh"
  RC=$?
  [[ $RC -gt 0 ]] && exit 1

  printheader "Preparing new master to master role"
  ssh $STANDBY_HOSTNAME ". .pgbasenv_profile; pgsetenv $PGBASENV_ALIAS; $PGOPERATE_BASE/bin/prepare_master.sh"
  RC=$?
  [[ $RC -gt 0 ]] && exit 1
  
  printheader "Starting old standby as new master."
  if [[ $FORCE -eq 1 ]]; then
    $PGOPERATE_BASE/bin/reinstate.sh -f -m $STANDBY_HOSTNAME
    RC=$?
  else
    $PGOPERATE_BASE/bin/reinstate.sh -m $STANDBY_HOSTNAME
    RC=$?
  fi

  if [[ $RC -eq 0 ]]; then
     echo "Switchover successful."
  else
     echo "Switchover unsuccessful."
  fi 

fi



echo -e "\nLogfile of this execution on host $(hostname): $LOGFILE\n"
exit 0

} 2>&1 | tee -a $LOGFILE

echo
if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
     echo "Successful execution on $(hostname)."
else
     echo "Unsuccessful execution on $(hostname).."
fi 
echo

exit ${PIPESTATUS[0]}


