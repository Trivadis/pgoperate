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
# Author:  Aychin Gasimov (AYG)
# Desc: Script to generate installation bundle from current pgOperate.
#       Check README.md for details.
#
# Change log:
#   06.07.2020: Aychin: Initial version created
#
#

bundle_dir=$1

dir=$(pwd) && dir=${dir//\/pgoperate\/bin/}
[[ $? -gt 0 ]] && echo -e "\nFAILURE\n" && exit 1

[[ ! -f create_cluster.sh ]] && echo "Execute this script from the pgoperate bin directory." && exit 1

#current_version=$(./pgoperate.sh --version)
current_version=$(cat VERSION | xargs)
[[ $? -gt 0 ]] && echo -e "\nFAILURE\n" && exit 1

echo -e "\nCurrent version: ${current_version}\n"

[[ -z $bundle_dir ]] && bundle_dir="$dir/pgoperate/bundle"

mkdir -p $bundle_dir
echo -e "Destination directory: $bundle_dir\n"

cp install_pgoperate.sh $bundle_dir
[[ $? -gt 0 ]] && echo -e "\nFAILURE\n" && exit 1

cd $dir

self=$(basename $0)
[[ $? -gt 0 ]] && echo -e "\nFAILURE\n" && exit 1

echo -e "Creating tar file: pgoperate-${current_version}.tar\n"

tar --exclude="pgoperate/.git" --exclude="pgoperate/.gitignore" --exclude="pgoperate/bin/$self" --exclude="pgoperate/bin/install_pgoperate.sh" --exclude="pgoperate/log/*" --exclude="pgoperate/etc/*.conf" --exclude="pgoperate/bundle/*" -cvf "$bundle_dir/pgoperate-${current_version}.tar" pgoperate

if [[ $? -eq 0 ]]; then
	echo -e "\nSUCCESS\n"
    exit 0
else
    exit 1
fi
