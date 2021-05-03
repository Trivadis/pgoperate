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
#
# Creates new PostgreSQL cluster.
#


help() {

echo "

Creates new PostgreSQL cluster and initializes Base directory.

Arguments:
              -a|--alias <alias_name> -  Alias name of the cluster to be created.

 parameters_<alias_name>.conf file must be created and prepared in \$PGOPERATE_BASE/etc before executing this script.

"

}




declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"
declare -r DEFAULT_REPLICATION_SLOT_NAME="slave001"


printheader() {
  GRE='\033[0;32m'
  NC='\033[0m'

  if [[ $SILENT -eq 0 ]]; then
    echo -e "$GRE"
    echo -e "----------------------------------------------------------------------------"
    echo -e "[   $1"
    echo -e "----------------------------------------------------------------------------"
    echo -e "$NC"
  fi

}



adding_entry_in_pgtab() {
  echo "$PGSQL_BASE/data;$(cat $PGSQL_BASE/data/PG_VERSION);$TVD_PGHOME;$PG_PORT;$PG_CLUSTER_ALIAS" >> $PGBASENV_BASE/etc/pgclustertab
}

minimize_conf_file() {
  if [[ "$MINIMIZE_CONF_FILE" =~ yes|YES ]]; then
    sed -i '/^[ |\t]*#/d' $1
    sed -i '/^$/d' $1
  fi
}


in_cluster_actions() {
  
  if [[ ! -z "$PG_SUPERUSER_PWD" ]]; then
    $PG_BIN_HOME/psql -p $PG_PORT -U $PG_SUPERUSER -d postgres -c "alter user $PG_SUPERUSER password '$PG_SUPERUSER_PWD';" -t
  fi

  if [[ ! -z $REPLICA_USER_PASSWORD ]]; then
    echo "Cluster will be prepared for replication."
    $PG_BIN_HOME/psql -p $PG_PORT -U $PG_SUPERUSER -d postgres -c "CREATE USER replica WITH REPLICATION PASSWORD '$REPLICA_USER_PASSWORD';" -t
  fi

  if [[ ! -z $PG_DATABASE ]]; then
    echo "Creating default database, role and schema $PG_DATABASE."
    $PG_BIN_HOME/psql -p $PG_PORT -U $PG_SUPERUSER -d postgres -c "CREATE DATABASE $PG_DATABASE ENCODING=$PG_ENCODING;" -t
    $PG_BIN_HOME/psql -p $PG_PORT -U $PG_SUPERUSER -d $PG_DATABASE -c "CREATE SCHEMA $PG_DATABASE;" -t

    $PG_BIN_HOME/psql -p $PG_PORT -U $PG_SUPERUSER -d postgres -c "CREATE ROLE $PG_DATABASE;"
    $PG_BIN_HOME/psql -p $PG_PORT -U $PG_SUPERUSER -d $PG_DATABASE -c "ALTER SCHEMA $PG_DATABASE OWNER TO $PG_DATABASE;"
  fi
}



manual_start_stop() {
  eval "$PG_BIN_HOME/pg_ctl start -D $PGSQL_BASE/data -l $PGSQL_BASE/log/server.log -o \"--config_file=$PGSQL_BASE/etc/postgresql.conf\" $([[ $SILENT -eq 1 ]] && echo \">/dev/null 2>\&1\")"
  check_server
  [[ $? -gt 0 ]] && local res=1 || local res=0
  eval "$PG_BIN_HOME/pg_ctl stop -D $PGSQL_BASE/data -s --mode=smart $([[ $SILENT -eq 1 ]] && echo \">/dev/null 2>\&1\")"
  return $res
}



### MAIN ######################################################################

ARGS="$@"

SILENT=0
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -a|--alias)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        PG_CLUSTER_ALIAS=$2
        shift 2
      else
        echo "ERROR: Alias name is missing" >&2
        help
        exit 1
      fi
      ;;
    --silent)
        SILENT=1
        shift
      ;;
    help) help
          exit 0
          ;;
    -*|--*=) # unsupported flags
      echo "ERROR: Unsupported flag $1" >&2
      help
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done


[[ ! -f $HOME/.pgbasenv_profile ]] && echo "ERROR: Please check if pgBasEnv installed for this user." && exit 1
[[ -z $PG_CLUSTER_ALIAS ]] && echo "ERROR: Provide alias name for the cluster to be created." && exit 1


source $HOME/.pgbasenv_profile


PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PG_CLUSTER_ALIAS}.conf

