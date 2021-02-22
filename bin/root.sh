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

# Executes root related action.

PGOPERATE_BASE=/var/lib/pgsql/tvdtoolbox/pgoperate
USER=postgres
GROUP=postgres

create_service_file() {
if [[ $_IS_ROOT -ne 0 ]]; then 
   echo "WARNING: Must be root to create service file for systemd."
   return 1
fi

local service_file=$1
local user=$2
local group=$3
echo "
[Unit]
Description=pgOperate deamon process
Documentation=https://github.com/Trivadis/pgoperate
After=network.target

[Service]
Type=forking
User=${user}
Group=${group}
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Environment=PGOPERATE_BASE=${PGOPERATE_BASE}
PIDFile=${PGOPERATE_BASE}/bin/pgoperate-deamon.pid
Restart=on-failure
TimeoutSec=300

ExecStart=${PGOPERATE_BASE}/bin/pgoperated start
ExecStop=${PGOPERATE_BASE}/bin/pgoperated kill
ExecReload=${PGOPERATE_BASE}/bin/pgoperated reload

[Install]
WantedBy=multi-user.target

" > /etc/systemd/system/$service_file

systemctl daemon-reload
systemctl enable $service_file
systemctl start $service_file
systemctl status $service_file --plain --no-pager
}


add_sudoers_rules() {

echo "
$USER ALL= NOPASSWD: /bin/systemctl start pgoperated-$USER.service
$USER ALL= NOPASSWD: /bin/systemctl stop pgoperated-$USER.service
$USER ALL= NOPASSWD: /bin/systemctl status pgoperated-$USER.service
$USER ALL= NOPASSWD: /bin/systemctl reload pgoperated-$USER.service
" > /etc/sudoers.d/01_$USER

echo "Now user $USER can use sudo to start/stop pgoperated-$USER.service using systemctl."

}


# If SELinux
semanage fcontext -a -t bin_t "$PGOPERATE_BASE/bin(/.*)?" > /dev/null 2>&1
restorecon -r -v $PGOPERATE_BASE/bin > /dev/null 2>&1

create_service_file "pgoperated-$USER.service" $USER $GROUP
add_sudoers_rules

echo "Done"
