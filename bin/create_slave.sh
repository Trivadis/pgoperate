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


help() {
  echo "

 Script to create standby PostgreSQL cluster.

 Available options:

 --force    \$PGDATA will be emptied by the script without warning.

 Script uses PGSQL_BASE and other variables from $PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf file.

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
[[ -z $PG_PORT ]] && PG_PORT=5432

declare -r DEFAULT_REPLICATION_SLOT_NAME="slave001"

FORCE=0
for i in $@; do
  [[ "$i" =~ -h|help ]] && help && exit 0
  [[ "$i" =~ -f|--force ]] && FORCE=1
done



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


update_db_params() {
modifyFile "$PGSQL_BASE/etc/postgresql.conf" bkp
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" wal_level "replica"
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_wal_senders "10"
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_wal_size "1GB"
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_replication_slots "10"
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" hot_standby "on"
}

update_pg_hba() {
grep -q "#replication#" $PGSQL_BASE/etc/pg_hba.conf
[[ $? -gt 0 ]] && echo -e "# For replication. Connect from remote hosts. #replication#\nhost    replication     replica      0.0.0.0/0      scram-sha-256" >> $PGSQL_BASE/etc/pg_hba.conf
}



if [[ $(id -u) -eq 0 ]]; then
  SU_PREFIX="su -l postgres -c"
else
  SU_PREFIX="eval"
fi


# Script main part begins here. Everything in curly braces will be logged in logfile
{

echo "Command line arguments: $@" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE



if [[ -z $MASTER_HOST ]]; then
  error "MASTER_HOST parameter is not defined. Define it in parameters.conf file and re-execute."
  exit 1
fi

if [[ -z $REPLICATION_SLOT_NAME ]]; then
    info "REPLICATION_SLOT_NAME parameter was not specified in parameters.conf. Default name $DEFAULT_REPLICATION_SLOT_NAME will be used."
    REPLICATION_SLOT_NAME=$DEFAULT_REPLICATION_SLOT_NAME
fi


if [[ $FORCE -eq 0 ]]; then
  data_dir=$(ls $PGSQL_BASE/data/)
  [[ ! -z $data_dir ]] && echo "ERROR: \$PGDATA directory $PGDATA is not empty. Remove all files from it or use --force option." && exit 1
fi

printheader "Setting parameters in postgresql.conf"
update_db_params

printheader "Stopping postgresql service with systemctl"
sudo systemctl stop postgresql-${PGBASENV_ALIAS}

if [[ $FORCE -eq 1 ]]; then
  printheader "Force option specified. Clearing data directory $PGSQL_BASE/data"
  rm -rf $PGSQL_BASE/data/*
fi

printheader "Copying data directory from $MASTER_HOST to the $PGSQL_BASE/data"
$SU_PREFIX "export PGPASSWORD=\"$REPLICA_USER_PASSWORD\" && $PG_BIN_HOME/pg_basebackup --wal-method=stream -D $PGSQL_BASE/data -U replica -h $MASTER_HOST -p $PG_PORT -R"
if [[ ! $? -eq 0 ]]; then
   error "Duplicate from master site failed. Check output and PostgreSQL log files."
   exit 1
fi

if [[ $TVD_PGVERSION -ge 12 ]]; then
  conninfo=$(grep primary_conninfo $PGSQL_BASE/data/postgresql.auto.conf | grep -oE "'.+'" | tail -1)
  [[ ! -z $BACKUP_LOCATION ]] && set_conf_param "$PGSQL_BASE/etc/postgresql.conf" restore_command "'cp $BACKUP_LOCATION/*/wal/%f "%p" || cp $PGSQL_BASE/arch/%f "%p"'"
  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" primary_conninfo "$conninfo"
  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" primary_slot_name "'${REPLICATION_SLOT_NAME//,*}'"
  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" recovery_target_timeline "'latest'"
  touch $PGSQL_BASE/data/standby.signal
else
  [[ ! -z $BACKUP_LOCATION ]] && echo "restore_command = 'cp $BACKUP_LOCATION/*/wal/%f "%p" || cp $PGSQL_BASE/arch/%f "%p"'" > $PGSQL_BASE/data/recovery.conf
  echo "primary_slot_name = '${REPLICATION_SLOT_NAME//,*}'" >> $PGSQL_BASE/data/recovery.conf
  echo "recovery_target_timeline = 'latest'" >> $PGSQL_BASE/data/recovery.conf
fi

printheader "Updating pg_hba.conf file"
update_pg_hba

printheader "Starting slave postgresql"
sudo systemctl start postgresql-${PGBASENV_ALIAS}


printheader "Check the replication status"
sleep 5
replication_status=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "select status from pg_stat_wal_receiver;" -t | xargs)
if [[ "$replication_status" == "streaming" ]]; then
   info "Replication status is 'streaming'. Successful."
else
   error "Replication status is not streaming. Something wrong. Check server log files."
   info "Check replication slot name in recovery.conf and on the master site. Replication slot used was ${REPLICATION_SLOT_NAME//,*}."
   exit 1
fi

exit 0

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}