[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PGOPERATE_BASE/lib/shared.lib
source $PARAMETERS_FILE

_SAVE_=$PGSQL_BASE


set_param() {
local param="$1"
local value="$2"
local repval="$(grep -Ei "(^|#| )$param *=" $PARAMETERS_FILE)"

if [[ ${#repval} -gt 0 ]]; then
  modifyFile $PARAMETERS_FILE rep "$param=$value" "${repval//[$'\n']}"
else
  modifyFile $PARAMETERS_FILE add "$param=$value"
fi
}


# Define log file
mkdir -p $PGOPERATE_BASE/log
declare -r LOGFILE="$PGOPERATE_BASE/log/$(basename $0)_$(date +"%Y%m%d_%H%M%S").log"


# Everything in curly braces will be logged in logfile
{

# Lock the pgclustertab and parameters file
exec 7<>$PGBASENV_BASE/etc/pgclustertab
flock -x 7

echo "Command line arguments: ${ARGS}" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE


[[ -z $PG_PORT ]] && echo "ERROR: Please set PG_PORT parameter in $PARAMETERS_FILE file." && exit 1


if [[ -z $TVD_PGHOME_ALIAS ]]; then
  TVD_PGHOME_ALIAS=$(grep -vE "^#" $PGBASENV_BASE/etc/pghometab | head -1 | cut -d";" -f4)
  if [[ -z $TVD_PGHOME_ALIAS ]]; then
  	echo "ERROR: No home in $PGBASENV_BASE/etc/pghometab file found! Check your installation."
  	exit 1
  else
    echo "INFO: Parameter TVD_PGHOME_ALIAS is not set in parameters file. The first home alias will be used: $TVD_PGHOME_ALIAS"
  fi
fi

pgsetenv $TVD_PGHOME_ALIAS
export PGSQL_BASE=$_SAVE_

PG_BIN_HOME=$TVD_PGHOME/bin

[[ -z $PGSQL_BASE ]] && echo "ERROR: PGSQL_BASE must be set." && exit 1

printheader "Creating directories in $PGSQL_BASE"
if [[ -d $PGSQL_BASE ]]; then
   [[ "$(ls -A $PGSQL_BASE)" ]] && echo "ERROR: The directory $PGSQL_BASE is not empty." && exit 1
fi
create_dirs

printheader "Initialize PostgreSQL CLuster"
set_param "INTENDED_STATE" "DOWN"
initialize_db

printheader "Moving config files to $PGSQL_BASE/etc"
move_configs

printheader "Copy certificates"
copy_certs

printheader "Updating pg_hba.conf"
update_pg_hba

printheader "Updating parameters in postgresql.conf"
export PGPORT=1
export SET_CONF_PARAM_IN_CLUSTER=NO
update_db_params
minimize_conf_file $PGSQL_BASE/etc/postgresql.conf

printheader "Manually testing new cluster"
if [[ $SILENT -eq 1 ]]; then
  manual_start_stop >/dev/null
  RC=$?
else
  manual_start_stop
  RC=$?
fi
if [[ $RC -gt 0 ]]; then
  error "Manual test failed, cluster fails to start."
  exit 1
fi

printheader "Generating $PGSQL_BASE/scripts/start.sh."
generate_manual_start_script

printheader "Adding entry into pgclustertab file."
adding_entry_in_pgtab

if [[ ! -z $PG_SUPERUSER_PWD ]]; then
printheader "Adding entry into ~/.pgpass for superuser."
modify_password_file "$PG_PORT" "$PG_SUPERUSER" "$PG_SUPERUSER_PWD" 
fi

printheader "Starting cluster with pgoperated daemon process."
# Release lock, because pgsetenv will require this lock.
exec 7>&-
pgsetenv $PG_CLUSTER_ALIAS
if [[ $SILENT -eq 1 ]]; then
  $PGOPERATE_BASE/bin/control.sh start >/dev/null
  RC=$?
else
  $PGOPERATE_BASE/bin/control.sh start
  RC=$?
fi
[[ $RC -gt 0 ]] && exit 1

printheader "Executing in database actions."
if [[ $SILENT -eq 1 ]]; then
  in_cluster_actions >/dev/null
else
  in_cluster_actions
fi


if [[ $SILENT -eq 0 ]]; then
  echo -e
  echo "Cluster created and ready to use."
  echo -e
  echo "Execute now pgsetenv in current shell to source new database alias."

  echo -e "\nLogfile of this execution: $LOGFILE\n"
fi

exit 0

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}
