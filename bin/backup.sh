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
# Script to backup PostgreSQL cluster.
#  Created on 07.2019 by Aychin Gasimov
#
# Change log:
#   06.07.2020: Aychin: Initial version created



#
#
# Script uses PGSQL_BASE and variables in Backup section from parameters_<alias>.conf file, which is in $PGOPERATE_BASE/etc directory.
#
# Arguments:
#         list  -  Script will list the contents of the BACKUP_LOCATION.
#  enable_arch  -  Sets the database cluster into archive mode. Archive location will be set to PGSQL_BASE/arch. No backup will taken.
#  backup_dir=<directory>  -  One time backup location. Archive log location will not be switched on this destination.
#                             Spare backup location $PGSQL_BASE/arch will not be maintained.
#
# To make backup, execute without any arguments.
#
# Backup strategy:
#
# Script will create (if not exist) BACKUP_LOCATION directory. This will be base for backups.
# It will check if cluster in archive mode or not. If not it will set it to "on" and RESTART the cluster.
#
# Script will maintain number of backups to retain automatically. The number of backups to retain
# defined in variable BACKUP_REDUNDANCY. If it set to 3, for example, then 3 full backups will be kept.
# If backups done every day, then 3 day backups always in place.
#
# If no BACKUP_REDUNDANCY specified then default value 7 will be used.
#
# The directory structure of BACKUP_LOCATION is as so:
#
# BACKUP_LOCATION
#             |
#             --- 1-YYYYMMDD
#             |   |
#             |   -- meta.info
#             |   |
#             |   -- data
#             |   |
#             |   -- wal
#             |
#             --- 2-YYYYMMDD
#             |   |
#             |   -- meta.info
#             |   |
#             |   -- data
#             |   |
#             |   -- wal
#             |
#             .
#             .
#
#  Script will maintain and recycle these directories automatically according to BACKUP_REDUNDANCY defined.
#  Each time backup.sh executed, it will identify correct directory to make backup. It will then
#  update archive_command parameter of the PostgreSQL cluster to redirect archived WALs to this directory.
#  Until next full backup, WALs will be archived to the last full backup subdirectory under BACKUP_LOCATION/n/wal.
#  If it will fail to archive into BACKUP_LOCATION/n-YYYYMMDD/wal directory then PGSQL_BASE/arch directory will be tried.
#  During restore, the source for the WALs will be first BACKUP_LOCATION/n-YYYYMMDD/wal and then PGSQL_BASE/arch.
#
#  PGSQL_BASE/arch used as spare location if for example BACKUP_LOCATION located on NFS and is not accessible, then
#  archive will continue into PGSQL_BASE/arch until NFS will be available again.
#
#  PGSQL_BASE/arch will be maintained by backup.sh after each backup operations, any WAL files not required by any
#  of the available backups will be deleted from it.
#
#  meta.info file contains full_backup_time variable. This variable defines the time when this backup was taken.
#  This file very important to identify correct location to make full backup.
#
#  !!! Never modify BACKUP_LOCATION directory manually. !!!
#

declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"
declare -r PARAMETERS=parameters.conf


[[ -z $PGBASENV_ALIAS ]] && error "Set the alias for the current cluster first." && exit 1
echo -e "\nCurrent cluster: ${PGBASENV_ALIAS}"

[[ -z $PGBASENV_ALIAS ]] && error "PG_BIN_HOME is not defined. Set the environment for cluster home."
PG_BIN_HOME=$TVD_PGHOME/bin


PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf

