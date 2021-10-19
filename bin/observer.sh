#!/usr/bin/env bash

SSH="ssh -o ConnectTimeout=5 -o PasswordAuthentication=no"


ca() {
  if [[ $1 =~ ^- ]]; then
     echo "ERROR: Argument $ARG requires value. Check input arguments."
     exit 1
  else
     return 0
  fi
}

while [[ $1 ]]; do
  ARG=$1
   if [[ "$1" =~ ^-h|^help|^--help ]]; then help && exit 0
 elif [[ "$1" == --force ]]; then FORCE=1 && shift
 elif [[ "$1" == --conf-file ]]; then shift && ca $1 && INPUT_CONF_FILE=$1 && shift
 else
   echo "Error: Invalid argument $1"
   exit 1
 fi
done

if [[ -f $INPUT_CONF_FILE ]]; then
  source $INPUT_CONF_FILE
else
  echo "ERROR: Provide valid config file with parameter --conf-file."
  exit 1
fi

[[ -z $POLL_INTERVAL_SEC ]] && POLL_INTERVAL_SEC=3
[[ -z $FAIL_COUNT ]] && FAIL_COUNT=3

execute_remote() {
  local host=$1
  local alias=$2
  local cmd=$3
  $SSH $host ". .pgbasenv_profile; pgsetenv $alias; $cmd"
  local RC=$?
  return $RC
}

check_members() {
  if [[ -z $MASTER_NODE || -z $STANDBY_NODE || -z $PGPORT ]]; then
    return 1
  else
    return 0
  fi
}


get_members() {
  ex() {
    echo "MASTER_NODE=$MASTER_NODE"
    echo "STANDBY_NODE=$STANDBY_NODE"
    echo "PGPORT=$PGPORT"
  }
  trap ex RETURN
  unset MASTER_NODE STANDBY_NODE PGPORT
  for h in ${PGHOSTS//,/ }; do
    echo "Try host $h"
    execute_remote $h $PGALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --sync-config"
    local status
    status=$(execute_remote $h $PGALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --status --list")
    local status_RC=$?
    if [[ $status_RC -eq 0 ]]; then
      MASTER_NODE=$(echo "$status" | grep MASTER | cut -d"|" -f2)
      STANDBY_NODE=$(echo "$status" | grep "STANDBY|UP|" | sort -n | head -1 | cut -d"|" -f2)
      PGPORT=$(execute_remote $h $PGALIAS "echo \$PGPORT")
      [[ ${#PGPORT} -gt 6 ]] && unset PGPORT
      break
    fi
  done

  check_members
  return $?
}

get_members

ftime=$(date +%s)
fcount=0
ccount=0
while true; do

  atime=$(date +%s)

  if [[ $((atime-ftime)) -ge 60 ]]; then
    echo "INFO: Actualize members info."
    get_members
    ftime=$(date +%s)
  fi


  # Check master
  check_members
  if [[ $? -gt 0 ]]; then
    ((ccount++))
    sleep 1
    if [[ $ccount -ge 10 ]]; then
      get_members
      ccount=0
    fi
    continue
  fi

  #$PG_BIN_DIR/pg_isready -h $MASTER_NODE -p $PGPORT
  $SSH $MASTER_NODE exit && ssh $MASTER_NODE ". .pgbasenv_profile; \$PGOPERATE_BASE/bin/control.sh daemon-status"
  M_RC=$?

  if [[ $M_RC -gt 0 ]]; then

    ((fcount++))
    echo "WARNING: PostgreSQL on master node $MASTER_NODE is not reachable. Fail count is ${fcount}."
    if [[ $fcount -ge $FAIL_COUNT ]]; then
      fcount=0
      echo "INFO: Checking from standby node $STANDBY_NODE"
      get_members
      [[ $? -gt 1 ]] && echo "WARNING: Not enough member information to continue." && continue

      # Check master from standby node
      #execute_remote $STANDBY_NODE $PGALIAS "pg_isready -h $MASTER_NODE -p $PGPORT"
      execute_remote $STANDBY_NODE $PGALIAS "$SSH $MASTER_NODE exit && ssh $MASTER_NODE ". .pgbasenv_profile; \$PGOPERATE_BASE/bin/control.sh daemon-status""
      S_RC=$?

      if [[ $S_RC -gt 1 ]]; then
         echo "WARNING: PostgreSQL on master node $MASTER_NODE is not reachable from standby node $STANDBY_NODE"
         echo "INFO: Initiating failover to $STANDBY_NODE"
         execute_remote $STANDBY_NODE $PGALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --failover"
         get_members
      else
         echo "INFO: PostgreSQL on master node $MASTER_NODE is reachable from standby node $STANDBY_NODE. No failover will be executed."
      fi

    fi # fail count

  fi


  sleep $POLL_INTERVAL_SEC
done
