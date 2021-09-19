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
#  Created on 02.2021 by Aychin Gasimov
#
# Change log:
#   05.02.2020: Aychin: Initial version created


help() {
  echo "

 Script to control PostgreSQL instances.
 
 With this script you can start and stop your instaces or check the status of the pgOperate daemon-process. 
 
 First argumant:
        start     Intended state of the instance will be changed to UP and pgoperated process will be woken up.
         stop     Intended state of the instance will be changed to DOWN and pgoperated process will be woken up.
daemon-status     Check the status of the pgOperate daemon process (pgoperated).

 Second argument:
        force     Can be used to force some operations.

"
}

declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"

if [[ $1 != "daemon-status" ]]; then

  [[ -z $PGBASENV_ALIAS ]] && error "Set the alias for the current cluster first." && exit 1

  [[ -z $PGBASENV_ALIAS ]] && error "PG_BIN_HOME is not defined. Set the environment for cluster home."
  PG_BIN_HOME=$TVD_PGHOME/bin

  PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf
  [[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
  source $PARAMETERS_FILE
  [[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
  source $PGOPERATE_BASE/lib/shared.lib
fi

# Checking PGPORT
[[ -z $PGPORT || $PGPORT -eq 1 ]] && PGPORT=$PG_PORT


set_param() {
local param="$1"
local value="$2"
local repval="$(grep -Ei "(^|#) *$param *=" $PARAMETERS_FILE)"

if [[ ${#repval} -gt 0 ]]; then
  modifyFile $PARAMETERS_FILE rep "$param=$value" "${repval//[$'\n']}"
else
  modifyFile $PARAMETERS_FILE add "$param=$value"
fi
}

PID_FILE=$PGOPERATE_BASE/bin/pgoperate-deamon.pid
PIPE_FILE=/tmp/.pgoperate.${PGBASENV_ALIAS}
LOCK_FILE=/tmp/.pgoperate.${PGBASENV_ALIAS}.lock

on_exit() {
   rm -f $PIPE_FILE
   rm -f $LOCK_FILE
}
trap on_exit EXIT


start_local() {
  local RC=0
  if [[ -z $PG_START_SCRIPT ]]; then
    pg_ctl start -D ${PGDATA} -l $PGSQL_BASE/log/server.log -s -o "-p ${PGPORT} --config_file=$PGSQL_BASE/etc/postgresql.conf $ADDITIONAL_START_OPTIONS" -w -t 300
    RC=$?
  else
    $PG_START_SCRIPT
    RC=$?
  fi
  return $RC
}

stop_local() {
  local RC=0
  if [[ -z $PG_STOP_SCRIPT ]]; then
    pg_ctl stop -s -m fast
    RC=$?
  else
    $PG_STOP_SCRIPT
    RC=$?
  fi
  return $RC
}


call_daemon() {
     [[ ! -p $PIPE_FILE ]] && mkfifo $PIPE_FILE
     kill -USR1 $(cat $PID_FILE)
     local msg=
     while true; do
       if read msg <$PIPE_FILE; then
          [[ ! -z "$msg" ]] && break
       fi
     done
     echo "$msg"
}

check_response() {
  local res=$1
  if [[ $res == "SUCCESS" ]]; then
     echo "Success response from daemon."
     return 0
  elif [[ $res == "FAIL" ]]; then
     echo "Failure response from daemon."
     echo "Last 10 lines from $PGSQL_BASE/log/server.log"
     tail -10 $PGSQL_BASE/log/server.log
     return 1
  elif [[ $res == "NOACTION" ]]; then
     echo "No action required response from daemon. Intended state already achived."
     return 0
  fi
}


exec 9>$LOCK_FILE
flock -x 9
if [[ $1 == "start" ]]; then

  local_status=$($PGOPERATE_BASE/bin/standbymgr.sh --status --list | grep "|$(hostname -s)|" | cut -d"|" -f3)
  RC=$?
  if [[ $RC -eq 0 && $local_status == "REINSTATE" && $2 != "force" ]]; then
      echo "INFO: The cluster is in reinstate mode. Reinstate it first with --reinstate option."
      exit 1
  fi

  echo -e "Starting cluster ${PGBASENV_ALIAS}."
  set_param "INTENDED_STATE" "UP"
  if [[ -f $PID_FILE && $AUTOSTART == "YES" ]]; then
     check_response $(call_daemon)
     RC=$?
     if [[ $RC -gt 0 ]]; then
        set_param "INTENDED_STATE" "DOWN"
        exit 1
     fi
  else
     start_local
     RC=$?

  fi


elif [[ $1 == "stop" ]]; then
  echo -e "Stopping cluster ${PGBASENV_ALIAS}."
  set_param "INTENDED_STATE" "DOWN"
  if [[ -f $PID_FILE && $AUTOSTART == "YES" ]]; then
     check_response $(call_daemon)
     RC=$?
     if [[ $RC -gt 0 ]]; then
        set_param "INTENDED_STATE" "UP"
        exit 1
     fi
  else
     stop_local
     RC=$?
  fi


elif [[ $1 == "daemon-status" ]]; then
  if [[ -f $PID_FILE ]]; then
    DPID=$(cat $PID_FILE)
    #kill -0 $DPID > /dev/null 2>&1
    ps -p $DPID -o args= | grep -q pgoperated
    RC=$?
    if [[ $RC -gt 0 ]]; then
       echo "PROBLEM: Inconsistent state. PID file exists but there is no daemon process with this $DPID running. Remove $PID_FILE and restart pgoperated cleanly with sudo systemctl stop/start pgoperated-$(id -nu)"
       exit 1
    else
       echo "pgoperated up and running."
    fi
  else
    PCOUNT=$(ps -aef | grep pgoperated | grep -v grep | wc -l)
    if [[ $PCOUNT -gt 0 ]]; then
       echo "PROBLEM: Inconsistent state. PID file not found but there is pgoperated processes running. Restart pgoperated cleanly with sudo systemctl stop/start pgoperated-$(id -nu)"
       exit 1
    else
       echo "pgoperated is down."
    fi
  fi

else
  help

fi

exec 9>&-
exit $RC
