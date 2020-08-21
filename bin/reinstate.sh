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
# Script to start old primary as new standby server.
#   Script will try to start as standby in next oder:
#     1. Start old primary as new stanbdy
#     2. If it fails to sync with master, then sync with pg_rewind
#     3. If it again fails then script will recreate standby from master if -f option was specified
#
# This script will use parameters from parameters.conf file. Parameters file must be in the same directory as the script itself.
#


help(){
echo "
  Script to start old master as new standby.
  
  Script will try:
    1. Start old primary as new standby
    2. If it fails to sync, try pg_rewind and start again
  If -f option specified then:
    3. If 1 and 2 fails then recreate standby from master

  Available options:

    -m <hostname>   Master host. If not specified, master host from $PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf will be used.
    -f              Force to recreate standby from master if everything else fails.
    -r              Execute only pg_rewind to synchronize primary and standby.
    -d              Recreate standby from master.

  Example:
   $0 -f
   $0 -f -h myhost1
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


standby_mode=$(grep standby_mode $PGSQL_BASE/data/recovery.conf | cut -d"=" -f2 | xargs)
shopt -s nocasematch
if [[ $standby_mode == "on" ]]; then
  IS_STANDBY="STANDBY"
else
  IS_STANDBY="NOTSTANDBY"
fi
shopt -u nocasematch

for i in $@; do
  [[ "$i" =~ -h|help ]] && help && exit 0
done


FORCE=0
REWIND=0
DUPLICATE=0
while getopts m:frdh option
do
 case "${option}"
 in
  m) MASTER_HOST=${OPTARG};;
  f) FORCE=1;;
  r) REWIND=1;;
  d) DUPLICATE=1;;
  h) help && exit 0;;
  ?) help && exit 1;;
 esac
done


if [[ $(id -u) -eq 0 ]]; then
  SU_PREFIX="su -l postgres -c"
else
  SU_PREFIX="eval"
fi


check_master(){
  local recstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -At -c "SELECT pg_is_in_recovery()" 2>&1)
  if [[ $recstatus == "f" ]]; then
     echo "WARNING: This database cluster running in non-recovery mode. Stop it first to convert to standby."
     exit 1
  fi
}

create_recovery_file(){
   echo "
standby_mode = 'on'
primary_conninfo = 'user=replica password=''$REPLICA_USER_PASSWORD'' host=$MASTER_HOST port=$PG_PORT'
primary_slot_name = '${REPLICATION_SLOT_NAME//,*}'
recovery_target_timeline = 'latest'
" > $PGSQL_BASE/data/recovery.conf
chown postgres:postgres $PGSQL_BASE/data/recovery.conf
}

do_rewind(){

  # if [[ ! -z "$PG_SUPERUSER_PWDFILE" && -f "$SCRIPTDIR/$PG_SUPERUSER_PWDFILE" ]]; then
  #   chown postgres:postgres $SCRIPTDIR/$PG_SUPERUSER_PWDFILE
  #   chmod 0400 $SCRIPTDIR/$PG_SUPERUSER_PWDFILE
  #   PG_SUPERUSER_PWD="$(head -1 $SCRIPTDIR/$PG_SUPERUSER_PWDFILE | xargs)"
  # else
  #   error "Password file with superuser $PG_SUPERUSER password is required for pg_rewind.
  #   Create the password file in the same directory as $0 script and set PG_SUPERUSER_PWDFILE parameter in parameters.conf."
  #   exit 1
  # fi
   sudo systemctl stop postgresql-${PGBASENV_ALIAS}
   $SU_PREFIX "$PG_BIN_HOME/pg_rewind --target-pgdata=$PGSQL_BASE/data --source-server=\"host=$MASTER_HOST port=$PG_PORT user=$PG_SUPERUSER dbname=postgres connect_timeout=5\" -P"
   create_recovery_file
   sudo systemctl start postgresql-${PGBASENV_ALIAS}
}

do_duplicate(){
  $SCRIPTDIR/createslave.sh
}


check_master


if [[ $REWIND -eq 1 ]]; then
  printheader "Executed with -r option. Will try pg_rewind."
  do_rewind
  sleep 5
  repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$MASTER_HOST%'")
  if [[ $repstatus == "streaming" ]]; then
        echo "INFO: WAL receiver in streaming mode."
        exit 0
  else
        echo "CRITICAL: WAL receiver in not streaming."
	echo "INFO: Execute with -d option to recreate standby from master."
        exit 1
  fi

fi	


if [[ $DUPLICATE -eq 1 ]]; then
  printheader "Executed with -d option. Will try to recreate standby from master site."
  do_duplicate
  sleep 5
  repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$MASTER_HOST%'")
  if [[ $repstatus == "streaming" ]]; then
        echo "INFO: WAL receiver in streaming mode."
        exit 0
  else
        echo "CRITICAL: WAL receiver in not streaming. Manual intervention required"
        exit 1
  fi

fi


if [[ $IS_STANDBY == "STANDBY" ]]; then
  printheader "Trying to start standby"
  echo "INFO: Cluster was in standby mode."
  echo "INFO: Staring the Cluster."
  sudo systemctl start postgresql-${PGBASENV_ALIAS}
  exit $?

elif [[ $IS_STANDBY == "NOTSTANDBY" ]]; then
  printheader "Starting as the standby cluster."
  create_recovery_file
  sudo systemctl start postgresql-${PGBASENV_ALIAS}
  [[ $? -gt 0 ]] && echo "CRITICAL: Manual intervention required." && exit 1
  repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$MASTER_HOST%'")
  if [[ $repstatus == "streaming" ]]; then
     echo "INFO: WAL receiver in streaming mode."
	 echo "INFO: Reinstation complete."
     exit 0
  else
     echo "WARNING: WAL receiver is not streaming. Will try to synchronize Master and Standby with pg_rewind."
	 printheader "Executing pg_rewind to synchronise both sides"
     do_rewind
     sleep 5
     repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$MASTER_HOST%'")
     if [[ $repstatus == "streaming" ]]; then
        echo "INFO: WAL receiver in streaming mode."
		echo "INFO: Reinstation complete."
        exit 0
     elif [[ $FORCE -eq 1 ]]; then
        echo "WARNING: Force option -f specified!"
        echo "WARNING: WAL receiver is steel not streaming. Will try to recreate Standby from active Master."
		printheader "Recreating standby from master"
        do_duplicate
	sleep 5
        repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$MASTER_HOST%'")
        if [[ $repstatus == "streaming" ]]; then
           echo "INFO: WAL receiver in streaming mode."
		   echo "INFO: Reinstation complete."
           exit 0
        else
           echo "WARNING: WAL receiver is steel not streaming. Manual action required."
           exit 1
        fi

     else
         echo "WARNING: WAL receiver is steel not streaming. Manual action required."
         exit 1
     fi

     echo "CRITICAL: WAL receiver is not streaming."
     echo "INFO: Standby is not applying. Check logfiles."
     exit 1
  fi

else
  exit 1

fi

exit 0


