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


# Default port
[[ -z $PG_PORT ]] && PG_PORT=5432

declare -r DEFAULT_REPLICATION_SLOT_NAME="slave001"

for i in $@; do
  [[ "$i" =~ -h|help ]] && help && exit 0
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


modifyFile() {
  local v_file=$1
  local v_op=$2
  local value="$3"
  local replace="$4"
  replace="${replace//\"/\\x22}"
  replace="${replace//$'\t'/\\t}"
  value="${value//\"/\\x22}"
  value="${value//$'\t'/\\t}"
  local v_bkp_file=$v_file"."$(date +"%y%m%d%H%M%S")
  if [[ -z $v_file || -z $v_op ]]; then
    error "First two arguments are mandatory!"
    return 1
  fi
  if [[ $v_op == "bkp" ]]; then
     cp $v_file $v_bkp_file
  fi
  if [[ $v_op == "rep" ]]; then
      if [[ -z $value || -z $replace ]]; then
         error "Last two values required $3 and $4, value and its replacement!"
         return 1
      fi
      sed -i -e "s+$replace+$value+g" $v_file
      [[ $? -ne 0 ]] && error "Write operation failed!" && return 1
  fi
  if [[ $v_op == "add" ]]; then
      if [[ -z $value ]]; then
         error "Third argument $3 required!"
         return 1
      fi
      echo -e $value >> $v_file
      [[ $? -ne 0 ]] && error "Write operation failed!" && return 1
  fi
  if [[ $v_op == "rem" ]]; then
      if [[ -z $value ]]; then
         error "Third argument $3 required!"
         return 1
      fi
      sed -i "s+$value++g" $v_file
      [[ $? -ne 0 ]] && error "Write operation failed!" && return 1
  fi
  return 0
}

set_conf_param() {
local config="$1"
local param="$2"
local value="$3"
local repval="$(grep -Ei "(^|#| )$param *=" $config)"

if [[ ${#repval} -gt 0 ]]; then
  modifyFile $config rep "$param = $value\t\t# Modified by createslave.sh" "${repval//[$'\n']}"
else
  modifyFile $config add "$param = $value\t\t# Added by createslave.sh"
fi
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



if [[ -z $MASTER_HOST ]]; then
  error "MASTER_HOST parameter is not defined. Define it in parameters.conf file and re-execute."
  exit 1
fi

if [[ -z $REPLICATION_SLOT_NAME ]]; then
    info "REPLICATION_SLOT_NAME parameter was not specified in parameters.conf. Default name $DEFAULT_REPLICATION_SLOT_NAME will be used."
    REPLICATION_SLOT_NAME=$DEFAULT_REPLICATION_SLOT_NAME
fi

printheader "Setting parameters in postgresql.conf"
update_db_params

printheader "Stopping postgresql service"
sudo systemctl stop postgresql-${PGBASENV_ALIAS}

printheader "Clearing data directory $PGSQL_BASE/data"
rm -rf $PGSQL_BASE/data/*

printheader "Copying data directory from $MASTER_HOST to the $PGSQL_BASE/data"
$SU_PREFIX "export PGPASSWORD=\"$REPLICA_USER_PASSWORD\" && $PG_BIN_HOME/pg_basebackup --wal-method=stream -D $PGSQL_BASE/data -U replica -h $MASTER_HOST -p $PG_PORT -R"
if [[ ! $? -eq 0 ]]; then
   error "Duplicate from master site failed. Check output and PostgreSQL log files."
   exit 1
fi
echo "primary_slot_name = '${REPLICATION_SLOT_NAME//,*}'" >> $PGSQL_BASE/data/recovery.conf
echo "recovery_target_timeline = 'latest'" >> $PGSQL_BASE/data/recovery.conf


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

