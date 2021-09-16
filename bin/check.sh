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
#   17.08.2021: Michael: adapted to json and text output
#   14.09.2021: Michael: added possbility to run specific check only
#
# Script to monitor and check PostgreSQL database cluster.
#
# Script uses PGSQL_BASE and other variables from parameters.conf file, which is in the script directory.


help(){
echo "
  Execute checks defined in $PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf.

  Arguments:
                -t|--text output result to text format only
                -j|--json output result to json format only
                -c==<check_defined_in_paramter_file>|--c=<check_defined_in_paramter_file> 
"
}


# Set custom .psqlrc file
export PSQLRC=$PGOPERATE_BASE/bin/.psqlrc


declare -r SCRIPTDIR="$( cd "$(dirname "$0")" ; pwd -P )"

[[ -z $PGBASENV_ALIAS ]] && error "Set the alias for the current cluster first." && exit 1
echo -e "\nCurrent cluster: ${PGBASENV_ALIAS}"

[[ -z $PGBASENV_ALIAS ]] && error "PG_BIN_HOME is not defined. Set the environment for cluster home."
PG_BIN_HOME=$TVD_PGHOME/bin


PARAMETERS_FILE=$PGOPERATE_BASE/etc/parameters_${PGBASENV_ALIAS}.conf
[[ ! -f $PARAMETERS_FILE ]] && echo "Cannot find configuration file $PARAMETERS_FILE." && exit 1
source $PARAMETERS_FILE


declare -r CHECKS_LIBRARY=check.lib
declare -r CUSTOM_CHECKS_LIBRARY=custom_check.lib
declare -r FAIL_COUNT_FILE=$PGSQL_BASE/etc/.check.fail.counter


if [[ -f $PGOPERATE_BASE/lib/$CHECKS_LIBRARY ]]; then
   . $PGOPERATE_BASE/lib/$CHECKS_LIBRARY
else
   echo "ERROR: Check library cannot be found: $PGOPERATE_BASE/lib/$CHECKS_LIBRARY"
   exit 1
fi

if [[ -f $PGOPERATE_BASE/lib/$CUSTOM_CHECKS_LIBRARY ]]; then
   . $PGOPERATE_BASE/lib/$CUSTOM_CHECKS_LIBRARY
else
   echo "ERROR: Custom Check library cannot be found: $PGOPERATE_BASE/lib/$CUSTOM_CHECKS_LIBRARY"
   exit 1
fi

# Default port
[[ -z $PG_PORT ]] && PG_PORT=5432

touch $FAIL_COUNT_FILE


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

success() {
  echo -e "$GRE"
  echo -e "SUCCESS: $1"
  echo -e "$NC"
}

critical() {
  echo -e "$RED"
  echo -e "CRITICAL: $1"
  echo -e "$NC"
}



modifyFile() {
  local v_file=$1
  local v_op=$2
  local value="$3"
  local replace="$4"
  replace="${replace//\"/\\x22}"
  replace="${replace//$'\t'/\\t}"
  value="${value//\"/\\x22}"
  value="${value//$'\t'/\\t}"
  local v_bkp_file=$v_file"."$(date +"%y%m%d%H%M%S")
  if [[ -z $v_file || -z $v_op ]]; then
    error "First two arguments are mandatory!"
    return 1
  fi
  if [[ $v_op == "bkp" ]]; then
     cp $v_file $v_bkp_file
  fi
  if [[ $v_op == "rep" ]]; then
      if [[ -z $value || -z $replace ]]; then
         error "Last two values required $3 and $4, value and its replacement!"
         return 1
      fi
      sed -i -e "s+$replace+$value+g" $v_file
      [[ $? -ne 0 ]] && error "Write operation failed!" && return 1
  fi
  if [[ $v_op == "add" ]]; then
      if [[ -z $value ]]; then
         error "Third argument $3 required!"
         return 1
      fi
      echo -e $value >> $v_file
      [[ $? -ne 0 ]] && error "Write operation failed!" && return 1
  fi
  if [[ $v_op == "rem" ]]; then
      if [[ -z $value ]]; then
         error "Third argument $3 required!"
         return 1
      fi
      sed -i "s+$value++g" $v_file
      [[ $? -ne 0 ]] && error "Write operation failed!" && return 1
  fi
  return 0
}


if_function() {
    [[ -z $1 ]] && return 1
    declare -f -F $1 > /dev/null
    return $?
}


add_fail_count() {
  [[ ! -z $1 ]] && local key=$1 || local key="${FUNCNAME[1]}"
  local curr_val=$(grep -E "^$key=" $FAIL_COUNT_FILE | cut -d"=" -f2 | xargs)
  local next_val
  if [[ ! -z $curr_val ]]; then
    ((next_val=curr_val+1))
    modifyFile $FAIL_COUNT_FILE rep "$key=$next_val" "$key=$curr_val"
    eval "${key}_FAILCOUNT=$next_val"
    FAILCOUNT=$next_val
  else
    modifyFile $FAIL_COUNT_FILE add "$key=1"
    eval "${key}_FAILCOUNT=1"
    FAILCOUNT=1
  fi
}


