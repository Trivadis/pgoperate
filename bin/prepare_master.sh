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
# Script to create replica user and configure PostgreSQL as master site.
#
# Script uses PGSQL_BASE and other variables from parameters.conf file, which is in the script directory.


help() {
echo "
 Script to create replica user and prepare PostgreSQL for master role.

 WARNING! Cluster will be restarted if track_commit_timestamp is not \"on\".

 Script accepts no arguments.

"
}

declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"

[[ -z $PGBASENV_ALIAS ]] && error "Set the alias for the current cluster first." && exit 1
echo -e "\nCurrent cluster: ${PGBASENV_ALIAS}"

[[ -z $PGBASENV_ALIAS ]] && error "PG_BIN_HOME is not defined. Set the environment for cluster home."
PG_BIN_HOME=$TVD_PGHOME/bin


PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf
[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PARAMETERS_FILE
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





reload_conf() {
  local output=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "SELECT pg_reload_conf();" -t | xargs)
  if [[ "${output,,}" == "t" ]]; then
    return 0
  else
    return 1
  fi
}


stop_pg() {
  $PG_BIN_HOME/pg_ctl stop -D $PGSQL_BASE/data -s -m fast
  return $?
}


start_pg() {
  $PG_BIN_HOME/pg_ctl start -D $PGSQL_BASE/data -l $PGSQL_BASE/log/server.log -s -o "-p ${PG_PORT} --config_file=$PGSQL_BASE/etc/postgresql.conf" -w -t 300
  return $?
}


update_db_params() {
modifyFile "$PGSQL_BASE/etc/postgresql.conf" bkp
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" wal_level "replica"
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_wal_senders "10"
# set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_wal_size "1GB"
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_replication_slots "10"
set_conf_param "$PGSQL_BASE/etc/postgresql.conf" track_commit_timestamp "on"
}

update_pg_hba() {
grep -q "#replication#" $PGSQL_BASE/etc/pg_hba.conf
[[ $? -gt 0 ]] && echo -e "# For replication. Connect from remote hosts. #replication#\nhost    replication     replica      0.0.0.0/0      scram-sha-256" >> $PGSQL_BASE/etc/pg_hba.conf
}



####### MAIN ###################################################

if [[ ${#@} -gt 0 ]]; then
 for arg in "$@"; do
   pattern=" +${arg%%=*} +"
   [[ ! " -h help " =~ $pattern ]] && error "Bad argument $arg" && help && exit 1
 done
fi


for arg in "$@"
do
 [[ "$arg" =~ -h|help ]] && help && exit 0
done



# Script main part begins here. Everything in curly braces will be logged in logfile
{

echo "Command line arguments: $@" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE



if [[ -z $REPLICATION_SLOT_NAME ]]; then
    info "REPLICATION_SLOT_NAME parameter was not specified in parameters.conf. Default name $DEFAULT_REPLICATION_SLOT_NAME will be used."
    REPLICATION_SLOT_NAME=$DEFAULT_REPLICATION_SLOT_NAME
fi

if [[ -z $REPLICA_USER_PASSWORD ]]; then
   error "REPLICA_USER_PASSWORD is not defined. Define it in parameters.conf file before execution."
   exit 1
fi

printheader "Setting parameters in postgresql.conf"
update_db_params

printheader "Create replication slot(s) $REPLICATION_SLOT_NAME"
for rslot in $(echo $REPLICATION_SLOT_NAME | sed "s/,/ /g")
do
  output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "SELECT * FROM pg_create_physical_replication_slot('$rslot');" -t 2>&1)"
  echo "$output" | grep -q "already exists"
  [[ $? -gt 0 ]] && echo "$output"
done

printheader "Create user replica for replication"
output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "CREATE USER replica WITH REPLICATION PASSWORD '$REPLICA_USER_PASSWORD';" -t 2>&1)"
echo "$output" | grep -q "already exists"
[[ $? -gt 0 ]] && echo "$output"

printheader "Updating pg_hba.conf file"
update_pg_hba


track_commit_enabled=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "select setting from pg_settings where name='track_commit_timestamp'" -t | xargs)
if [[ "$track_commit_enabled" == "on" ]]; then
  printheader "Reloading postgresql"
  reload_conf
else
  printheader "Restarting postgresql"
  sudo systemctl stop postgresql-${PGBASENV_ALIAS}
  sudo systemctl start postgresql-${PGBASENV_ALIAS}
fi

echo -e "\nLogfile of this execution: $LOGFILE\n"
exit 0

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}

