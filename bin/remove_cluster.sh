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
# Removes PostgreSQL cluster.
#


help() {

echo "

Removes PostgreSQL cluster and its directories.

Arguments:
              -a|--alias <alias_name> -  Alias name of the cluster to be removed.


"

}




declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"


printheader() {
  GRE='\033[0;32m'
  NC='\033[0m'

  echo -e "$GRE"
  echo -e "----------------------------------------------------------------------------"
  echo -e "[   $1"
  echo -e "----------------------------------------------------------------------------"
  echo -e "$NC"

}


create_pg_rm_service_sh() {
  echo "#!/usr/bin/env bash

systemctl disable $PG_SERVICE_FILE
rm -f /etc/systemd/system/$PG_SERVICE_FILE

" > /tmp/pg_rm_service.sh
chmod +x /tmp/pg_rm_service.sh
}



removing_entry_from_pgtab() {
  sed -i "/;$PG_CLUSTER_ALIAS$/d" $PGBASENV_BASE/etc/pgclustertab
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
[[ -z $PG_CLUSTER_ALIAS ]] && echo "ERROR: Provide alias name for the cluster to be deleted." && exit 1


source $HOME/.pgbasenv_profile

PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PG_CLUSTER_ALIAS}.conf
[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
source $PARAMETERS_FILE
_SAVE_=$PGSQL_BASE

[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PGOPERATE_BASE/lib/shared.lib

# Set environment of the cluster to be deleted
pgsetenv $PG_CLUSTER_ALIAS
PGSQL_BASE=$_SAVE_

[[ -z $PGDATA ]] && echo "ERROR: PGDATA is not defined, check if the cluster alias specified correctly." && exit 1

read -p "Cluster $PG_CLUSTER_ALIAS will be deleted. Cluster base directory including \$PGDATA will be removed. Continue? [y/n]" -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Nothing done."
  exit 0
fi

# Define log file
mkdir -p $PGOPERATE_BASE/log
declare -r LOGFILE="$PGOPERATE_BASE/log/$(basename $0)_$(date +"%Y%m%d_%H%M%S").log"


# Everything in curly braces will be logged in logfile
{

echo "Command line arguments: ${ARGS}" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE


PG_SERVICE_FILE="postgresql-${PG_CLUSTER_ALIAS}.service"
PG_BIN_HOME=$TVD_PGHOME/bin


printheader "Stopping cluster."
sudo systemctl stop $PG_SERVICE_FILE

printheader "Removing $PGSQL_BASE directory."
if [[ -d $PGSQL_BASE ]]; then
   rm -Rf $PGSQL_BASE
fi

printheader "Removing entry from pgclustertab file."
removing_entry_from_pgtab


if [[ $PGPORT -gt 1 ]]; then
  printheader "Removing entries from ~/.pgpass for port $PGPORT."
  cp ~/.pgpass ~/.pgpass.bkp
  sed -i "/:$PGPORT:/d" ~/.pgpass
fi 

create_pg_rm_service_sh

echo -e
echo "INFO: Please execute /tmp/pg_rm_service.sh as root user to remove service file for this cluster."
echo " "

echo -e "\nLogfile of this execution: $LOGFILE\n"
exit 0

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}