get_fail_count() {
  [[ ! -z $1 ]] && local key=$1 || local key="${FUNCNAME[1]}"
  local curr_val=$(grep -E "^$key=" $FAIL_COUNT_FILE | cut -d"=" -f2 | xargs)
  if [[ $curr_val -gt 0 ]]; then
     eval "${key}_FAILCOUNT=$curr_val"
     FAILCOUNT=$curr_val
  else
     eval "${key}_FAILCOUNT=0"
     FAILCOUNT=0
  fi
}

reset_fail_count() {
  [[ ! -z $1 ]] && local key=$1 || local key="${FUNCNAME[1]}"
  local curr_val=$(grep -E "^$key=" $FAIL_COUNT_FILE | cut -d"=" -f2 | xargs)
  local new_val=0
  if [[ $curr_val -ge 0 ]]; then
    modifyFile $FAIL_COUNT_FILE rep "$key=$new_val" "$key=$curr_val"
  else
    modifyFile $FAIL_COUNT_FILE add "$key=$new_val"
  fi
}


check_connectivity() {
  $PG_BIN_HOME/pg_isready -p $PG_PORT -U $PG_SUPERUSER -q
  local res=$?
  [[ $res -gt 0 ]] && declare -gr PG_AVAILABLE=false || declare -gr PG_AVAILABLE=true
  return $res
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

alarm_error() {
  local check_name=$1
  local message=$2
  error "From check $check_name: $message"
}


alarm_success() {
  local check_name=$1
  local message=$2
  success "From check $check_name: $message"  
}

alarm_critical() {
  local check_name=$1
  local message=$2
  critical "From check $check_name: $message"    
}




##########
# main()
##########




while (( "$#" )); do
  case "$1" in
    -t|--text)
    exptype='text'
    shift
      ;;
    -j|--json)
    exptype='json'
    shift
      ;;  
    -c=*|--check=*)
    ctype='single'
    export check=`echo $1 | sed -e 's/^[^=]*=//g'`
    shift
      ;;          
    help) help
          exit 0
          ;;
    -*|--*=) # unsupported flags
      echo "ERROR: Unsupported flag $1" >&2
      help
      exit 1
      ;;
    *) echo "ERROR: Illegal argument."
       help
       exit 1
      ;;
  esac
done


check_connectivity
if [[ $? -gt 0 ]]; then 
   alarm_critical PG_AVAILABILITY "PostgreSQL database cluster is not available!"
fi





if [[ $ctype == "single" ]]; then

check_function=$(eval "echo \$$check")
check_variable=$check

  OCCURRENCE=0
  FAILCOUNT=0
  eval "test ! -z \${${check_variable}_THRESHOLD+check}" && eval "declare -r ${check_function}_THRESHOLD=\$${check_variable}_THRESHOLD"
  eval "test ! -z \${${check_variable}_OCCURRENCE+check}" && eval "declare -r ${check_function}_OCCURRENCE=\$${check_variable}_OCCURRENCE" && OCCURRENCE=$(eval "echo \$${check_variable}_OCCURRENCE")


  if [[ $exptype == "json" ]]; then

       eval "$check_function"
  if [[ $? -eq 0 ]]; then
     printf '{"check":"%s","status":"%s","curval":"%s","treshold":"%s"}\n' "$check_variable" "ok" "$(eval "echo \"\$${check_function}_CURVAL\"")" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"
     reset_fail_count $check_function
  else
     add_fail_count $check_function

     if [[ $FAILCOUNT -ge $OCCURRENCE ]]; then
                 
          printf '{"check":"%s","status":"%s","curval":"%s","treshold":"%s"}\n' "$check_variable" "critical" "$(eval "echo \"\$${check_function}_CURVAL\"")" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"

     else
        alarm_success $check_variable "FAIL COUNT: $FAILCOUNT: $(eval "echo \"\$${check_function}_PAYLOAD\"")"
        eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
        echo "alarm success"
      


     fi
  fi


  elif [[ $exptype == "text" ]]; then      
     #debug echo "the text part"  

       eval "$check_function"
  if [[ $? -eq 0 ]]; then
     #alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOAD\"")"
     
     
     echo $check_variable "|" "ok" "|" "$(eval "echo \"\$${check_function}_CURVAL\"")" "|" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"

     reset_fail_count $check_function
  else
     add_fail_count $check_function

     if [[ $FAILCOUNT -ge $OCCURRENCE ]]; then
        #alarm_critical $check_variable "$(eval "echo \"\$${check_function}_PAYLOAD\"")"
        #eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_critical $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
       
          echo $check_variable "|" "critical" "|" "$(eval "echo \"\$${check_function}_CURVAL\"")" "|" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"

     else
        alarm_success $check_variable "FAIL COUNT: $FAILCOUNT: $(eval "echo \"\$${check_function}_PAYLOAD\"")"
        eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
        echo "alarm success"



     fi
  fi

  else

  
  echo "Executing check $check_variable"

  eval "$check_function"
  if [[ $? -eq 0 ]]; then
     alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOAD\"")"
     reset_fail_count $check_function
  else
     add_fail_count $check_function

     if [[ $FAILCOUNT -ge $OCCURRENCE ]]; then
        alarm_critical $check_variable "$(eval "echo \"\$${check_function}_PAYLOAD\"")"
        eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_critical $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
        echo $check_variable "|" "critical" "|" "$(eval "echo \"\$${check_function}_CURVAL\"")"


     else
        alarm_success $check_variable "FAIL COUNT: $FAILCOUNT: $(eval "echo \"\$${check_function}_PAYLOAD\"")"
        eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
        echo "alarm success"
        echo $check_variable "|" "ok" "|" "$(eval "echo \"\$${check_function}_CURVAL\"")"

                ## added output to  text mmi


     fi
  fi
