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
# Generates a script to update systemctl unit file with the actual information from the pgclustertab
#


help() {

echo "

Generates a script to update systemctl unit file with the actual information from the pgclustertab.

"

}

if [[ $1 =~ -h|help ]]; then
  help
  exit
fi


declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"

if [[ -z $PGBASENV_ALIAS ]]; then
  echo "ERROR: Set environment for the target cluster first."
  exit 1
fi

[[ ! -f $PGOPERATE_BASE/lib/shared.lib ]] && echo "Cannot read $PGOPERATE_BASE/lib/shared.lib file." && exit 1
source $PGOPERATE_BASE/lib/shared.lib

PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf
[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1


printheader() {
  GRE='\033[0;32m'
  NC='\033[0m'

  echo -e "$GRE"
  echo -e "----------------------------------------------------------------------------"
  echo -e "[   $1"
  echo -e "----------------------------------------------------------------------------"
  echo -e "$NC"

}


create_update_unitfile_sh() {
  echo "#!/usr/bin/env bash

source $PGOPERATE_BASE/lib/shared.lib
PGSQL_BASE=$PGSQL_BASE
PG_PORT=$PG_PORT
PG_BIN_HOME=$PG_BIN_HOME

create_service_file $PG_SERVICE_FILE

" > $PGSQL_BASE/scripts/update_unitfile.sh 
chmod 700 $PGSQL_BASE/scripts/update_unitfile.sh 
}


### MAIN ######################################################################

PG_SERVICE_FILE="postgresql-${PGBASENV_ALIAS}.service"
PG_BIN_HOME=$TVD_PGHOME/bin
PG_PORT=$PGPORT

printheader "Generating $PGSQL_BASE/scripts/update_unitfile.sh file."
create_update_unitfile_sh


echo -e
echo "INFO: Execute as root $PGSQL_BASE/scripts/update_unitfile.sh."
echo " "
echo " "


exit

