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
#   26.05.2021: Aychin: Initial version created



help() {
  echo "

 Standby manager is a tool to add, switchover, failover and reinstate standby databases.

 Available options:

 --check --target <hostname>          Check the SSH connection from local host to target host and back.
 --status                             Show current configuration and status.
 --sync-config                        Synchronize config with real-time information and distribute on all configured nodes.
 --add-standby --target <hostname>    Add new standby cluster on spevified host. Must be executed on master host.
 --switchover [--target <hostname>]   Switchover to standby. If target was not provided, then local host will be a target.
 --failover [--target <hostname>]     Failover to standby. If target was not provided, then local host will be a target.
                                        Old master will be stopped and marked as REINSTATE in configuration.
 --reinstate [--target <hostname>]    Reinstate old primary as new standby.
 --prepare-master [--target <hostname>]  Can be used to prepare the hostname for master role.

 --force     Can be used with any option to force some operations.

"
}

# Debug
# set -xv

declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"

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


if [[ ${#PGBASENV_ALIAS} -eq 0 ]]; then 
   error "Set the alias for the current cluster first."
   exit 1
fi

pgsetenv $PGBASENV_ALIAS

declare -r REPCONF=$PGOPERATE_BASE/db/repconf_${PGBASENV_ALIAS}
declare -r PG_BIN_HOME=$TVD_PGHOME/bin


PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf
[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
source $PARAMETERS_FILE
[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PGOPERATE_BASE/lib/shared.lib


SSH="ssh -o ConnectTimeout=5 -o PasswordAuthentication=no"
SCP="scp -o ConnectTimeout=5 -o PasswordAuthentication=no"
LOCAL_HOST=$(hostname -s)


# Define log file
prepare_logdir
declare -r LOGFILE="$PGSQL_BASE/log/tools/$(basename $0)_$(date +"%Y%m%d_%H%M%S").log"



check_connection() {
   $SSH $REMOTE_HOST "$SSH $LOCAL_HOST exit" >/dev/null 2>&1
   local RC=$?
   return $RC
}

execute_remote() {
  local host=$1
  local alias=$2
  local cmd=$3
  $SSH $host ". .pgbasenv_profile; pgsetenv $alias; $cmd"
  local RC=$?
  return $RC
}



get_remote_vars() {
  local host=$1
  local output="$($SSH $host ". .pgbasenv_profile; echo \$PGOPERATE_BASE")"
  local RC=$?
  if [[ $RC -eq 0 ]]; then
    REMOTE_PGOPERATE_BASE=$output
  fi
  return $RC
}


# Return status 1 - UP, 2 - data dir not empty, 0 - no cluster
check_remote_cluster() {
  local host=$1
  local alias=$2

  local output="$(execute_remote $host $alias "echo STATUS=\$TVD_PGSTATUS")"
  local status=$(echo $output | grep STATUS= | cut -d"=" -f2)
  if [[ $status == "UP" ]]; then
    return 1
  else
    check_remote_dir $host $PGDATA
    if [[ $? -eq 1 ]]; then
      return 2
    fi 
  fi 

}





###################################################################################
# MAIN
###################################################################################


ca() {
  if [[ $1 =~ ^- ]]; then
     echo "ERROR: Argument $ARG requires value. Check input arguments."
     exit 1
  else
     return 0
  fi
}

FORCE=0
while [[ $1 ]]; do
  ARG=$1
   if [[ "$1" =~ ^-h|^help|^--help ]]; then help && exit 0
 elif [[ "$1" == --parfile ]]; then shift && ca $1 && INPUT_PARFILE=$1 && shift
 else 
   echo "Error: Invalid argument $1" 
   exit 1 
 fi
done

# Script main part begins here. Everything in curly braces will be logged in logfile
{

echo "Command line arguments: $@" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE


if [[ ! -f $INPUT_PARFILE ]]; then
  error "Parameter file $INPUT_PARFILE not found. Provide parameter file with --parfile argument."
  exit 1
fi

source $INPUT_PARFILE


exit $RC

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}