fi  



exit

fi 

while read check_variable; do
  
  eval "test ! -z \$$check_variable"

  #echo $check_variable

  [[ $? -gt 0 ]] && continue

  check_function=$(eval "echo \$$check_variable")
  if_function "$check_function"
  if [[ $? -gt 0 ]]; then 
     alarm_error $check_variable "Check function $check_function not defined!"
     continue
  fi

  OCCURRENCE=0
  FAILCOUNT=0
  eval "test ! -z \${${check_variable}_THRESHOLD+check}" && eval "declare -r ${check_function}_THRESHOLD=\$${check_variable}_THRESHOLD"
  eval "test ! -z \${${check_variable}_OCCURRENCE+check}" && eval "declare -r ${check_function}_OCCURRENCE=\$${check_variable}_OCCURRENCE" && OCCURRENCE=$(eval "echo \$${check_variable}_OCCURRENCE")



  if [[ $exptype == "json" ]]; then

       eval "$check_function"
  if [[ $? -eq 0 ]]; then
     #printf '{"check":"%s","status":"%s","treshold":"%s"}\n' "$check_variable" "ok" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"
     printf '{"check":"%s","status":"%s","curval":"%s","treshold":"%s"}\n' "$check_variable" "ok" "$(eval "echo \"\$${check_function}_CURVAL\"")" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"
     reset_fail_count $check_function
  else
     add_fail_count $check_function

     if [[ $FAILCOUNT -ge $OCCURRENCE ]]; then
                 
          #printf '{"check":"%s","status":"%s","treshold":"%s"}\n' "$check_variable" "critical" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"
          printf '{"check":"%s","status":"%s","curval":"%s","treshold":"%s"}\n' "$check_variable" "critical" "$(eval "echo \"\$${check_function}_CURVAL\"")" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"
     else
        alarm_success $check_variable "FAIL COUNT: $FAILCOUNT: $(eval "echo \"\$${check_function}_PAYLOAD\"")"
        eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
        echo "alarm success"
      


     fi
  fi


  elif [[ $exptype == "text" ]]; then      
     #debug echo "the text part"  

       eval "$check_function"
  if [[ $? -eq 0 ]]; then
     #alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOAD\"")"
     
     #echo $check_variable "|" "ok" "|" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"
     echo $check_variable "|" "ok" "|" "$(eval "echo \"\$${check_function}_CURVAL\"")" "|" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"
     reset_fail_count $check_function
  else
     add_fail_count $check_function

     if [[ $FAILCOUNT -ge $OCCURRENCE ]]; then
        #alarm_critical $check_variable "$(eval "echo \"\$${check_function}_PAYLOAD\"")"
        #eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_critical $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
       
          #echo $check_variable "|" "critical" "|" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"
          echo $check_variable "|" "critical" "|" "$(eval "echo \"\$${check_function}_CURVAL\"")" "|" "$(eval "echo \"\$${check_function}_THRESHOLD\"")"

     else
        alarm_success $check_variable "FAIL COUNT: $FAILCOUNT: $(eval "echo \"\$${check_function}_PAYLOAD\"")"
        eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
        echo "alarm success"

     fi
  fi

  else

  
  echo "Executing check $check_variable"

  eval "$check_function"
  if [[ $? -eq 0 ]]; then
     alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOAD\"")"
     
     reset_fail_count $check_function

  else
     add_fail_count $check_function

     if [[ $FAILCOUNT -ge $OCCURRENCE ]]; then
        alarm_critical $check_variable "$(eval "echo \"\$${check_function}_PAYLOAD\"")"
        eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_critical $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
       

     else
        alarm_success $check_variable "FAIL COUNT: $FAILCOUNT: $(eval "echo \"\$${check_function}_PAYLOAD\"")"
        eval "test ! -z \${${check_function}_PAYLOADLONG+check}" && alarm_success $check_variable "$(eval "echo \"\$${check_function}_PAYLOADLONG\"")"
        echo "alarm success"
                ## added output to  text mmi
      

     fi
  fi
fi  

done < <(compgen -A variable | grep -E "^PG_CHECK" | grep -vE "(_THRESHOLD|_OCCURRENCE)$")











exit 0