[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PARAMETERS_FILE
source $PGOPERATE_BASE/lib/shared.lib



# Default port
[[ -z $PG_PORT ]] && PG_PORT=5432


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


help() {

echo "
Arguments:
                     list -  Script will list the contents of the BACKUP_LOCATION.
              enable_arch -  Sets the database cluster into archive mode. Archive location will be set to PGSQL_BASE/arch.
                             No backup will taken. Cluster will be restarted!
  backup_dir=<directory>  -  One time backup location. Archive log location will not be switched on this destination.

 To make backup, execute without any arguments.

"

}




create_backup_dir() {
local bdir=$1
mkdir -p $bdir
chown postgres:postgres $bdir
touch $bdir/meta.info
chown postgres:postgres $bdir/meta.info
mkdir -p $bdir/data
chown postgres:postgres $bdir/data
mkdir -p $bdir/wal
chown postgres:postgres $bdir/wal
}

list_backup_dir() {
echo -e "\nBackup location: $BACKUP_LOCATION"
local backups=$(ls $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$")
local d md cnt mdir mid midir
cnt=0
md=0
mid=$(date +"%s")
if [[ ! -z $backups ]]; then
 for bdir in $(ls -1 $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$" | sort -h); do
   d="$(grep full_backup_time $BACKUP_LOCATION/$bdir/meta.info | cut -s -d"=" -f2)"
   d=$(eval "echo $d")
   d=$(date --date="${d}" +%s)
   [[ $d -gt $md ]] && md=$d && mdir=$bdir
   [[ $d -lt $mid ]] && mid=$d && midir=$bdir
 done
 local note nwals bsize wsize
 local delimiter="$(printf '%0.1s' ={1..73})"
 printf "%s\n" "$delimiter"
 printf "|%7s|%20s|%10s|%15s|%15s|\n" "Sub Dir" "Backup created" "WALs count" "Backup size(MB)" "WALs size(MB)"
 printf "%s\n" "$delimiter"
 for bdir in $(ls -1 $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$" | sort -h); do
   (( cnt++ ))
   d="$(grep full_backup_time $BACKUP_LOCATION/$bdir/meta.info | cut -s -d"=" -f2)"
   d=$(eval "echo $d")
   nwals=$(ls -1 $BACKUP_LOCATION/$bdir/wal | grep -v "\." | wc -l)
   bsize=$(du -sm $BACKUP_LOCATION/$bdir/data | awk '{print $1}' | xargs)
   wsize=$(du -sm $BACKUP_LOCATION/$bdir/wal  | awk '{print $1}' | xargs)
   if [[ "$midir" == "$mdir" ]]; then
     note=" <--- Current backup dir"
   elif [[ "$bdir" == "$midir" ]]; then
     note=" <--- Oldest backup dir"
   elif [[ "$bdir" == "$mdir" ]]; then
     note=" <--- Current backup dir"
   else
     note=""
   fi
   printf "|%7d|%20s|%10d|%15d|%15d|%-25s\n" "${bdir//-*}"   "$d"   "$nwals"  "$bsize"  "$wsize"  "$note"
 done
 printf "%s\n" "$delimiter"
 echo -e "Number backups: $cnt \n"

fi

}

is_in_recovery() {
  local isrecover=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "SELECT pg_is_in_recovery();" -t | xargs)
  if [[ "${isrecover,,}" == "t" ]]; then
    return 0
  else
    return 1
  fi
}


reload_conf() {
  local output=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "SELECT pg_reload_conf();" -t | xargs)
  if [[ "${output,,}" == "t" ]]; then
    return 0
  else
    return 1
  fi
}



stop_pg() {
  $PG_BIN_HOME/pg_ctl stop -D $PGSQL_BASE/data -s -m fast
  return $?
}


start_pg() {
  $PG_BIN_HOME/pg_ctl start -D $PGSQL_BASE/data -l $PGSQL_BASE/log/server.log -s -o "-p ${PG_PORT} --config_file=$PGSQL_BASE/etc/postgresql.conf" -w -t 300
  return $?
}


declare -a BACKUP_DATES_ARRAY
declare -a BACKUP_DIRS_ARRAY

getuntildir() {
local untiltime=$1
UNTIL_DIR_TIME=""
local backups=$(ls $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$")
local step=1
local c=0
local i a b
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
   BACKUP_DATES_ARRAY[$i]=${bdir//:*}
   BACKUP_DIRS_ARRAY[$i]=${bdir//*:}
   (( i++ ))
 done

else
 UNTIL_DIR_TIME=""
fi


local untildirtime
local arrcnt=${#BACKUP_DATES_ARRAY[@]}
i=0
while [ $i -le $arrcnt ]; do
  if [[ $i -eq $(( arrcnt-1 )) ]]; then
    [[ $untiltime -gt ${BACKUP_DATES_ARRAY[$i]} && $untiltime -lt ${BACKUP_DATES_ARRAY[0]} ]] && untildirtime=${BACKUP_DATES_ARRAY[$i]}
  else
    [[ $untiltime -gt ${BACKUP_DATES_ARRAY[$i]} && $untiltime -lt ${BACKUP_DATES_ARRAY[$(( i+1 ))]} ]] && untildirtime=${BACKUP_DATES_ARRAY[$i]}
  fi
  (( i++ ))
done

if [[ -z $untildirtime ]]; then
  UNTIL_DIR_TIME=""
else
  UNTIL_DIR_TIME=$untildirtime
fi

}




get_curr_backup_loc() {
local backups=$(ls $BACKUP_LOCATION/)
local d md cnt mdir mid midir
cnt=0
md=0
mid=$(date +"%s")
local dirdate=$(date +"%Y%m%d")

if [[ ! -z $backups ]]; then

 for bdir in $(ls -1 $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$" | sort); do
   (( cnt++ ))
   d="$(grep full_backup_time $BACKUP_LOCATION/$bdir/meta.info | cut -s -d"=" -f2)"
   d=$(eval "echo $d")
   d=$(date --date="${d}" +%s)
   [[ $d -gt $md ]] && md=$d && mdir=$bdir
   [[ $d -lt $mid ]] && mid=$d && midir=$bdir
 done

 local max_dir_num=$(ls -1 $BACKUP_LOCATION | sort -n | tail -1 | cut -d"-" -f1)
 [[ -z $max_dir_num ]] && max_dir_num=0

 if [[ ! -z $BACKUP_RETENTION_DAYS ]]; then
   # RETENTION_DAYS scenario

   local curr_date_secs=$(date +%s)
   local retension_seconds=$((BACKUP_RETENTION_DAYS*24*60*60))
   local retention_date_secs=$((curr_date_secs-retension_seconds))

   getuntildir $retention_date_secs

    
   if [[ -z $UNTIL_DIR_TIME ]]; then
     CURR_BACKUP_DIR=$BACKUP_LOCATION/$(( max_dir_num+1 ))"-$dirdate"

   else

    local dirs_obsoleted
    local arrcnt=${#BACKUP_DATES_ARRAY[@]}
    local i=0
    while [ $i -le $arrcnt ]; do
      [[ $UNTIL_DIR_TIME -gt ${BACKUP_DATES_ARRAY[$i]} ]] && dirs_obsoleted="$dirs_obsoleted ${BACKUP_DIRS_ARRAY[$i]}"
      (( i++ ))
    done

#    for bdir in $(ls -1 $BACKUP_LOCATION/ | grep -E "^[0-9]+-[0-9]+$" | sort); do
#     d="$(grep full_backup_time $BACKUP_LOCATION/$bdir/meta.info | cut -s -d"=" -f2)"
#     d=$(eval "echo $d")
#     d=$(date --date="${d}" +%s)
#     [[ $d -lt $retention_date_secs ]] && dirs_obsoleted="$dirs_obsoleted $bdir"
#    done
     
     info "According to BACKUP_RETENTION_DAYS=$BACKUP_RETENTION_DAYS, next folder(s) will be removed:"
     for ddir in $dirs_obsoleted; do
       echo "${ddir}"
       rm -Rf $BACKUP_LOCATION/${ddir}
     done

     echo "obsolet=$dirs_obsoleted"

     if [[ ${#dirs_obsoleted} -lt 2 ]]; then
        echo "1"  
        CURR_BACKUP_DIR=$BACKUP_LOCATION/$(( max_dir_num+1 ))"-$dirdate"     
     else
       [[ -z $midir ]] && error "All backup dates in the future, check meta.info file." && exit 1
       info "Folder $midir will be used for new backup"
       CURR_BACKUP_DIR=$BACKUP_LOCATION/${midir//-*}-$dirdate
     fi

   fi

else
  # REDUNDANCY scenario
   
   if [[ $cnt -lt $BACKUP_REDUNDANCY ]]; then
     CURR_BACKUP_DIR=$BACKUP_LOCATION/$(( max_dir_num+1 ))"-$dirdate"
   else
     if [[ $cnt -gt $BACKUP_REDUNDANCY && ${midir//-*} -eq 1 ]]; then
        for dropdir in $(seq $(( BACKUP_REDUNDANCY+1 )) $cnt); do
          info "According to BACKUP_REDUNDANCY=$BACKUP_REDUNDANCY, folder $dropdir will be removed."
          rm -Rf $BACKUP_LOCATION/${dropdir}-*
        done
     fi
     [[ -z $midir ]] && error "All backup dates in the future, check meta.info file." && exit 1
     info "According to BACKUP_REDUNDANCY=$BACKUP_REDUNDANCY, folder $midir will be recycled and used for new backup"
     rm -Rf $BACKUP_LOCATION/${midir}
     CURR_BACKUP_DIR=$BACKUP_LOCATION/${midir//-*}-$dirdate
     #CURR_BACKUP_DIR=$BACKUP_LOCATION/1-$dirdate
   fi

fi

else
 CURR_BACKUP_DIR=$BACKUP_LOCATION/1-$dirdate
fi

}




########### MAIN ########################################



[[ -z $BACKUP_LOCATION ]] && error "BACKUP_LOCATION is not defined. Check parameters.conf." && exit 1



args=" list enable_arch backup_dir -h help "


LIST=false
ENABLEARCH=false
ONETIME_BACKUP_LOC=""
SWITCH_ARCH_LOC=true

for arg in "$@"; do

  pattern=" +${arg%%=*} +"
  [[ ! "$args" =~ $pattern ]] && error "Bad argument $arg" && help && exit 1

  [[ "$arg" == "list" ]] && LIST=true
  [[ "$arg" == "enable_arch" ]] && ENABLEARCH=true
  [[ "$arg" =~ backup_dir=.+ ]] && ONETIME_BACKUP_LOC=$(echo $arg | cut -s -d"=" -f2 | xargs)
  [[ "$arg" =~ -h|help ]] && help && exit 0

done


if [[ ! -z $ONETIME_BACKUP_LOC ]]; then
  BACKUP_LOCATION=$ONETIME_BACKUP_LOC
  SWITCH_ARCH_LOC=false
  info "One time backup location $BACKUP_LOCATION will be used. No archive location switch will be performed."
fi

[[ "$LIST" == true ]] && list_backup_dir && exit 0




printheader "Check if Cluster in archive log mode."
ARCH_MODE=$($PG_BIN_HOME/psql -U $PG_SUPERUSER -p $PG_PORT -d postgres -c "SHOW archive_mode" -t | xargs)
if [[ ! "${ARCH_MODE,,}" == "on" && ! "${ARCH_MODE,,}" == "always" ]]; then
  info "Cluster is not in archive mode."

  if [[ "$ENABLEARCH" == true ]]; then
     info "Cluster will be restarted to set archive_mode"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" archive_mode "always"
     set_conf_param "$PGSQL_BASE/etc/postgresql.conf" archive_command "'test ! -f $PGSQL_BASE/arch/%f && cp %p $PGSQL_BASE/arch/%f'"
     sudo systemctl stop postgresql-${PGBASENV_ALIAS}
     sudo systemctl start postgresql-${PGBASENV_ALIAS}
  fi
else
  info "Cluster is in archive log mode."
fi

[[ "$ENABLEARCH" == true ]] && info "Done." && exit 0


if [[ ! -d $BACKUP_LOCATION ]]; then
  info "Backup directory $BACKUP_LOCATION not exist. Creating."
  mkdir -p $BACKUP_LOCATION && chown postgres:postgres $BACKUP_LOCATION
fi


#if [[ ! -z "$PG_SUPERUSER_PWDFILE" && -f "$SCRIPTDIR/$PG_SUPERUSER_PWDFILE" ]]; then
#    chown postgres:postgres $SCRIPTDIR/$PG_SUPERUSER_PWDFILE
#    chmod 0400 $SCRIPTDIR/$PG_SUPERUSER_PWDFILE
#    PG_SUPERUSER_PWD="$(head -1 $SCRIPTDIR/$PG_SUPERUSER_PWDFILE | xargs)"
#else
#  error "Password file with superuser $PG_SUPERUSER password is required for backup.
#  Create the password file in the same directory as the backup script and set PG_SUPERUSER_PWDFILE parameter in parameters.conf."
#  exit 1
#fi


BACKUP_MODE=full

[[ -z $BACKUP_REDUNDANCY ]] && BACKUP_REDUNDANCY=7

printheader "Prepare backup subdirectory."
get_curr_backup_loc

if [[ "${BACKUP_MODE,,}" == "full" ]]; then
  if [[ ! -d $CURR_BACKUP_DIR ]]; then
     info "Creating directory $CURR_BACKUP_DIR"
     create_backup_dir $CURR_BACKUP_DIR
  else
     error "Cannot overwrite existing backup in $CURR_BACKUP_DIR, remove it first if not required!"
     exit 1
  fi

  if [[ "$SWITCH_ARCH_LOC" == true ]]; then
    printheader "Update archive log location."
    info "Setting archived wal location to $CURR_BACKUP_DIR/wal, wals will be archived to this directory until next full backup."
    set_conf_param "$PGSQL_BASE/etc/postgresql.conf" archive_command "'rsync --timeout=5 --ignore-existing %p $CURR_BACKUP_DIR/wal/%f \&\& rsync --timeout=5 --ignore-existing --remove-source-files -a $PGSQL_BASE/arch/ $CURR_BACKUP_DIR/wal || cp -p %p $PGSQL_BASE/arch/%f'"
    reload_conf
  fi

  printheader "Execute Cluster backup."

  info "full_backup_time=\"$(date +"%Y-%m-%d %H:%M:%S")\"" > $CURR_BACKUP_DIR/meta.info
  #start_lsn="$(su -l postgres -c "$PG_BIN_HOME/psql -c \"SELECT pg_start_backup('label', false, true);\" -t" | xargs)"

  info "Backup to $CURR_BACKUP_DIR"
  #tar -cf $CURR_BACKUP_DIR/data/basebackup.tar.gz -C $PGSQL_BASE/data .

#  export PGPASSWORD=$PG_SUPERUSER_PWD
  $PG_BIN_HOME/pg_basebackup -D $CURR_BACKUP_DIR/data -F tar -X stream -p $PG_PORT -U $PG_SUPERUSER -v -w -z -Z3
  if [[ $? -ne 0 ]]; then
     error "Backup failed, check the output and server logs."
     rm -Rf $TMP_DIR_NAME
 #    rm -f .pwdfile_pg_basebackup
     rm -Rf $CURR_BACKUP_DIR
     exit 1
  fi
 # rm -f .pwdfile_pg_basebackup

  chown postgres:postgres $CURR_BACKUP_DIR/data/*

  if [[ "$SWITCH_ARCH_LOC" == true ]]; then
    printheader "Maintaining spare archive log location $PGSQL_BASE/arch."
    info "Files do not required for recovery will be removed."
    oldest_backup_file="$(ls -1tr $BACKUP_LOCATION/*/data/base.tar.gz | head -1)"

    if [[ ! -z $oldest_backup_file ]]; then
       oldest_backup_wal=$(tar -xf $oldest_backup_file backup_label -O | grep -oE "file [0-9A-Za-z]+" | cut -d" " -f2)
       $PG_BIN_HOME/pg_archivecleanup -d $PGSQL_BASE/arch $oldest_backup_wal
    fi
  fi

 # start_wal="$(su -l postgres -c "$PG_BIN_HOME/psql -c \"SELECT pg_walfile_name('$start_lsn');\" -t" | xargs)"
 # echo "Copying all WAL files after $start_wal"
 # walepoch="$(date -r $WAL_ARCH_LOCATION/$start_wal +%s)"
 # for walname in $(ls -1tr $WAL_ARCH_LOCATION); do
 #   if [[ $(date -r $WAL_ARCH_LOCATION/$walname +%s) -ge $walepoch ]]; then
 #     echo "processing wal file $WAL_ARCH_LOCATION/$walname"
 #     cp -p $WAL_ARCH_LOCATION/$walname $CURR_BACKUP_DIR/wal/
 #   fi
 #   [[ -f $CURR_BACKUP_DIR/wal/$walname ]] && rm -f $WAL_ARCH_LOCATION/$walname
 # done

fi

echo -e
echo "Backup finished."


exit 0

