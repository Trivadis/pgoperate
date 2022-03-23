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
#   19.10.2020: Aychin: uniqnames was introduced



help() {
  echo "

 Standby manager is a tool to add, switchover, failover and reinstate standby databases.

 Available options:

 --check --host <hostname> --master-host <hostname>  Check the SSH connection from local host to target host and back.
 --status                             Show current configuration and status.
 --sync-config                        Synchronize config with real-time information and distribute on all configured nodes.
 --add-standby --uniqname <name> --host <hostname> [--master-uniqname <master name> --master-host <master hostname>]    Add new standby cluster on specified host. 
                                          Provide uniq name and hostname to connect. If there was no configuration, then also master uniqname and hostname are required.  
                                          Must be executed on master host.
 --show-uniqname                      Get the uniqname of the local site.
 --set-sync --target <uniqname> [--bidirectional]  Set target standby to synchronous replication mode.  
 --set-async --target <uniqname> [--bidirectional]  Set target standby to asynchronous replication mode.
                                      If bidirectional option specified, then current master will be added as synchronous 
                                      standby to the target standbys configuration. To maintain synchronous replication after switchover.
 --switchover [--target <uniqname>]   Switchover to standby. If target was not provided, then local site will be a target.
 --failover [--target <uniqname>]     Failover to standby. If target was not provided, then local site will be a target.
                                        Old master will be stopped and marked as REINSTATE in configuration.
 --reinstate [--target <uniqname>]    Reinstate old primary as new standby.
 --prepare-master [--target <uniqname>]  Can be used to prepare the hostname for master role.

 --force     Can be used with any option to force some operations.

"
}

# Debug
# set -xv

declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"

# Execution ID. Can be used for debugging.
declare -r EXECID=$((1 + $RANDOM % 9999))

# Set custom .psqlrc file
export PSQLRC=$PGOPERATE_BASE/bin/.psqlrc

OS_USER=$(id -un)
OS_GROUP=$(id -gn)

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

