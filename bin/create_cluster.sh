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

  echo -e "$GRE"
  echo -e "----------------------------------------------------------------------------"
  echo -e "[   $1"
  echo -e "----------------------------------------------------------------------------"
  echo -e "$NC"

}


create_root_sh() {
  echo "#!/usr/bin/env bash

source $PGOPERATE_BASE/lib/shared.lib
source $PARAMETERS_FILE
PG_BIN_HOME=$PG_BIN_HOME

add_sudoers_rules
create_service_file $PG_SERVICE_FILE
start_pg_service $PG_SERVICE_FILE
in_cluster_actions

" > $PGSQL_BASE/scripts/root.sh 
chmod 700 $PGSQL_BASE/scripts/root.sh 
}



adding_entry_in_pgtab() {
  echo "$PGSQL_BASE/data;$(cat $PGSQL_BASE/data/PG_VERSION);$TVD_PGHOME;$PG_PORT;$PG_CLUSTER_ALIAS" >> $PGBASENV_BASE/etc/pgclustertab
}





### MAIN ######################################################################

ARGS="$@"

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
source $PARAMETERS_FILE
source $PGOPERATE_BASE/lib/shared.lib


# Define log file
mkdir -p $PGOPERATE_BASE/log
declare -r LOGFILE="$PGOPERATE_BASE/log/$(basename $0)_$(date +"%Y%m%d_%H%M%S").log"

# Everything in curly braces will be logged in logfile
{

echo "Command line arguments: ${ARGS}" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE



[[ -z $PG_PORT ]] && echo "ERROR: Please set PG_PORT parameter in $PARAMETERS_FILE file." && exit 1


if [[ -z $TVD_PGHOME_ALIAS ]]; then
  TVD_PGHOME_ALIAS=$(grep -vE "^#" $TVDPGENV_BASE/etc/pghometab | head -1 | cut -d";" -f4)
  if [[ -z $TVD_PGHOME_ALIAS ]]; then
  	echo "ERROR: No home in $TVDPGENV_BASE/etc/pghometab file found! Check your installation."
  	exit 1
  else
    echo "INFO: Parameter TVD_PGHOME_ALIAS is not set in parameters file. The first home alias will be used: $TVD_PGHOME_ALIAS"
  fi
fi

pgsetenv $TVD_PGHOME_ALIAS



PG_SERVICE_FILE="postgresql-${PG_CLUSTER_ALIAS}.service"
PG_BIN_HOME=$TVD_PGHOME/bin


printheader "Creating directories in $PGSQL_BASE"
if [[ -d $PGSQL_BASE ]]; then
   [[ "$(ls -A $PGSQL_BASE)" ]] && echo "ERROR: The directory $PGSQL_BASE is not empty." && exit 1
fi
create_dirs

printheader "Initialize PostgreSQL CLuster"
initialize_db

printheader "Moving config files to $PGSQL_BASE/etc"
move_configs

printheader "Copy certificates"
copy_certs

printheader "Updating pg_hba.conf"
update_pg_hba

printheader "Updating parameters in postgresql.conf"
update_db_params

printheader "Manually testing new cluster"
manual_start_stop
if [[ $? -gt 0 ]]; then
  error "Manual test failed, cluster fails to start."
  exit 1
fi

printheader "Generating $PGSQL_BASE/scripts/start.sh."
generate_manual_start_script

printheader "Generating $PGSQL_BASE/scripts/root.sh file."
create_root_sh

printheader "Adding entry into pgclustertab file."
adding_entry_in_pgtab

printheader "Adding entry into ~/.pgpass for superuser."
modify_password_file "$PG_PORT" "$PG_SUPERUSER" "$PG_SUPERUSER_PWD" 

echo -e
echo "INFO: Please execute $PGSQL_BASE/scripts/root.sh as root user."
echo " "
echo "        It will execute following steps:"
echo "           1. Create service file for this cluster. (/etc/systemd/system/$PG_SERVICE_FILE)"
echo "           2. Start the service $PG_SERVICE_FILE"
echo "           3. Execute in-cluster actions."
echo " "

exit 0

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}
