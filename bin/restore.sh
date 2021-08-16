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


help() {
echo "
 Script to restore PostgreSQL cluster backup made by backup.sh.

 Script uses PGSQL_BASE and variables in Backup section from $PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf file.

 Script can be executed without any parameters. In this case it will restore from the latest available backup.

 Arguments:
    list                        - Script will list the contents of the BACKUP_LOCATION.
    backup_dir=<directory>      - One time backup location. Will be used as restore source.
    from_subdir=<subdir>        - Execute restore from specified sub-directory number. Use 'list' to check all sub directory numbers. It must be number without date part.
    until_time=<date and time>  - To execute Point in Time recovery. Specify target time. Time must be in \"YYYY-MM-DD HH24:MI:SS\" format.
    pause                       - Will set recovery_target_action to pause in recovery.conf or postgresql.conf. When Point In Time will be reached, recovery will pause.
    shutdown                    - Will set recovery_target_action to shutdown in recovery.conf or postgresql.conf. When Point In Time will be reached, database will shutdown.
    verify                      - If this argument specified, then no actual restore will be execute. Use to check which subfolder will be used to restore.

 Examples:
  Restore from last (Current) backup location:
    $0

  Restore from subdirectory 3:
    $0 from_subdir=3

  First verify then restore to Point in Time \"2018-10-17 11:25:00\":
    $0 until_time=\"2018-10-17 11:25:00\" verify
    $0 until_time=\"2018-10-17 11:25:00\"

"

}

# Set custom .psqlrc file
export PSQLRC=$PGOPERATE_BASE/bin/.psqlrc

OS_USER=$(id -un)
OS_GROUP=$(id -gn)

declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"

[[ -z $PGBASENV_ALIAS ]] && error "Set the alias for the current cluster first." && exit 1
echo -e "\nCurrent cluster: ${PGBASENV_ALIAS}"

[[ -z $PGBASENV_ALIAS ]] && error "PG_BIN_HOME is not defined. Set the environment for cluster home."
PG_BIN_HOME=$TVD_PGHOME/bin


PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf
[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
source $PARAMETERS_FILE
[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PGOPERATE_BASE/lib/shared.lib

if [[ $DISABLE_BACKUP_SCRIPTS == "yes" ]]; then
  echo "INFO: Backup/recovery disabled by DISABLE_BACKUP_SCRIPTS variable."
  exit 0
fi

# Define log file
prepare_logdir
declare -r LOGFILE="$PGSQL_BASE/log/tools/$(basename $0)_$(date +"%Y%m%d_%H%M%S").log"


declare -r RECENT_WAL_LOCATION=/tmp/recent_pg_wal


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


get_curr_backup_loc() {
local backups=$(ls $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$")
local d md mdir
md=0
if [[ ! -z $backups ]]; then
 for bdir in $(ls -1 $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$" | sort); do
   d="$(grep full_backup_time $BACKUP_LOCATION/$bdir/meta.info | cut -s -d"=" -f2)"
   d=$(eval "echo $d")
   d=$(date --date="${d}" +%s)
   [[ $d -gt $md ]] && md=$d && mdir=$bdir
 done
   MAX_DATE=$md
   CURR_BACKUP_DIR=$BACKUP_LOCATION/$mdir
else
 error "No full backups found, take full backup first." && exit 1
fi
}


getuntildir() {
local untiltime=$1
local backups=$(ls $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$")
untiltime=$(date -d "$untiltime" +%s)
get_curr_backup_loc
local step=1
local c=0
local i a b
local -a arr
local -a arrdir
i=0
if [[ ! -z $backups ]]; then

 local alldirs=$(
 {
 for bdir in $(ls -1 $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$"); do
   d="$(grep full_backup_time $BACKUP_LOCATION/$bdir/meta.info | cut -s -d"=" -f2)"
   d=$(eval "echo $d")
   d=$(date --date="${d}" +%s)
   echo "$d:$bdir"
 done
 } | sort -u )


 for bdir in $alldirs; do
   arr[$i]=${bdir//:*}
   arrdir[$i]=${bdir//*:}
   (( i++ ))
 done
else
 error "No full backups found, take full backup first." && exit 1
fi

local restoredir
local arrcnt=${#arr[@]}
i=0
while [ $i -le $arrcnt ]; do
  if [[ $i -eq $(( arrcnt-1 )) ]]; then
    [[ $untiltime -gt ${arr[$i]} && $untiltime -lt ${arr[0]} ]] && restoredir=${arrdir[$i]}
  else
    [[ $untiltime -gt ${arr[$i]} && $untiltime -lt ${arr[$(( i+1 ))]} ]] && restoredir=${arrdir[$i]}
  fi
  (( i++ ))
done

unset UNTIL_DIR
if [[ -z $restoredir ]]; then
  [[ $untiltime -gt $MAX_DATE ]] && UNTIL_DIR=$CURR_BACKUP_DIR
else
  UNTIL_DIR=$BACKUP_LOCATION/$restoredir
fi

}


restoreme() {
[[ "$verify" = "yes" ]] && info "In verify mode. Nothing done." && return 0
local backupdir=$1
local untiltime="$2"
local tmpdir="/tmp/pgrestore_pg_wal"

printheader "Stopping database cluster."
#local current_wal=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -c "SELECT file_name from pg_walfile_name_offset(pg_current_wal_lsn());" -t | xargs)
$PGOPERATE_BASE/bin/control.sh stop
[[ $? -gt 0 ]] && exit 1

if [[ ! -d $PGSQL_BASE/data ]]; then
  info "Directory $PGSQL_BASE/data doesn't exist. Will be created."
  mkdir -p $PGSQL_BASE/data
  chown $OS_USER:$OS_GROUP $PGSQL_BASE/data
  chmod 0700 $PGSQL_BASE/data
fi

if [[ ! -d $RECENT_WAL_LOCATION && -d $PGSQL_BASE/data/pg_wal ]]; then
printheader "Copying current WALs to $tmpdir."
mkdir -p $tmpdir
chown $OS_USER:$OS_GROUP $tmpdir
#cp -p $PGSQL_BASE/data/pg_wal/* $tmpdir/
find $PGSQL_BASE/data/pg_wal -maxdepth 1 -type f -exec cp -t $tmpdir {} +
fi

if [[ $(test -d $PGSQL_BASE/data/pg_replslot && ls -1 $PGSQL_BASE/data/pg_replslot | wc -l) -gt 0 ]]; then
   cp -rp $PGSQL_BASE/data/pg_replslot /tmp/
fi

printheader "Clearing $PGSQL_BASE/data directory."
rm -rf $PGSQL_BASE/data/*

printheader "Restoring data from $backupdir to $PGSQL_BASE/data."
tar -xpf $backupdir/data/base.tar.gz -C $PGSQL_BASE/data
[[ -f $PGSQL_BASE/data/recovery.done ]] && rm -f $PGSQL_BASE/data/recovery.done
rm -Rf $PGSQL_BASE/data/pg_wal/*

if [[ -d /tmp/pg_replslot ]]; then
   cp -rp /tmp/pg_replslot $PGSQL_BASE/data/
fi

printheader "Restoring WALs to the $PGSQL_BASE/data/pg_wal."
tar -xpf $backupdir/data/pg_wal.tar.gz -C $PGSQL_BASE/data/pg_wal
chown -R $OS_USER:$OS_GROUP $PGSQL_BASE/data/pg_wal

if [[ -d $RECENT_WAL_LOCATION ]]; then
printheader "Copying current WALs to the $PGSQL_BASE/data/pg_wal from $RECENT_WAL_LOCATION."
chown -R $OS_USER:$OS_GROUP $RECENT_WAL_LOCATION
cp -p $RECENT_WAL_LOCATION/* $PGSQL_BASE/data/pg_wal
local tmpdir=$RECENT_WAL_LOCATION
else
printheader "Copying current WALs to the $PGSQL_BASE/data/pg_wal."
cp -p $tmpdir/* $PGSQL_BASE/data/pg_wal
fi

if [[ -f $PGSQL_BASE/data/tablespace_map && $(cat $PGSQL_BASE/data/tablespace_map | wc -l) -gt 0 ]]; then
  printheader "Restoring externally stored tablespaces."
  while read oid tbs_path; do
    info "Preparing $tbs_path directory."
    [[ -d $tbs_path ]] && rm -rf $tbs_path/* || mkdir -p $tbs_path && chown $OS_USER:$OS_GROUP $tbs_path
    info "Restoring tablespace OID $oid."
    tar -xpf $backupdir/data/$oid.tar.gz -C $tbs_path
  done <$PGSQL_BASE/data/tablespace_map

fi

if [[ $TVD_PGVERSION -ge 12 ]]; then 
   printheader "Updating $PGSQL_BASE/etc/postgresql.conf."
   if [[ ! -z $untiltime ]]; then
      set_conf_param "$PGSQL_BASE/etc/postgresql.conf" recovery_target_time "'$untiltime'"
   else
      set_conf_param "$PGSQL_BASE/etc/postgresql.conf" recovery_target_time "''"
   fi
   set_conf_param "$PGSQL_BASE/etc/postgresql.conf" restore_command "'cp $BACKUP_LOCATION/*/wal/%f "%p" || cp $PGSQL_BASE/arch/%f "%p"'"

   if [[ "$do_pause" == "yes" ]]; then
    set_conf_param "$PGSQL_BASE/etc/postgresql.conf" recovery_target_action "'pause'"
   elif [[ "$do_shutdown" == "yes" ]]; then
    set_conf_param "$PGSQL_BASE/etc/postgresql.conf" recovery_target_action "'shutdown'"
   else
    set_conf_param "$PGSQL_BASE/etc/postgresql.conf" recovery_target_action "'promote'"
   fi   
   touch $PGSQL_BASE/data/recovery.signal

else
   printheader "Creating $PGSQL_BASE/recovery.conf."
   [[ ! -z $untiltime ]] && local untiltimeline="recovery_target_time = '$untiltime'" || local untiltimeline=""
   echo "restore_command = 'cp $BACKUP_LOCATION/*/wal/%f "%p" || cp $PGSQL_BASE/arch/%f "%p"'
$untiltimeline
recovery_end_command = 'rm -rf $tmpdir && rm -rf /tmp/pg_replslot'" > $PGSQL_BASE/data/recovery.conf

   if [[ "$do_pause" == "yes" ]]; then
    echo "recovery_target_action=pause" >> $PGSQL_BASE/data/recovery.conf
   elif [[ "$do_shutdown" == "yes" ]]; then
    echo "recovery_target_action=shutdown" >> $PGSQL_BASE/data/recovery.conf
   else
    echo "recovery_target_action=promote" >> $PGSQL_BASE/data/recovery.conf
   fi
   chown $OS_USER:$OS_GROUP $PGSQL_BASE/data/recovery.conf

fi

printheader "Starting database cluster to process recovery."
$PGOPERATE_BASE/bin/control.sh start
[[ $? -gt 0 ]] && exit 1

echo -e
echo "Done success."
echo -e
}


check_backup_source() {
  local backup_location=$1
  local source=$(tar -xf $backup_location/base.tar.gz backup_label -O | grep "BACKUP FROM:" | cut -d":" -f2 | xargs)
  if [[ "$source" == "standby" ]]; then
     info "Backup source is standby database. Please consider following, if database must be restored up to the failure time, to the most recent state,"
     info "then copy WAL files from standbys pg_wal location to $RECENT_WAL_LOCATION directory. Note that after restore operation, this directory will be removed."
     info "Script will copy them to pg_wal before restore operation."
     read -p "Press enter to continue or CTRL-C to cancel now."
  fi
}



if [[ ${#@} -gt 0 ]]; then
 for arg in "$@"; do
   pattern=" +${arg%%=*} +"
   [[ ! " list backup_dir verify from_subdir until_time pause shutdown -h help " =~ $pattern ]] && error "Bad argument $arg" && help && exit 1
 done
fi


######## MAIN #######################################


# Script main part begins here. Everything in curly braces will be logged in logfile
{


echo "Command line arguments: $@" >> $LOGFILE
echo "Current user id: $(id)" >> $LOGFILE
echo "--------------------------------------------------------------------------------------------------------------------------------" >> $LOGFILE
echo -e >> $LOGFILE




for arg in "$@"
do
 [[ "$arg" == "list" ]] && list_backup_dir && exit 0
 [[ "$arg" == "verify" ]] && verify="yes"
 [[ "$arg" == "pause" ]] && do_pause="yes"
 [[ "$arg" == "shutdown" ]] && do_shutdown="yes"
 [[ "$arg" =~ from_subdir=.+ ]] && FROM_DIR=$( echo $arg | cut -s -d"=" -f2 | xargs)
 [[ "$arg" =~ until_time=.+ ]] && UNTIL_TIME=$( echo $arg | cut -s -d"=" -f2 | xargs)
 [[ "$arg" =~ backup_dir=.+ ]] && BACKUP_LOCATION=$( echo $arg | cut -s -d"=" -f2 | xargs) && CMD_LINE_LOCATION=true
 [[ "$arg" =~ -h|help ]] && help && exit 0
done


if [[ ! -z $FROM_DIR && ! -z $UNTIL_TIME ]]; then
  error "Both parameters specified 'from_subdir' and 'until_time'. Only one of them can be specified."
  exit 1
fi

if [[ "$do_pause" == "yes" && "$do_shutdown" == "yes" ]]; then
  error "Both parameters specified 'pause' and 'shutdown'. Only one of them can be specified."
  exit 1
fi

if [[ ! -d $BACKUP_LOCATION ]]; then
  error "Backup directory $BACKUP_LOCATION not exist."
  exit 1
fi


[[ -z $PGSQL_BASE ]] && error "PGSQL_BASE variable is not defined!" && exit 1

echo -e
info "PGSQL_BASE = $PGSQL_BASE"

get_curr_backup_loc


FROM_DIR=$(ls -1d $BACKUP_LOCATION/$FROM_DIR-* 2>&1 | grep -oE "[0-9]+-[0-9]+$")


if [[ ! -z $FROM_DIR ]]; then
  [[ ! -d $BACKUP_LOCATION/$FROM_DIR ]] && error "Directory $BACKUP_LOCATION/$FROM_DIR-YYYYMMDD not exist!" && exit 1
  info "Database cluster will be restored from backup dir = $BACKUP_LOCATION/$FROM_DIR"
  check_backup_source $BACKUP_LOCATION/$FROM_DIR/data
  restoreme $BACKUP_LOCATION/$FROM_DIR
  if [[ ! "$BACKUP_LOCATION/$FROM_DIR" == "$CURR_BACKUP_DIR" ]]; then
    echo -e "\n!!! YOU EXECUTED RESTORE FROM NON-CURRENT BACKUP DIRECTORY. YOU MUST TAKE FRESH BACKUP NOW. !!!\n"
    echo -e "!!! ALL STANDBY DATABASES MUST BE RECREATED !!!\n"

  fi
elif [[ ! -z $UNTIL_TIME ]]; then
  info "Until time specified: $(date -d "$UNTIL_TIME")"
  [[ $? -gt 0 ]] && error "Please specify time in unix format YYYY-MM-DD HH24:MI:SS" && exit 1
  getuntildir "$UNTIL_TIME"
  [[ -z $UNTIL_DIR ]] && error "Cannot find matching backup directory!" && exit 1
  info "Database cluster will be restored from backup dir = $UNTIL_DIR"
  check_backup_source $UNTIL_DIR/data
  restoreme $UNTIL_DIR "$UNTIL_TIME"
  if [[ ! "$UNTIL_DIR" == "$CURR_BACKUP_DIR" ]]; then
    echo -e "\n!!! YOU EXECUTED RESTORE FROM NON-CURRENT BACKUP DIRECTORY. YOU MUST TAKE FRESH BACKUP NOW. !!!\n"
    echo -e "!!! ALL STANDBY DATABASES MUST BE RECREATED !!!\n"

  fi
else
  info "Database cluster will be restored from current backup dir = $CURR_BACKUP_DIR"
  check_backup_source $CURR_BACKUP_DIR/data
  restoreme $CURR_BACKUP_DIR
fi


if [[ "$CMD_LINE_LOCATION" == true ]]; then
   info "You restored from non-default backup location. Consider to take fresh backup if it is production system."
fi

echo -e "\nLogfile of this execution: $LOGFILE\n"
exit 0

} 2>&1 | tee -a $LOGFILE

exit ${PIPESTATUS[0]}