[[ ! -f $PGOPERATE_BASE/lib/check.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/check.lib file." && exit 1
source $PGOPERATE_BASE/lib/check.lib


SSH="ssh -o ConnectTimeout=5 -o PasswordAuthentication=no"
SCP="scp -o ConnectTimeout=5 -o PasswordAuthentication=no"
LOCAL_HOST=$(hostname -s)


# Define log file
prepare_logdir
declare -r LOGFILE="$PGSQL_BASE/log/tools/$(basename $0)_$(date +"%Y%m%d_%H%M%S").log"


set_param() {
local file="$1"
local param="$2"
local value="$3"
local repval="$(grep -Ei "(^|#| )$param *=" $file)"

if [[ ${#repval} -gt 0 ]]; then
  modifyFile $file rep "$param=$value" "${repval//[$'\n']}"
else
  modifyFile $file add "$param=$value"
fi
}

exec_pg() {
  local cmd="$1"
  local db="$2"
  [[ -z $db ]] && db=postgres
  # output must be declared separately or return code from subshell will not be captured
  local output
  output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d $db -c "$1" -t 2>&1)"
  local res=$?
  echo "$output"
  return $res
}


update_db_params() {
  modifyFile "$PGSQL_BASE/etc/postgresql.conf" bkp
  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" wal_level "replica"
  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_wal_senders "10"
  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_replication_slots "10"
  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" hot_standby "on"
}

update_pg_hba() {
  grep -q "#pgOperate replication#" $PGSQL_BASE/etc/pg_hba.conf
  [[ $? -gt 0 ]] && echo -e "# For replication. Connect from remote hosts. #pgOperate replication#\nhost    replication     replica      0.0.0.0/0      scram-sha-256" >> $PGSQL_BASE/etc/pg_hba.conf
}

check_connection() {
   local remote_host=$1
   local local_host=$2
   $SSH $remote_host "$SSH $local_host exit" >/dev/null 2>&1
   local RC=$?
   return $RC
}

execute_remote() {
  local host=$1
  local alias=$2
  local cmd=$3
  $SSH $host ". ~/.PGBASENV_HOME; . \$PGBASENV_BASE/bin/pgsetenv.sh --noscan; pgsetenv $alias; $cmd"
  local RC=$?
  return $RC
}

execute_remote_noalias() {
  local host=$1
  local cmd=$2
  $SSH $host ". ~/.PGBASENV_HOME; . \$PGBASENV_BASE/bin/pgsetenv.sh --noscan; $cmd"
  local RC=$?
  return $RC
}

create_repconf() {
  local tab=$1
  if [[ ! -d $REPCONF ]]; then
    mkdir $REPCONF
    local RC=$?
    if [[ $RC -gt 0 ]]; then
      return 1
    fi
  fi
}


get_new_row() {
  local tab=$1
  local lastRow=$(ls -1d $REPCONF/* | sort -n | xargs -0 basename | xargs)
  ((lastRow++))
  echo $lastRow
}



initialize_config() {
   mkdir -p $REPCONF/1
   echo "1" > $REPCONF/1/1_id
   echo "$INPUT_MASTER_HOST" > $REPCONF/1/2_host
   echo "MASTER" > $REPCONF/1/3_role
   echo "$INPUT_MASTER_UNIQNAME" > $REPCONF/1/4_uniqname
}

db_copy_to_standbys() {
  local standby_host
  for d in $(ls $REPCONF); do
    if [[ $(cat $REPCONF/$d/3_role) != "MASTER" ]]; then
      standby_host=$(cat $REPCONF/$d/2_host)
      get_remote_vars $standby_host
      execute_remote $standby_host $PGBASENV_ALIAS "rm -rf $REMOTE_PGOPERATE_BASE/db/repconf_${PGBASENV_ALIAS}"
      $SCP -r $PGOPERATE_BASE/db/repconf_${PGBASENV_ALIAS} $standby_host:$REMOTE_PGOPERATE_BASE/db/
      if [[ $? -gt 0 ]]; then
        error "Failed to scp to $standby_host."
      fi
    fi
  done
}


get_actual_status() {
   local role start_time
   if [[ $TVD_PGIS_STANDBY == "YES" ]]; then
     role='STANDBY'
   else
     role='MASTER'
   fi
   local apply_lag_mb transfer_lag_mb transfer_lag_min
   if [[ $role == "STANDBY" ]]; then
     if [[ $TVD_PGSTATUS == "UP" ]]; then
       PG_AVAILABLE=true
       
       check_stdby_apply_delay_mb
       apply_lag_mb=$check_stdby_apply_delay_mb_VALUE

       check_stdby_tr_delay_mb
       transfer_lag_mb=$check_stdby_tr_delay_mb_VALUE

       check_stdby_ap_lag_time
       transfer_lag_min=$check_stdby_ap_lag_time_VALUE
     fi

   fi
   pgsetenv $PGBASENV_ALIAS
   if [[ $TVD_PGSTATUS == "UP" ]]; then
     start_time=$(psql -t -c "SELECT date_part('epoch', pg_postmaster_start_time())" | xargs | cut -d"." -f1)
   else
     start_time="NA"
   fi
   
   echo "$role|$TVD_PGSTATUS|$TVD_PGSTANDBY_STATUS|$apply_lag_mb|$transfer_lag_mb|$transfer_lag_min|$start_time"
}


show_actual_status() {
  local status=$(get_actual_status)
  echo "Current node: $(hostname -s)"
  echo "Role: $(echo $status | cut -d'|' -f1)"
  echo "State: $(echo $status | cut -d'|' -f2)"
  if [[ $(echo $status | cut -d'|' -f1) == "STANDBY" ]]; then
    echo "WAL receiver status: $(echo $status | cut -d'|' -f3)"
    echo "Apply lag (MB): $(echo $status | cut -d'|' -f4)"
    echo "Transfer lag (MB): $(echo $status | cut -d'|' -f5)"
    echo "Transfer lag (Minutes): $(echo $status | cut -d'|' -f6)"
  fi
}


get_actual_status_from_nodes() {
  local d host role uniqname stats RC
  local res
  for d in $(ls $REPCONF); do
    host=$(cat $REPCONF/$d/2_host)
    role=$(cat $REPCONF/$d/3_role)
    uniqname=$(cat $REPCONF/$d/4_uniqname)
    if [[ $role != "REINSTATE" ]]; then
      if [[ $(is_local_host $host) == "YES" ]]; then
        stats=$(get_actual_status)
        RC=$?
      else 
        stats=$(execute_remote $host $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --get-local-status")
        RC=$?
      fi
      if [[ $RC -eq 0 ]]; then
         res=$(echo -e "$res\n$host|$stats|$uniqname")
      fi
    fi
  done
  echo "$res"     
}

db_sync_with_actual_data() {
  local actual="$1"
  local master_found=0
  while IFS= read -r line; do
    local host=$(echo $line | cut -d'|' -f1)
    local role=$(echo $line | cut -d'|' -f2)
    local uniqname=$(echo $line | cut -d'|' -f9)
    if [[ $role == "MASTER" && $master_found -eq 0 ]]; then
      master_found=1
      db_set_new_master $uniqname
    fi
  done <<< "$actual"
}

sync_config() {
  local d RC
  if [[ -z $INPUT_PAYLOAD ]]; then
     local actual_status="$(get_actual_status_from_nodes | sort -n -t'|' -k8)"
  else
     local actual_status="$INPUT_PAYLOAD"
  fi
  local actual_master_row=$(echo "$actual_status" | grep "MASTER")
  local actual_master=$(echo $actual_master_row | cut -d"|" -f1)
  local actual_master_uniqname=$(echo $actual_master_row | cut -d"|" -f9)

  if [[ $(is_local_host $actual_master) == "YES" ]]; then
    echo "Executing sync on master $actual_master_uniqname ($actual_master)"
    db_sync_with_actual_data "$actual_status"
    for d in $(ls $REPCONF); do
      if [[ $(cat $REPCONF/$d/3_role) == "MASTER" ]]; then
         if [[ $(is_local_host $(cat $REPCONF/$d/2_host)) == "YES" ]]; then
            db_copy_to_standbys
            return 0          
         fi
      fi
    done

  else
    execute_remote $actual_master $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --sync-config --payload \"$actual_status\""
    RC=$?
    return $RC
  fi

  return 1
}

get_sync_standbys() {
  local master=$1
  
  if [[ $(is_local_host $master) == "YES" ]]; then
    local sync_standbys=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "select string_agg(application_name||':'||sync_state, ',') from pg_stat_replication" 2>&1)
    echo "$sync_standbys"
  else
    execute_remote $master $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --exec --payload \"get_sync_standbys $master\""
  fi

}

list_db() {
  local mode=$1
  local row
  local nodenum nodename role actual_role cls_status wal_receiver apply_lag_mb tr_lag_mb tr_lag_min stats uniqname

  if [[ ! -d $REPCONF ]]; then
     echo "No configuration exists on this host."
     return 1
  fi

  local actual_status=$(get_actual_status_from_nodes)
  
  if [[ $mode != "list" ]]; then
     local master=$(echo "$actual_status" | grep MASTER | cut -d"|" -f1)
     local sync_standbys=$(get_sync_standbys $master)
  fi

  local mode
  [[ ! -d $REPCONF ]] && return
  [[ $mode != "list" ]] && printf "%-11s %-10s %-20s %-15s %9s %-5s %-10s %12s %15s %16s\n" "Node_number" "Uniq_name" "Host" "Role" "Mode" "State" "WAL_receiver" "Apply_lag_MB" "Transfer_lag_MB" "Transfer_lag_Min"
  for row in $(ls $REPCONF); do
     nodenum="$(cat $REPCONF/$row/1_id)"
     nodename="$(cat $REPCONF/$row/2_host)"
     role="$(cat $REPCONF/$row/3_role)"
     stats=$(echo "$actual_status" | grep "^$nodename|")
     actual_role=$(echo $stats | cut -d"|" -f2)
     cls_status=$(echo $stats | cut -d"|" -f3)
     wal_receiver=$(echo $stats | cut -d"|" -f4)
     apply_lag_mb=$(echo $stats | cut -d"|" -f5)
     tr_lag_mb=$(echo $stats | cut -d"|" -f6)
     tr_lag_min=$(echo $stats | cut -d"|" -f7)
     uniqname="$(cat $REPCONF/$row/4_uniqname)"
    
     if [[ $mode != "list" ]]; then 
        [[ ",$sync_standbys," =~ ,${uniqname}: ]] && mode=$(echo -e "${sync_standbys//,/\\n}" | grep "${uniqname}:" | cut -d: -f2)
        [[ $role != STANDBY ]] && mode=""
        printf "%-11s %-10s %-20s %-15s %9s %-5s %-10s %12s %15s %16s\n" "$nodenum" "$uniqname" "$nodename" "$role" "$mode" "$cls_status" "$wal_receiver" "$apply_lag_mb" "$tr_lag_mb" "$tr_lag_min"
     else
        echo "$nodenum|$nodename|$role|$cls_status|$wal_receiver|$apply_lag_mb|$tr_lag_mb|$tr_lag_min|$uniqname"
     fi
     stats=""
  done
}



db_set_new_master() {
  local master_uniqname=$1
  local row nodenum nodeuniqname role
  for row in $(ls $REPCONF); do
     nodenum="$(cat $REPCONF/$row/1_id)"
     nodeuniqname="$(cat $REPCONF/$row/4_uniqname)"
     role="$(cat $REPCONF/$row/3_role)"
     if [[ $nodeuniqname != $master_uniqname ]]; then
        [[ $role != "REINSTATE" ]] && echo "STANDBY" > $REPCONF/$row/3_role
     else
        echo "MASTER" > $REPCONF/$row/3_role
     fi
  done
}


db_set_to_reinstate() {
  local uniqname=$1
  local row nodenum nodeuniqname role
  for row in $(ls $REPCONF); do
     nodenum="$(cat $REPCONF/$row/1_id)"
     nodeuniqname="$(cat $REPCONF/$row/4_uniqname)"
     role="$(cat $REPCONF/$row/3_role)"
     if [[ $nodeuniqname == $uniqname ]]; then
        echo "REINSTATE" > $REPCONF/$row/3_role
     fi
  done
}


db_add_standby() {
   local uniqname=$1
   local hostname=$2
   local row nodename
   local db_val=$(db_get_by_uniqname $uniqname)
   if [[ -z $db_val ]]; then
     row=$(get_new_row $REPCONF)
     mkdir -p $REPCONF/$row
     local maxId=$(cat $REPCONF/*/1_id | sort -n | tail -1)
     ((maxId++))
     echo $maxId > $REPCONF/$row/1_id
     echo "$hostname" > $REPCONF/$row/2_host
     echo "STANDBY" > $REPCONF/$row/3_role
     echo "$uniqname" > $REPCONF/$row/4_uniqname
   else
     
     for row in $(ls $REPCONF); do
       local uname="$(cat $REPCONF/$row/4_uniqname)"
       if [[ $uname == $uniqname ]]; then
         echo "STANDBY" > $REPCONF/$row/3_role
       fi
     done

   fi
}


db_remove_host() {
   local uniqname=$1
   local row nodename
   local RC

   for row in $(ls $REPCONF); do
       nodeuniqname="$(cat $REPCONF/$row/4_uniqname)"
       if [[ $nodeuniqname == $uniqname ]]; then
         rm -Rf $REPCONF/$row
         RC=$?
       fi
   done

   return $RC
}


db_get_master() {
  local d
  shopt -s nocasematch
  for d in $(ls $REPCONF); do
    if [[ $(cat $REPCONF/$d/3_role) == "MASTER" ]]; then
      echo "$(cat $REPCONF/$d/1_id)|$(cat $REPCONF/$d/2_host)|$(cat $REPCONF/$d/3_role)|$(cat $REPCONF/$d/4_uniqname)"
    fi
  done
  shopt -u nocasematch
}

db_get_uniqname() {
  local host=$1
  local d
  shopt -s nocasematch
  for d in $(ls $REPCONF); do
    if [[ $(cat $REPCONF/$d/2_host) == $host ]]; then
      echo "$(cat $REPCONF/$d/4_uniqname)"
    fi
  done
  shopt -u nocasematch
}

db_get_standby() {
  local uniqname=$1
  local d
  shopt -s nocasematch
  for d in $(ls $REPCONF); do
    if [[ $(cat $REPCONF/$d/3_role) == "STANDBY" && $(cat $REPCONF/$d/4_uniqname) == $uniqname ]]; then
      echo "$(cat $REPCONF/$d/1_id)|$(cat $REPCONF/$d/2_host)|$(cat $REPCONF/$d/3_role)"
    fi
  done
  shopt -u nocasematch
}


db_get_by_hotsname() {
  local host=$1
  local d
  shopt -s nocasematch
  for d in $(ls $REPCONF); do
    if [[ $(cat $REPCONF/$d/2_host) == $host ]]; then
      echo "$(cat $REPCONF/$d/1_id)|$(cat $REPCONF/$d/2_host)|$(cat $REPCONF/$d/3_role)"
      return 0
    fi
  done
  shopt -u nocasematch
}

db_get_by_uniqname() {
  local uniqname=$1
  local d
  shopt -s nocasematch
  for d in $(ls $REPCONF); do
    if [[ $(cat $REPCONF/$d/4_uniqname) == $uniqname ]]; then
      echo "$(cat $REPCONF/$d/1_id)|$(cat $REPCONF/$d/2_host)|$(cat $REPCONF/$d/3_role)"
      return 0
    fi
  done
  shopt -u nocasematch
}

db_get_reinstate() {
  local host=$1
  local d
  shopt -s nocasematch
  for d in $(ls $REPCONF); do
    if [[ $(cat $REPCONF/$d/3_role) == "REINSTATE" && $(cat $REPCONF/$d/2_host) == $host ]]; then
      echo "$(cat $REPCONF/$d/1_id)|$(cat $REPCONF/$d/2_host)|$(cat $REPCONF/$d/3_role)"
    fi
  done
  shopt -u nocasematch
}



copy_params_file_to_remote() {
  scp $PARAMETERS_FILE $REMOTE_HOST:$REMOTE_PGOPERATE_BASE/etc
  local RC=$?
  return $RC   
}


set_autostart() {
local param="AUTOSTART"
local value="$1"
local repval="$(grep -Ei "(^|#) *$param *=" $PARAMETERS_FILE)"

if [[ ${#repval} -gt 0 ]]; then
  modifyFile $PARAMETERS_FILE rep "$param=$value" "${repval//[$'\n']}"
else
  modifyFile $PARAMETERS_FILE add "$param=$value"
fi
}


create_replica_user() {
  local output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "select true from pg_roles where rolname='replica'" -t 2>&1)"
  if [[ -z $output ]]; then
     output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "CREATE USER replica WITH REPLICATION PASSWORD '$REPLICA_USER_PASSWORD';" -t 2>&1)"
     local RC=$?
  else
     output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "ALTER USER replica PASSWORD '$REPLICA_USER_PASSWORD';" -t 2>&1)"
     local RC=$?
  fi
  [[ $RC -gt 0 ]] && echo "$output"
  return $RC
}


create_replication_slot() {
  local uniqname=$1
  local slot_name="slot_${uniqname}"
  local output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "select true from pg_replication_slots where slot_name = '${slot_name}'" -t 2>&1)"
  local RC=$?
  if [[ -z $output ]]; then
     output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "SELECT * FROM pg_create_physical_replication_slot('${slot_name}')" -t 2>&1)"
     RC=$?
     [[ $RC -eq 0 ]] && echo "Replication slot ${slot_name} created on ${LOCAL_HOST}." || echo "Failed to create replication slot ${slot_name}."
  fi
  return $RC
}

check_replication_parameters_REQUIRE_RESTART=0
check_replication_parameters() {

  $PG_BIN_HOME/pg_isready -p $PG_PORT > /dev/null
  if [[ $? -gt 0 ]]; then
    return 1
  fi

  getp() {
    local param=$1
    local output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "select setting, context from pg_settings where name='${param}'" -t 2>&1 | tr -d " " )"
    echo $output
  }
  
  local setting=$(getp wal_level)
  local dbval=${setting//*:}
  local context=${setting//:*}
  if [[ $dbval == "minimal" ]]; then
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" wal_level "replica"
     [[ $context == "postmaster" ]] && check_replication_parameters_REQUIRE_RESTART=1
  fi
  setting=$(getp max_wal_senders)
  dbval=${setting//*:}
  context=${setting//:*}
  if [[ $dbval -lt 10 ]]; then
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_wal_senders "10"
     [[ $context == "postmaster" ]] && check_replication_parameters_REQUIRE_RESTART=1
  fi
  setting=$(getp max_replication_slots)
  dbval=${setting//*:}
  context=${setting//:*}
  if [[ $dbval -lt 10 ]]; then
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" max_replication_slots "10"
     [[ $context == "postmaster" ]] && check_replication_parameters_REQUIRE_RESTART=1
  fi
  setting=$(getp track_commit_timestamp)
  dbval=${setting//*:}
  context=${setting//:*}
  if [[ $dbval != "on" ]]; then
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" track_commit_timestamp "on"
     [[ $context == "postmaster" ]] && check_replication_parameters_REQUIRE_RESTART=1
  fi

}

get_param_value() {
  local param=$1
  local output="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "select name, context from pg_settings where name='$param'" -t 2>&1| tr -d " ")"
  echo $output
}


get_remote_vars() {
  local host=$1
  local output="$($SSH $host ". ~/.PGBASENV_HOME; . \$PGBASENV_BASE/bin/pgsetenv.sh --noscan; echo \$PGOPERATE_BASE")"
  local RC=$?
  if [[ $RC -eq 0 ]]; then
    REMOTE_PGOPERATE_BASE=$output
  fi
  return $RC
}



# Check if remote dir empty
check_remote_dir() {
    local host=$1
    local dir=$2
    local output=$($SSH $host "if [[ ! -d $dir ]]; then echo EMPTY; else [[ \"\$(ls -A /u00/pgbase/pg11 2>&1)\" ]] && echo NOT_EMPTY; fi")
    echo $output | grep -q NOT_EMPTY
    if [[ $? -eq 0 ]]; then
      return 1
    fi
}


check_local_dir() {
    local dir=$2
    local output=$([[ "$(ls -A $dir 2>&1)" ]] && echo NOT_EMPTY)
    echo $output | grep -q NOT_EMPTY
    if [[ $? -eq 0 ]]; then
      return 1
    fi
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



create_slave() {
   local MASTER_HOST=$1
   local MASTER_PORT=$2
   local RC

   check_replication_parameters

   $PGOPERATE_BASE/bin/control.sh stop >/dev/null
   #$PG_BIN_HOME/pg_ctl stop -D ${PGDATA} -s -m fast >/dev/null
   check_local_dir $PGDATA
   RC=$?
   if [[ $RC -gt 0 ]]; then
      rm -rf $PGDATA/*
   fi



   #echo "Copying data directory from $MASTER_HOST to the $PGSQL_BASE/data"
   export PGPASSWORD="$REPLICA_USER_PASSWORD"
   $PG_BIN_HOME/pg_basebackup --wal-method=stream -D $PGSQL_BASE/data -U replica -h $MASTER_HOST -p $MASTER_PORT -R
   if [[ ! $? -eq 0 ]]; then
      error "Duplicate from master site failed. Check output and PostgreSQL log files."
      return 1
   fi


   #echo "Updating pg_hba.conf file"
   update_pg_hba

   #echo "Starting slave."
   $PGOPERATE_BASE/bin/control.sh start force >/dev/null
   #$PG_BIN_HOME/pg_ctl start -D ${PGDATA} -l $PGSQL_BASE/log/server.log -s -o "-p ${PGPORT} --config_file=$PGSQL_BASE/etc/postgresql.conf" >/dev/null


   local conninfo
   if [[ $TVD_PGVERSION -ge 12 ]]; then
     [[ ! -z $BACKUP_LOCATION && $DISABLE_BACKUP_SCRIPTS == "no" ]] && set_conf_param "$PGSQL_BASE/etc/postgresql.conf" restore_command "'cp $BACKUP_LOCATION/*/wal/%f "%p" || cp $PGSQL_BASE/arch/%f "%p"'"
     conninfo=$(grep primary_conninfo $PGSQL_BASE/data/postgresql.auto.conf | grep -oE "'.+'" | tail -1)
     conninfo="$(eval "echo $conninfo") application_name=${INPUT_SLAVE_UNIQNAME}"
     #SET_CONF_PARAM_IN_CLUSTER="NO"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" primary_conninfo "'$conninfo'"
     #SET_CONF_PARAM_IN_CLUSTER="YES"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" primary_slot_name "'slot_${INPUT_SLAVE_UNIQNAME}'"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" recovery_target_timeline "'latest'"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" restore_command "'$RESTORE_COMMAND'"
     touch $PGSQL_BASE/data/standby.signal
   else
     [[ ! -z $BACKUP_LOCATION && $DISABLE_BACKUP_SCRIPTS == "no" ]] && echo "restore_command = 'cp $BACKUP_LOCATION/*/wal/%f "%p" || cp $PGSQL_BASE/arch/%f "%p"'" >> $PGSQL_BASE/data/recovery.conf
     conninfo=$(grep primary_conninfo $PGSQL_BASE/data/recovery.conf | grep -oE "'.+'" | tail -1)
     conninfo="$(eval "echo $conninfo") application_name=${INPUT_SLAVE_UNIQNAME}"
     set_conf_param "$PGSQL_BASE/data/recovery.conf" primary_conninfo "'$conninfo'"
     echo "primary_slot_name = 'slot_${INPUT_SLAVE_UNIQNAME}'" >> $PGSQL_BASE/data/recovery.conf
     echo "recovery_target_timeline = 'latest'" >> $PGSQL_BASE/data/recovery.conf
   fi

   $PG_BIN_HOME/pg_ctl reload -D ${PGDATA} -s

   echo "Standby created. Checking status ..."
   local i=0
   while [[ $i -le 15 ]]; do
     local replication_status=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "select status from pg_stat_wal_receiver;" -t | xargs)
     if [[ "$replication_status" == "streaming" ]]; then
       echo "Replication status is 'streaming'. Successful."
       return 0
     fi
     ((i++))
     sleep 1
   done
   
   error "Replication status is not streaming. Something wrong. Check server log files."
   return 1

}



prepare_master() {
  #local standby=$1
  local uniqname=$1

  if [[ -z $REPLICA_USER_PASSWORD ]]; then
    echo "ERROR: Set REPLICA_USER_PASSWORD in $PARAMETERS_FILE."
    return 1
  fi
  create_replica_user
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Check the error message from psql. Fix the issue and try again."
    return 1
  fi

  create_replication_slot $uniqname
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Failed to create replication slot. Check the error message from psql. Fix the issue and try again."
    return 1
  fi

  # Create replication slots for standbys
  local config="$(list_db list)"
  if [[ ! -z $config ]]; then
    while IFS= read -r line; do
       local db_standby=$(echo $line | cut -d'|' -f2)
       if [[ $(echo $line | cut -d'|' -f3) == "STANDBY" ]]; then
          create_replication_slot "$(db_get_uniqname $db_standby)"
       fi
    done <<< "$config"
  fi

  local RC1=0
  local RC2=0
  check_replication_parameters
  if [[ $check_replication_parameters_REQUIRE_RESTART -eq 1 ]]; then
    if [[ $FORCE -eq 1 ]]; then
       $PGOPERATE_BASE/bin/control.sh stop >/dev/null
       RC1=$?
       $PGOPERATE_BASE/bin/control.sh start force >/dev/null
       RC2=$?
    else
      echo "Cluster must be restarted."
      return 0
    fi
  fi

  return $((RC1+RC2))

}


switch_master() {
  local NEW_MASTER_UNIQNAME=$1
  
  local db_new_master=$(db_get_by_uniqname $NEW_MASTER_UNIQNAME)
  local NEW_MASTER_HOST=$(echo $db_new_master | cut -d"|" -f2)

  local master_conninfo=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "select setting from pg_settings where name='primary_conninfo'" 2>&1)
    if [[ ! -z $master_conninfo ]]; then
      local new_master_conninfo=$(echo $master_conninfo | sed "s/\(host=\)[^ ]* \(.*\)/\1$NEW_MASTER_HOST \2/g")
      echo "Switching master $NEW_MASTER_UNIQNAME to $NEW_MASTER_HOST on ${LOCAL_HOST}."
      $PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "alter system set primary_conninfo='$new_master_conninfo'" >/dev/null 2>&1
      $PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "select pg_reload_conf()" >/dev/null 2>&1
    fi

}


point_standbys_to_new_master() {
  local NEW_MASTER_UNIQNAME=$1
  local _config="$(list_db list)"

  if [[ ! -z $_config ]]; then
    while IFS= read -r line; do
       if [[ "$(echo $line | cut -d'|' -f3)" == "STANDBY" && "$(echo $line | cut -d'|' -f9)" != "$NEW_MASTER_UNIQNAME" ]]; then
          local standby=$(echo $line | cut -d'|' -f2)
          if [[ $(is_local_host $standby) == "NO" ]]; then
            execute_remote $standby $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --switch-master --master-uniqname $NEW_MASTER_UNIQNAME"
            local RC=$?
          else
            switch_master $NEW_MASTER_UNIQNAME
            local RC=$?
          fi
          if [[ $RC -gt 0 ]]; then
            echo "ERROR: Failed to switch master on host $standby."
            #return 1
          fi
          continue
       fi
    done < <(echo "$_config")
  fi

}

add_slave() {
  local STANDBY_UNIQNAME=$1
  local REMOTE_HOST=$2
  local RC MASTER_HOST

  create_repconf
  local db_master=$(db_get_master)
  if [[ ! -z $db_master ]]; then
    MASTER_HOST=$(echo $db_master | cut -d"|" -f2)
    [[ $(is_local_host $MASTER_HOST) == "NO" ]] && error "Must be executed on master site" && return 1
  else
    if [[ -z $INPUT_MASTER_UNIQNAME || -z $INPUT_MASTER_HOST ]]; then
       echo "ERROR: There is no master registered in repo, provide --master-uniqname and --master-host."
       return 1
    fi
    initialize_config
    MASTER_HOST=$INPUT_MASTER_HOST
  fi
  
  check_connection $REMOTE_HOST $MASTER_HOST
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Passwordless ssh connection check failed between hosts $MASTER_HOST and $REMOTE_HOST. Both directions must be configured."
    return 1
  fi

  execute_remote_noalias $REMOTE_HOST "cat \$PGBASENV_BASE/etc/pghometab | grep -q \";${TVD_PGHOME_ALIAS}\$\""
  if [[ $? -gt 0 ]]; then
    echo "ERROR: Alias ${TVD_PGHOME_ALIAS} not exists on ${REMOTE_HOST}."
    return 1
  fi


  local is_standby_exits=$(db_get_standby $STANDBY_UNIQNAME)
  if [[ ! -z $is_standby_exits ]]; then
     echo "ERROR: Standby with unique name $STANDBY_UNIQNAME already exists."
     return 1
  fi

  get_remote_vars $REMOTE_HOST
  RC=$?
  if [[ $RC -gt 0 || -z $REMOTE_PGOPERATE_BASE ]]; then
    echo "ERROR: Cannot get remote variables from $REMOTE_HOST. Check if romote host accessible and pgOperate installed on remote host."
    return 1
  fi
   
  prepare_master $STANDBY_UNIQNAME
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Failed to prepare for master role."
    return 1
  fi
  
  copy_params_file_to_remote
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Failed to copy $PARAMETERS_FILE to $REMOTE_HOST."
    return 1
  fi

  check_remote_dir $REMOTE_HOST $PGSQL_BASE
  RC=$?
  if [[ $RC -eq 0 ]]; then
    execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/create_cluster.sh --alias $PGBASENV_ALIAS --silent"
    RC=$?
    if [[ $RC -gt 0 ]]; then
      echo "ERROR: Failed to create cluster on $REMOTE_HOST."
      return 1
    fi
  fi

  execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --create-slave --uniqname $STANDBY_UNIQNAME --master-host $MASTER_HOST --master-port $PGPORT"
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Failed to create slave cluster on $REMOTE_HOST."
    return 1
  fi

  local db_standby=$(db_get_standby $STANDBY_UNIQNAME)
  if [[ -z $db_standby ]]; then
    db_add_standby $STANDBY_UNIQNAME $REMOTE_HOST
  fi
  echo "Synchronizing config with all standbys."
  db_copy_to_standbys

}



# Values for REWIND and DUPLICATE can be 0 or 1
reinstate() {
  local NEW_MASTER_UNIQNAME=$1
  local REWIND=$2
  local DUPLICATE=$3

  local db_master=$(db_get_master)
  local db_master_uniqname=$(echo $db_master | cut -d"|" -f4)
  
  local db_new_master=$(db_get_by_uniqname $NEW_MASTER_UNIQNAME)
  local NEW_MASTER_HOST=$(echo $db_new_master | cut -d"|" -f2)

  local REPLICATION_SLOT_NAME="slot_${db_master_uniqname}"

  on_exit() {
     local SET_AUTOSTART_TO=$1
     if [[ ! -z $SET_AUTOSTART_TO ]]; then
       set_autostart $SET_AUTOSTART_TO
     fi
  }

  if [[ $AUTOSTART =~ yes|YES ]]; then
     SET_AUTOSTART_TO=YES
     trap 'on_exit $SET_AUTOSTART_TO' EXIT
     set_autostart NO
  fi

  local PGPORT=$PGPORT
  [[ -z $PGPORT ]] && PGPORT=$PG_PORT

  check_master() {
    local recstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "SELECT pg_is_in_recovery()" 2>&1)
    if [[ $recstatus == "f" ]]; then
      echo "WARNING: This database cluster running in non-recovery mode. Stop it first to convert to standby."
      $PGOPERATE_BASE/bin/control.sh stop
    fi
  }

  prepare_for_standby(){
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" hot_standby "on"
     grep -q "#replication#" $PGSQL_BASE/etc/pg_hba.conf
     [[ $? -gt 0 ]] && echo -e "# For replication. Connect from remote hosts. #replication#\nhost    replication     replica      0.0.0.0/0      scram-sha-256" >> $PGSQL_BASE/etc/pg_hba.conf
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" primary_conninfo "'user=replica password=$REPLICA_USER_PASSWORD host=$NEW_MASTER_HOST port=$PGPORT application_name=${db_master_uniqname}'"
     set_conf_param "$PGSQL_BASE/data/postgresql.auto.conf" primary_conninfo "'user=replica password=$REPLICA_USER_PASSWORD host=$NEW_MASTER_HOST port=$PGPORT application_name=${db_master_uniqname}'"
     [[ ! -z $BACKUP_LOCATION && $DISABLE_BACKUP_SCRIPTS == "no" ]] && set_conf_param "$PGSQL_BASE/etc/postgresql.conf" restore_command "'cp $BACKUP_LOCATION/*/wal/%f "%p" || cp $PGSQL_BASE/arch/%f "%p"'"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" primary_slot_name "'${REPLICATION_SLOT_NAME}'"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" recovery_target_timeline "'latest'"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" restore_command "'$RESTORE_COMMAND'"
     touch $PGSQL_BASE/data/standby.signal 
  }

  create_recovery_file(){
    echo "
standby_mode = 'on'
primary_conninfo = 'user=replica password=''$REPLICA_USER_PASSWORD'' host=$NEW_MASTER_HOST port=$PGPORT application_name=${db_master_uniqname}'
primary_slot_name = '${REPLICATION_SLOT_NAME}'
recovery_target_timeline = 'latest'
" > $PGSQL_BASE/data/recovery.conf
[[ ! -z $BACKUP_LOCATION ]] && echo "restore_command = 'cp $BACKUP_LOCATION/*/wal/%f "%p" || cp $PGSQL_BASE/arch/%f "%p"'" >> $PGSQL_BASE/data/recovery.conf
chown $OS_USER:$OS_GROUP $PGSQL_BASE/data/recovery.conf
}

do_rewind(){

  # if [[ ! -z "$PG_SUPERUSER_PWDFILE" && -f "$SCRIPTDIR/$PG_SUPERUSER_PWDFILE" ]]; then
  #   chown $OS_USER:$OS_GROUP $SCRIPTDIR/$PG_SUPERUSER_PWDFILE
  #   chmod 0400 $SCRIPTDIR/$PG_SUPERUSER_PWDFILE
  #   PG_SUPERUSER_PWD="$(head -1 $SCRIPTDIR/$PG_SUPERUSER_PWDFILE | xargs)"
  # else
  #   error "Password file with superuser $PG_SUPERUSER password is required for pg_rewind.
  #   Create the password file in the same directory as $0 script and set PG_SUPERUSER_PWDFILE parameter in parameters.conf."
  #   exit 1
  # fi
   local RC1 RC2
   $PGOPERATE_BASE/bin/control.sh stop >/dev/null
   #$PG_BIN_HOME/pg_ctl stop -D ${PGDATA} -s -m fast >/dev/null
   RC1=$?
   $PG_BIN_HOME/pg_rewind --target-pgdata=$PGSQL_BASE/data --source-server="host=$NEW_MASTER_HOST port=$PGPORT user=$PG_SUPERUSER dbname=postgres connect_timeout=5" -P
   if [[ $TVD_PGVERSION -ge 12 ]]; then
     prepare_for_standby
   else
     create_recovery_file
   fi
   $PGOPERATE_BASE/bin/control.sh start force >/dev/null
   #$PG_BIN_HOME/pg_ctl start -D ${PGDATA} -l $PGSQL_BASE/log/server.log -s -o "-p ${PGPORT} --config_file=$PGSQL_BASE/etc/postgresql.conf" >/dev/null
   RC2=$?
   return $((RC1+RC2))
}

do_duplicate(){
  create_slave $NEW_MASTER_HOST $PGPORT
}


check_master


if [[ $REWIND -eq 1 ]]; then
  do_rewind
  sleep 5
  repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$NEW_MASTER_HOST%'")
  if [[ $repstatus == "streaming" ]]; then
        echo "WAL receiver in streaming mode."
        return 0
  else
        echo "CRITICAL: WAL receiver in not streaming."
        return 1
  fi

fi	


if [[ $DUPLICATE -eq 1 ]]; then
  do_duplicate
  sleep 5
  repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$NEW_MASTER_HOST%'")
  if [[ $repstatus == "streaming" ]]; then
        echo "WAL receiver in streaming mode."
        return 0
  else
        echo "CRITICAL: WAL receiver in not streaming. Manual intervention required"
        return 1
  fi

fi

pgsetenv $PGBASENV_ALIAS


#if [[ $TVD_PGIS_STANDBY == "YES" ]]; then
#  echo "Cluster was in standby mode."
#  echo "Staring the Cluster."
#  $PGOPERATE_BASE/bin/control.sh start
#  return $?

#elif [[ $TVD_PGIS_STANDBY != "YES" ]]; then

  if [[ $TVD_PGVERSION -ge 12 ]]; then
    prepare_for_standby
  else
    create_recovery_file
  fi
  $PGOPERATE_BASE/bin/control.sh start force
  #$PG_BIN_HOME/pg_ctl start -D ${PGDATA} -l $PGSQL_BASE/log/server.log -s -o "-p ${PGPORT} --config_file=$PGSQL_BASE/etc/postgresql.conf"
  [[ $? -gt 0 ]] && return 1
  sleep 5
  repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$NEW_MASTER_HOST%'")
  if [[ $repstatus == "streaming" ]]; then
     echo "WAL receiver in streaming mode."
	   echo "Reinstation complete."
     return 0
  else
     echo "WARNING: WAL receiver is not streaming. Will try to synchronize Master and Standby with pg_rewind."
     do_rewind
     sleep 5
     repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$NEW_MASTER_HOST%'")
     if [[ $repstatus == "streaming" ]]; then
        echo "WAL receiver in streaming mode."
		    echo "Reinstation complete."
        return 0
     elif [[ $FORCE -eq 1 ]]; then
        echo "WARNING: Force option -f specified!"
        echo "WARNING: WAL receiver is steel not streaming. Will try to recreate Standby from active Master."
        do_duplicate
	      sleep 5
        repstatus=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -At -c "select status from pg_stat_wal_receiver where conninfo like '%host=$NEW_MASTER_HOST%'")
        if [[ $repstatus == "streaming" ]]; then
           echo "WAL receiver in streaming mode."
		       echo "Reinstation complete."
           return 0
        else
           echo "WARNING: WAL receiver is steel not streaming. Manual action required."
           return 1
        fi

     else
         echo "WARNING: WAL receiver is steel not streaming. Manual action required."
         return 1
     fi

     echo "CRITICAL: WAL receiver is not streaming."
     echo "Standby is not applying. Check logfiles."
     return 1
  fi

#else
#  return 1
#fi


}





remove_host() {
  local UNIQNAME=$1
  local REMOTE_HOST
  local RC RC1 RC2

  if [[ ! -d $REPCONF ]]; then
     return 0
  fi

  local db_data=$(db_get_by_uniqname $UNIQNAME)
  local REMOTE_HOST=$(echo $db_data | cut -d"|" -f2)

  local db_master=$(db_get_master)
  local db_master_host=$(echo $db_master | cut -d"|" -f2)

  if [[ $(is_local_host $db_master_host) == "NO" ]]; then
     local force_mode
     [[ $FORCE -eq 1 ]] && force_mode="--force" || force_mode=""
     execute_remote $db_master_host $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --remove --target $UNIQNAME $force_mode"
     RC=$?
     return $RC   
  fi

  if [[ $(is_local_host $REMOTE_HOST) == "YES" ]]; then
     echo "Master host to be removed. All configuration will be deleted."
     local d
     shopt -s nocasematch
       for d in $(ls $REPCONF); do
         if [[ $(cat $REPCONF/$d/3_role) == "STANDBY" ]]; then
           execute_remote $(cat $REPCONF/$d/2_host) $PGBASENV_ALIAS "rm -Rf $REPCONF"
         fi
       done
     shopt -u nocasematch
     rm -Rf $REPCONF

  else
     echo "Standby host will be removed."
     db_remove_host $UNIQNAME
     RC1=$?
     execute_remote $REMOTE_HOST $PGBASENV_ALIAS "rm -Rf $REPCONF"
     RC2=$?
  fi

  $0 --sync-config
  
  return $((RC1+RC2))

}



add_host_to_sync_list() {
  local UNIQNAME=$1
  local RC1 RC2

  local final_list

     local current_list="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "show synchronous_standby_names" -t | xargs 2>&1)"

     if [[ -z $current_list ]]; then
        final_list="${UNIQNAME}"
     else
        current_list=$(eval "echo $current_list")
        if [[ ",${current_list}," =~ ,${UNIQNAME}, ]]; then
           final_list="${current_list}"
        else
           final_list="${current_list},${UNIQNAME}"
        fi
     fi
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" synchronous_commit "on"

  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" synchronous_standby_names "'$final_list'"
  RC1=$?
  $PG_BIN_HOME/pg_ctl reload -D ${PGDATA} -s
  RC2=$?

  return $((RC1+RC2))

}


rm_host_from_sync_list() {
  local UNIQNAME=$1

  local RC1 RC2
  local final_list="$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "select trim(regexp_replace(setting, '${UNIQNAME}(\$| *,)', ''),',') from pg_settings where name='synchronous_standby_names'" -t | xargs 2>&1)"

  set_conf_param "$PGSQL_BASE/etc/postgresql.conf" synchronous_standby_names "'$final_list'"
  RC1=$?
  $PG_BIN_HOME/pg_ctl reload -D ${PGDATA} -s
  RC2=$?

  return $((RC1+RC2))

}


set_syncasync() {
  local UNIQNAME=$1
  local RC1 RC2

  local db_data=$(db_get_by_uniqname $UNIQNAME)
  local REMOTE_HOST=$(echo $db_data | cut -d"|" -f2)

  local db_master=$(db_get_master)
  local db_master_host=$(echo $db_master | cut -d"|" -f2)

  local mode samode
  [[ $MODE == "SETASYNC" ]] && mode="--set-async" || mode="--set-sync"
  [[ $SYNCASYNC_MODE == "BIDIRECTIONAL" ]] && samode="--bidirectional" || samode=""

  if [[ $(is_local_host $db_master_host) == "NO" ]]; then
     execute_remote $db_master_host $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh $mode --target $UNIQNAME $samode"
     RC=$?
     return $RC
  fi

  local final_list
  
  if [[ $MODE == "SETSYNC" ]]; then
    
    add_host_to_sync_list $UNIQNAME
    RC1=$?

    if [[ $SYNCASYNC_MODE == "BIDIRECTIONAL" ]]; then
       set_local_uniqname
       execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --exec --payload \"add_host_to_sync_list $LOCAL_SITE_UNIQNAME\""
       RC2=$?
    fi

  else

    rm_host_from_sync_list $UNIQNAME
    RC1=$? 

    if [[ $SYNCASYNC_MODE == "BIDIRECTIONAL" ]]; then
       set_local_uniqname
       execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --exec --payload \"rm_host_from_sync_list $LOCAL_SITE_UNIQNAME\""
       RC2=$?
    fi

  fi

  [[ $RC1 -gt 0 ]] && echo "ERROR: Failed to set synchronous_standby_names on master site $LOCAL_SITE_UNIQNAME"
  [[ $RC2 -gt 0 ]] && echo "ERROR: Failed to set synchronous_standby_names on standby site $UNIQNAME"

  return $((RC1+RC2))
  
}


switchover_to() {
  local UNIQNAME=$1
  local RC MASTER_HOST STANDBY_HOST

  local db_master=$(db_get_master)
  local MASTER_HOST=$(echo $db_master | cut -d"|" -f2)

  # If current host is not master host, then command will be executed on the master
  if [[ $(is_local_host $MASTER_HOST) == "NO" ]]; then
     local force_mode
     [[ $FORCE -eq 1 ]] && force_mode="--force" || force_mode=""
     execute_remote $MASTER_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --switchover --target $UNIQNAME $force_mode"
     RC=$?
     return $RC   
  fi

  local db_standby=$(db_get_standby $UNIQNAME)
  if [[ -z $db_standby ]]; then
    error "No registered standby database with unique name $UNIQNAME"
    return 1
  fi
  STANDBY_HOST=$(echo $db_standby | cut -d"|" -f2)

  check_connection $STANDBY_HOST $MASTER_HOST
  RC=$?
  if [[ $RC -gt 0 ]]; then
    echo "ERROR: Passwordless ssh connection check failed between hosts $MASTER_HOST and $STANDBY_HOST. Both directions must be configured."
    return 1
  fi

  if [[ $TVD_PGIS_STANDBY == "YES" ]]; then
    error "Operation must be executed on master site"
    return 1
  fi

  echo "Stopping master."
  $PGOPERATE_BASE/bin/control.sh stop >/dev/null
  [[ $? -gt 0 ]] && error "Failed to stop master on $MASTER_HOST." && return 1

  echo "Getting master last checkpoint location and next XID."
  local master_ckpt_location=$($PG_BIN_HOME/pg_controldata | grep "Latest checkpoint location:" | cut -d: -f2 | xargs)
  local master_next_xid=$($PG_BIN_HOME/pg_controldata | grep "NextXID:" | cut -d: -f2,3 | xargs)
  master_next_xid=${master_next_xid//*:}

  local remote_is_standby=$(execute_remote $STANDBY_HOST $PGBASENV_ALIAS "echo \$TVD_PGIS_STANDBY")

  if [[ $remote_is_standby == "YES" ]]; then
    execute_remote $STANDBY_HOST $PGBASENV_ALIAS "psql -t -c \"CHECKPOINT\" > /dev/null"
    local standby_next_xid=$(execute_remote $STANDBY_HOST $PGBASENV_ALIAS "pg_controldata | grep "NextXID:" | cut -d: -f2,3 | xargs")
    standby_next_xid=${standby_next_xid//*:}
    local standby_transfer_lag=$(execute_remote $STANDBY_HOST $PGBASENV_ALIAS "psql -t -c \"select pg_wal_lsn_diff('$master_ckpt_location', pg_last_wal_receive_lsn())\" | xargs")
    local check_passed="YES"

    local xid_diff=$((master_next_xid-standby_next_xid))
    if [[ $xid_diff -gt 1 ]]; then
       echo "PROBLEM: Switchover can lead to data loss. Master next XID is $master_next_xid and standby XID is $standby_next_xid."
       check_passed="NO"
    fi

    if [[ $standby_transfer_lag -gt 0 ]]; then
       echo "PROBLEM: Switchover can lead to data loss. There is $standby_transfer_lag MB transfer lag between master and stadnby."
       check_passed="NO"
    fi

    if [[ $check_passed == "NO" ]]; then
       echo "Use failover. Now starting master again."
       $PGOPERATE_BASE/bin/control.sh start force >/dev/null
       return 1
    fi

    execute_remote $STANDBY_HOST $PGBASENV_ALIAS "\$TVD_PGHOME/bin/pg_ctl promote"
    [[ $? -gt 0 ]] && error "Failed to promote slave cluster on host $STANDBY_HOST." && return 1
    execute_remote $STANDBY_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --set-master --target $UNIQNAME"
    #execute_remote $STANDBY_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --sync-config"
  else
    echo "Remote is already promoted."
  fi

  execute_remote $STANDBY_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --prepare-master --target $UNIQNAME --force"
  RC=$?
  if [[ $RC -gt 0 ]]; then
    error "Failed to prepare for master role on host $STANDBY_HOST."
    return 1
  fi

  point_standbys_to_new_master $UNIQNAME 

  FORCE=1
  reinstate $UNIQNAME
  RC=$?
  

  $0 --sync-config

  
  #"cleanup orphan rep slots"

  rep_slot=$(exec_pg "select slot_name from pg_replication_slots where slot_name like('%$UNIQNAME%')" | xargs)
  res=$(exec_pg "select pg_drop_replication_slot('$rep_slot')")
  res2=$(execute_remote $STANDBY_HOST $PGBASENV_ALIAS "$PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PGPORT -d postgres -c \"select pg_drop_replication_slot('slot_$UNIQNAME')\" ")


  return $RC

}



reinstate_cluster() {
  local UNIQNAME=$1
  local RC

  local db_target=$(db_get_by_uniqname $UNIQNAME)

  if [[ -z $db_target ]]; then
     echo "ERROR: No cluster with unique name $UNIQNAME exists."
     return 1
  fi

  local TARGET_HOST=$(echo $db_target | cut -d"|" -f2)

  local db_master=$(db_get_master)
  local db_master_host=$(echo $db_master | cut -d"|" -f2)
  local db_master_uniqname=$(echo $db_master | cut -d"|" -f4)

  if [[ $(is_local_host $TARGET_HOST) == "NO" ]]; then
     execute_remote $TARGET_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --reinstate --target $UNIQNAME --force"
     RC=$?
     return $RC
  fi

  if [[ $(is_local_host $db_master_host) == "YES" ]]; then
       prepare_master $UNIQNAME
  else
       execute_remote $db_master_host $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --prepare-master --target $UNIQNAME"
  fi

  FORCE=1
  reinstate $db_master_uniqname
  RC=$?

  if [[ $RC -eq 0 ]]; then
    if [[ $(is_local_host $db_master_host) == "YES" ]]; then
       db_add_standby $UNIQNAME $TARGET_HOST
    else
       execute_remote $db_master_host $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --exec --payload \"db_add_standby $UNIQNAME $TARGET_HOST\""
    fi
  fi

  $0 --sync-config

  return $RC

}



failover_to() {
  local UNIQNAME=$1
  local RC MASTER_HOST STANDBY_HOST

  local db_data=$(db_get_by_uniqname $UNIQNAME)
  local REMOTE_HOST=$(echo $db_data | cut -d"|" -f2)

  local db_master=$(db_get_master)
  local db_master_host=$(echo $db_master | cut -d"|" -f2)
  local db_master_uniqname=$(echo $db_master | cut -d"|" -f4)

  #if [[ $db_master_host == $LOCAL_HOST && $FORCE -ne 1 ]]; then
  #   echo "Execute failover on one of the standby hosts or use --force option."
  #   return 1
  #fi

  if [[ $(is_local_host $REMOTE_HOST) == "NO" ]]; then
     execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --failover --target $UNIQNAME --force"
     RC=$?
     return $RC   
  fi

  local db_standby=$(db_get_standby $UNIQNAME)
  if [[ -z $db_standby ]]; then
    error "No registered standby database with unique name $UNIQNAME"
    return 1
  fi

  #if [[ $LOCAL_HOST != $REMOTE_HOST ]]; then
  #  check_connection
  #  RC=$?
  #  if [[ $RC -gt 0 ]]; then
  #    echo "ERROR: Passwordless ssh connection check failed between hosts $LOCAL_HOST and $REMOTE_HOST. Both directions must be configured."
  #    return 1
  #  fi
  #fi

  # Check master
  local master_info=$(execute_remote $db_master_host $PGBASENV_ALIAS "echo \$TVD_PGSTATUS:\$TVD_PGIS_STANDBY")
  RC=$?
  if [[ $RC -gt 0 ]]; then
     echo "Master not reachable."
  else
     if [[ ${master_info//:*} == "UP" && ${master_info//*:} != "YES" ]]; then
        echo "Shutting down master on $db_master_host."
        execute_remote $db_master_host $PGBASENV_ALIAS "$PGOPERATE_BASE/bin/control.sh stop > /dev/null"
     fi
  fi

  if [[ $(is_local_host $REMOTE_HOST) == "NO" ]]; then
    local remote_is_standby=$(execute_remote $REMOTE_HOST $PGBASENV_ALIAS "echo \$TVD_PGIS_STANDBY")
  else
    local remote_is_standby=$TVD_PGIS_STANDBY
  fi

  
  if [[ $remote_is_standby == "YES" ]]; then
    if [[ $(is_local_host $REMOTE_HOST) == "NO" ]]; then
       execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$TVD_PGHOME/bin/pg_ctl promote"
       [[ $? -gt 0 ]] && error "Failed to promote slave cluster on $REMOTE_HOST." && return 1
       execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --set-master --target $UNIQNAME"
       execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --set-reinstate --target $db_master_uniqname"
    else
       $TVD_PGHOME/bin/pg_ctl promote
       [[ $? -gt 0 ]] && error "Failed to promote slave cluster on $REMOTE_HOST." && return 1
       db_set_new_master $UNIQNAME
       db_set_to_reinstate $db_master_uniqname
    fi
  else
    echo "Remote is already promoted."
  fi

  if [[ $(is_local_host $REMOTE_HOST) == "NO" ]]; then
    execute_remote $REMOTE_HOST $PGBASENV_ALIAS "\$PGOPERATE_BASE/bin/standbymgr.sh --prepare-master --target $UNIQNAME --force"
    RC=$?
  else
    FORCE=1
    prepare_master $UNIQNAME
    RC=$?
  fi

  if [[ $RC -gt 0 ]]; then
    error "Failed to prepare for master role on $REMOTE_HOST."
    return 1
  fi

  point_standbys_to_new_master $UNIQNAME 
  
  $0 --sync-config

  return $RC

}



set_local_uniqname() {
    local list=$(list_db list)
    while IFS="|" read _ nameline statusline _ _ _ _ _ uniqnameline; do
        if [[ $(is_local_host $nameline) == "YES" ]]; then
            LOCAL_SITE_STATUS=$statusline
            LOCAL_SITE_UNIQNAME=$uniqnameline
            break
        fi
    done <<< "$(echo "$list")"
}


check_uniqname() {
  local uniqname=$1

  if [[ ${#uniqname} -le 16 ]]; then
     if [[ $uniqname =~ ^[a-z][a-z0-9]+$ ]]; then
        return 0
     fi
  fi
  return 1
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
 elif [[ "$1" == --force ]]; then FORCE=1 && shift
 elif [[ "$1" == --add-standby ]]; then MODE="ADD_SLAVE" && shift
 elif [[ "$1" == --remove ]]; then MODE="REMOVE_HOST" && shift
 elif [[ "$1" == --create-slave ]]; then MODE="CREATE_SLAVE" && shift
 elif [[ "$1" == --prepare-master ]]; then MODE="PREPARE_MASTER" && shift
 elif [[ "$1" == --status ]]; then MODE="SHOW_STATUS" && shift
 elif [[ "$1" == --show-uniqname ]]; then MODE="SHOW_UNIQNAME" && shift
 elif [[ "$1" == --list ]]; then SHOW_STATUS_MODE="list" && shift
 elif [[ "$1" == --get-local-status ]]; then MODE="GET_LOCAL_STATUS" && shift
 elif [[ "$1" == --local-status ]]; then MODE="SHOW_LOCAL_STATUS" && shift
 elif [[ "$1" == --sync-config ]]; then MODE="SYNC_CONFIG" && shift
 elif [[ "$1" == --set-master ]]; then MODE="SET_MASTER" && shift
 elif [[ "$1" == --set-reinstate ]]; then MODE="SET_REINSTATE" && shift
 elif [[ "$1" == --reinstate ]]; then MODE="REINSTATE" && shift
 elif [[ "$1" == --switchover ]]; then MODE="SWITCHOVER" && shift
 elif [[ "$1" == --set-async ]]; then MODE="SETASYNC" && shift
 elif [[ "$1" == --set-sync ]]; then MODE="SETSYNC" && shift
 elif [[ "$1" == --check ]]; then MODE="CHECK" && shift
 elif [[ "$1" == --failover ]]; then MODE="FAILOVER" && shift
 elif [[ "$1" == --bidirectional ]]; then SYNCASYNC_MODE="BIDIRECTIONAL" && shift
 elif [[ "$1" == --exec ]]; then MODE="EXEC" && shift
 elif [[ "$1" == --switch-master ]]; then MODE="SWITCH_MASTER" && shift
 elif [[ "$1" == --target ]]; then shift && ca $1 && INPUT_SLAVE_UNIQNAME=$1 && shift
 elif [[ "$1" == --uniqname ]]; then shift && ca $1 && INPUT_SLAVE_UNIQNAME=$1 && shift
 elif [[ "$1" == --host ]]; then shift && ca $1 && INPUT_SLAVE_HOST=$1 && shift
 elif [[ "$1" == --master-uniqname ]]; then shift && ca $1 && INPUT_MASTER_UNIQNAME=$1 && shift
 elif [[ "$1" == --master-host ]]; then shift && ca $1 && INPUT_MASTER_HOST=$1 && shift
 elif [[ "$1" == --master-port ]]; then shift && ca $1 && INPUT_MASTER_PORT=$1 && shift
 elif [[ "$1" == --payload ]]; then shift && ca $1 && INPUT_PAYLOAD=$1 && shift
 elif [[ "$1" == --remote-host ]]; then shift && ca $1 && REMOTE_HOST=$1 && shift
 elif [[ "$1" == --local-host ]]; then shift && ca $1 && LOCAL_HOST=$1 && shift
 
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


if [[ $MODE == "ADD_SLAVE" ]]; then

  if [[ -z $INPUT_SLAVE_HOST || -z $INPUT_SLAVE_UNIQNAME ]]; then
     echo "Error: Add slave mode requires --uniqname and --host arguments."
     exit 1
  fi
  
  if [[ ! -z $INPUT_SLAVE_UNIQNAME ]]; then
     if ! check_uniqname $INPUT_SLAVE_UNIQNAME; then
        echo "ERROR: Uniqname $INPUT_SLAVE_UNIQNAME is not eligible. Uniqname must be only small letters and numbers, start with letter and not longer than 16 characters."
        exit 1
     fi
  fi

  if [[ ! -z $INPUT_MASTER_UNIQNAME ]]; then
     if ! check_uniqname $INPUT_MASTER_UNIQNAME; then
        echo "ERROR: Uniqname $INPUT_MASTER_UNIQNAME is not eligible. Uniqname must be only small letters and numbers, start with letter and not longer than 16 characters."
        exit 1
     fi
  fi

  add_slave $INPUT_SLAVE_UNIQNAME $INPUT_SLAVE_HOST
  RC=$?


elif [[ $MODE == "EXEC" ]]; then

  if [[ -z $INPUT_PAYLOAD ]]; then
     echo "Error: Exec mode requires --payload arguments."
     exit 1
  fi
  eval "$INPUT_PAYLOAD"
  RC=$?


elif [[ $MODE == "CHECK" ]]; then

  if [[ -z $REMOTE_HOST ]]; then
     echo "Error: Check mode requires --remote-host argument."
     exit 1
  fi

  if [[ -z $INPUT_MASTER_HOST ]]; then
     echo "Master host will be localhost ${LOCAL_HOST}."
  fi
  
  #check_connection $INPUT_SLAVE_HOST $INPUT_MASTER_HOST
  check_connection $REMOTE_HOST $LOCAL_HOST 

  RC=$?
  if [[ $RC -eq 0 ]]; then
    echo "Success."
  else
    echo "Check failed."
  fi

elif [[ $MODE == "REMOVE_HOST" ]]; then

  if [[ -z $INPUT_SLAVE_UNIQNAME ]]; then
     set_local_uniqname
     INPUT_SLAVE_UNIQNAME=$LOCAL_SITE_UNIQNAME
  fi
  remove_host $INPUT_SLAVE_UNIQNAME
  RC=$?


elif [[ $MODE == "CREATE_SLAVE" ]]; then

  if [[ -z $INPUT_MASTER_HOST || -z $INPUT_MASTER_PORT ]]; then
     echo "Error: Create slave mode requires --master-host and --master-port arguments."
     exit 1
  fi
  create_slave $INPUT_MASTER_HOST $INPUT_MASTER_PORT
  RC=$?

elif [[ $MODE == "PREPARE_MASTER" ]]; then

  if [[ -z $INPUT_SLAVE_UNIQNAME ]]; then
     set_local_uniqname
     if [[ -z $LOCAL_SITE_UNIQNAME ]]; then
        echo "Error: Prepare master mode requires --target <uniqname> argument, but cant identify uniqname of local site."
        exit 1
     else
        INPUT_SLAVE_UNIQNAME=$LOCAL_SITE_UNIQNAME
     fi
  fi
  prepare_master $INPUT_SLAVE_UNIQNAME
  RC=$?


elif [[ $MODE == "SWITCHOVER" ]]; then

  if [[ -z $INPUT_SLAVE_UNIQNAME ]]; then
     set_local_uniqname
     if [[ -z $LOCAL_SITE_UNIQNAME ]]; then
        echo "Error: Switchover mode requires --target <uniqname> argument, but cant identify uniqname of local site."
        exit 1
     else
        INPUT_SLAVE_UNIQNAME=$LOCAL_SITE_UNIQNAME
     fi
  fi
  switchover_to $INPUT_SLAVE_UNIQNAME
  RC=$?

elif [[ $MODE == "SETASYNC" || $MODE == "SETSYNC" ]]; then

  if [[ -z $INPUT_SLAVE_UNIQNAME ]]; then
     set_local_uniqname
     if [[ -z $LOCAL_SITE_UNIQNAME ]]; then
       echo "Error: This mode requires --target <uniqname> argument, but cant identify uniqname of local site."
       exit 1
     else
       INPUT_SLAVE_UNIQNAME=$LOCAL_HOST
     fi
  fi
  set_syncasync $INPUT_SLAVE_UNIQNAME
  RC=$?

elif [[ $MODE == "FAILOVER" ]]; then

  if [[ -z $INPUT_SLAVE_UNIQNAME ]]; then
     set_local_uniqname
     if [[ -z $LOCAL_SITE_UNIQNAME ]]; then
        echo "Error: This mode requires --target <uniqname> argument, but cant identify uniqname of local site."
        exit 1
     else
        INPUT_SLAVE_UNIQNAME=$LOCAL_SITE_UNIQNAME
     fi
  fi
  failover_to $INPUT_SLAVE_UNIQNAME
  RC=$?

elif [[ $MODE == "REINSTATE" ]]; then

  if [[ -z $INPUT_SLAVE_UNIQNAME ]]; then
     set_local_uniqname
     if [[ -z $LOCAL_SITE_UNIQNAME ]]; then
        echo "Error: Reinstate mode requires --target <uniqname> argument, but cant identify uniqname of local site."
        exit 1
     else
        INPUT_SLAVE_UNIQNAME=$LOCAL_SITE_UNIQNAME
     fi
  fi

  reinstate_cluster $INPUT_SLAVE_UNIQNAME
  RC=$?


elif [[ $MODE == "SHOW_STATUS" ]]; then

  list_db $SHOW_STATUS_MODE
  RC=$?

elif [[ $MODE == "SHOW_UNIQNAME" ]]; then

  set_local_uniqname
  RC=$?
  echo $LOCAL_SITE_UNIQNAME

elif [[ $MODE == "SYNC_CONFIG" ]]; then

  sync_config
  RC=$?

elif [[ $MODE == "SET_MASTER" ]]; then

  if [[ -z $INPUT_SLAVE_UNIQNAME ]]; then
     set_local_uniqname
     if [[ -z $LOCAL_SITE_UNIQNAME ]]; then
        echo "Error: Set master mode requires --target <uniqname> argument, but cant identify uniqname of local site."
        exit 1
     else
        INPUT_SLAVE_UNIQNAME=$LOCAL_SITE_UNIQNAME
     fi
  fi

  db_set_new_master $INPUT_SLAVE_UNIQNAME
  RC=$?

elif [[ $MODE == "SET_REINSTATE" ]]; then
  
  if [[ -z $INPUT_SLAVE_UNIQNAME ]]; then
     set_local_uniqname
     if [[ -z $LOCAL_SITE_UNIQNAME ]]; then
        echo "Error: Set reinstate mode requires --target <uniqname> argument, but cant identify uniqname of local site."
        exit 1
     else
        INPUT_SLAVE_UNIQNAME=$LOCAL_SITE_UNIQNAME
     fi
  fi

  db_set_to_reinstate $INPUT_SLAVE_UNIQNAME
  RC=$?

elif [[ $MODE == "GET_LOCAL_STATUS" ]]; then

  get_actual_status
  RC=$?

elif [[ $MODE == "SHOW_LOCAL_STATUS" ]]; then

  show_actual_status
  RC=$?

elif [[ $MODE == "SWITCH_MASTER" ]]; then

  if [[ -z $INPUT_MASTER_UNIQNAME ]]; then
     echo "Error: Switch master mode requires --master-uniqname argument, but cant identify uniqname of local site."
     exit 1
  fi
  switch_master $INPUT_MASTER_UNIQNAME
  RC=$?

fi


exit $RC

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}

