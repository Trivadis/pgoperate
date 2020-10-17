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
#   06.10.2020: Aychin: Initial version created
#
#
# Adds existing running PostgreSQL cluster to the pgOperate environment.
#


help() {

echo "

Adds existing running PostgreSQL cluster to the pgOperate environment.

Arguments:
              -a|--alias <alias_name> -  Alias name of the running cluster to be added.


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

" > $PGSQL_BASE/scripts/root.sh 
chmod 700 $PGSQL_BASE/scripts/root.sh 
}

set_param() {
local param="$1"
local value="$2"
local repval="$(grep -Ei "^$param *=" $PARAMETERS_FILE)"

if [[ ${#repval} -gt 0 ]]; then
  modifyFile $PARAMETERS_FILE rep "$param=$value" "${repval//[$'\n']}"
else
  modifyFile $PARAMETERS_FILE add "$param=$value"
fi
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
[[ -z $PG_CLUSTER_ALIAS ]] && echo "ERROR: Provide alias name for the cluster to be added." && exit 1


source $HOME/.pgbasenv_profile


PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PG_CLUSTER_ALIAS}.conf


[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PGOPERATE_BASE/lib/shared.lib


pgsetenv $PG_CLUSTER_ALIAS
if [[ $TVD_PGSTATUS != "UP" ]]; then
   echo "ERROR: Cluster must be up and running."
   exit 1
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


PG_PORT=$PGPORT


printheader "Processing TVD_PGHOME_ALIAS"
TVD_PGHOME_ALIAS=$(grep -E "^${TVD_PGHOME};" $PGBASENV_BASE/etc/pghometab | cut -d";" -f4 | xargs)
if [[ -z $TVD_PGHOME_ALIAS ]]; then
  echo "ERROR: No home in $PGBASENV_BASE/etc/pghometab file found matching to ${TVD_PGHOME}! Check your pgBaseEnv installation."
  exit 1
else
  echo "INFO: Parameter TVD_PGHOME_ALIAS will be set to $TVD_PGHOME_ALIAS"
fi

printheader "Processing PGSQL_BASE"
read -p "Please, provide the location for the PGSQL_BASE directory, it will be base location for this cluster: "
echo
if [[ ! -z $REPLY ]]; then
  PGSQL_BASE=$REPLY
  if [[ ! -d $PGSQL_BASE ]]; then
     mkdir -p $PGSQL_BASE/$PG_CLUSTER_ALIAS
     PGSQL_BASE=$PGSQL_BASE/$PG_CLUSTER_ALIAS
     ln -s $PGDATA $PGSQL_BASE/data
  else
     if [[ "$(dirname $PGDATA)" != "$PGSQL_BASE" ]]; then
        PGSQL_BASE=$PGSQL_BASE/$PG_CLUSTER_ALIAS
        ln -s $PGDATA $PGSQL_BASE/data
     else
        if [[ $(basename $PGDATA) != "data" ]]; then
           ln -s $PGDATA $PGSQL_BASE/data
        fi
     fi
  fi
else
  exit 1
fi


echo "PGSQL_BASE=$PGSQL_BASE"



printheader "Processing PGSQL_BASE/etc"
if [[ ! -d $PGSQL_BASE/etc ]]; then
  echo "INFO: Directory not exists."
  if [[ $(dirname $TVD_PGCONF) == $(dirname $TVD_PGHBA) ]]; then
    ln -s $(dirname $TVD_PGCONF) $PGSQL_BASE/etc
    echo "INFO: Symbolic link \$PGSQL_BASE/etc created pointing to $(dirname $TVD_PGCONF)"
  else
    echo "INFO: Creating directory \$PGSQL_BASE/etc"
    mkdir -p $PGSQL_BASE/etc
    ln -s $TVD_PGCONF $PGSQL_BASE/etc/postgresql.conf
    echo "INFO: Symbolic link \$PGSQL_BASE/etc/postgresql.conf created pointing to $TVD_PGCONF"
    ln -s $TVD_PGHBA $PGSQL_BASE/etc/pg_hba.conf
    echo "INFO: Symbolic link \$PGSQL_BASE/etc/pg_hba.conf created pointing to $TVD_PGHBA"
  fi
else
  echo "INFO: Directory is already exists."
  if [[ "$(dirname $TVD_PGCONF)" != "$PGSQL_BASE/etc" ]]; then
     ln -s $TVD_PGCONF $PGSQL_BASE/etc/postgresql.conf
     echo "INFO: Symbolic link \$PGSQL_BASE/etc/postgresql.conf created pointing to $TVD_PGCONF"
  fi
  if [[ "$(dirname $TVD_PGHBA)" != "$PGSQL_BASE/etc" ]]; then 
     ln -s $TVD_PGHBA $PGSQL_BASE/etc/pg_hba.conf
     echo "INFO: Symbolic link \$PGSQL_BASE/etc/pg_hba.conf created pointing to $TVD_PGHBA"
  fi
fi


printheader "Processing PGSQL_BASE/log"
if [[ ! -d $PGSQL_BASE/log ]]; then
  echo "INFO: Directory not exists."
  if [[ $TVD_PGLOG_COLLECTOR == "on" ]]; then
    ln -s $TVD_PGLOG_DIR $PGSQL_BASE/log
    echo "INFO: Logging collector is enabled for this cluster. Symbolic link \$PGSQL_BASE/log created pointing to $TVD_PGLOG_DIR"
  else
    mkdir -p $PGSQL_BASE/log
    echo "INFO: Logging collector is not enabled for this cluster. Directory \$PGSQL_BASE/log created."
    echo "INFO: It is strongly recommended to enable logging collector and point it to \$PGSQL_BASE/log."
  fi
fi



printheader "Processing superuser details"
read -p "Please, provide the superuser [postgres]: "
echo
if [[ ! -z $REPLY ]]; then
  PG_SUPERUSER=$REPLY
else
  PG_SUPERUSER="postgres"
fi

echo
echo "PG_SUPERUSER=$PG_SUPERUSER"
echo

read -p "Please, provide the superuser password: "
echo
if [[ ! -z $REPLY ]]; then
  PG_SUPERUSER_PWD=$REPLY
else
  PG_SUPERUSER_PWD=
fi


printheader "Processing backup parameters"
if [[ ! -d $PGSQL_BASE/backup ]]; then
   read -p "Please, provide the location for the backups [\$PGSQL_BASE/backup]: "
   echo
   if [[ ! -z $REPLY ]]; then
     BACKUP_DIR=$REPLY
     if [[ $BACKUP_DIR != $PGSQL_BASE/backup ]]; then
       ln -s $BACKUP_DIR \$PGSQL_BASE/backup
       echo "INFO: Symbolic link \$PGSQL_BASE/backup created pointing to $BACKUP_DIR"
       BACKUP_LOCATION="\$PGSQL_BASE/backup"
     fi
   else
     BACKUP_LOCATION="\$PGSQL_BASE/backup"
     echo "INFO: Backup location will be \$PGSQL_BASE/backup"
   fi

else
  echo "INFO: Directory \$PGSQL_BASE/backup already exists."
  if [[ "$(ls -A $PGSQL_BASE/backup)" ]]; then
     echo "ERROR: The directory $PGSQL_BASE/backup is not empty. It must be empty."
     exit 1
  else
     echo "INFO: \$PGSQL_BASE/backup will be used as backup location."
     BACKUP_LOCATION="\$PGSQL_BASE/backup"
  fi
fi

echo

if [[ ! -d $PGSQL_BASE/arch ]]; then
   read -p "Please, provide the spare location for the archived WALs [\$PGSQL_BASE/arch]: "
   echo
   if [[ ! -z $REPLY ]]; then
     ARCH_DIR=$REPLY
     if [[ $ARCH_DIR != $PGSQL_BASE/arch ]]; then
       ln -s $ARCH_DIR \$PGSQL_BASE/arch
       echo "INFO: Symbolic link \$PGSQL_BASE/arch created pointing to $ARCH_DIR"
     fi
   else
     echo "INFO: Arch location will be \$PGSQL_BASE/arch"
   fi

else
  echo "INFO: Directory \$PGSQL_BASE/arch already exists."
  echo "INFO: \$PGSQL_BASE/arch will be used as spare archive location."
fi



printheader "Creating parameters file $PARAMETERS_FILE"
cp $PGOPERATE_BASE/etc/parameters_mycls.conf.tpl $PARAMETERS_FILE

echo "TVD_PGHOME_ALIAS = $TVD_PGHOME_ALIAS"
set_param "TVD_PGHOME_ALIAS" "$TVD_PGHOME_ALIAS"
set_param "PGSQL_BASE" "$PGSQL_BASE"
set_param "PG_PORT" "$PGPORT"
set_param "PG_ENCODING" "$(psql -c "show server_encoding;" -t 2>/dev/null | xargs)"
PG_ENABLE_CHECKSUM=$(pg_controldata | grep "Data page checksum version:" | cut -d":" -f2 | xargs)
[[ $PG_ENABLE_CHECKSUM == "1" ]] && PG_ENABLE_CHECKSUM="yes" || PG_ENABLE_CHECKSUM="no"
set_param "PG_ENABLE_CHECKSUM" "$PG_ENABLE_CHECKSUM"
set_param "PG_SUPERUSER" "$PG_SUPERUSER"
set_param "PG_SUPERUSER_PWD" "$PG_SUPERUSER_PWD"
set_param "BACKUP_LOCATION" "$BACKUP_LOCATION"



PG_SERVICE_FILE="postgresql-${PG_CLUSTER_ALIAS}.service"
PG_BIN_HOME=$TVD_PGHOME/bin


printheader "Generating $PGSQL_BASE/scripts/start.sh."
mkdir -p $PGSQL_BASE/scripts
generate_manual_start_script

printheader "Generating $PGSQL_BASE/scripts/root.sh file."
create_root_sh

printheader "Adding entry into ~/.pgpass for superuser."
modify_password_file "$PG_PORT" "$PG_SUPERUSER" "$PG_SUPERUSER_PWD" 

echo -e
echo "INFO: If you want to register cluster with systemctl execute $PGSQL_BASE/scripts/root.sh as root user."
echo " "
echo "        It will execute following steps:"
echo "           Create service file for this cluster. (/etc/systemd/system/$PG_SERVICE_FILE)"
echo " "


echo -e "\nLogfile of this execution: $LOGFILE\n"
exit 0

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}
