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


PG_SUPERUSER=postgres

add_sudoers_rules() {

echo "
$PG_SUPERUSER ALL= NOPASSWD: /bin/systemctl start postgresql*
$PG_SUPERUSER ALL= NOPASSWD: /bin/systemctl stop postgresql*
$PG_SUPERUSER ALL= NOPASSWD: /bin/systemctl status postgresql*
$PG_SUPERUSER ALL= NOPASSWD: /bin/systemctl reload postgresql*
" > /etc/sudoers.d/01_postgres

echo "Now user $PG_SUPERUSER can use sudo to start/stop postgresql using systemctl."

}


add_sudoers_rules

echo "Done"
