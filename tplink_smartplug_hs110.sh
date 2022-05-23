#!/bin/bash

###
# Description:
#   Queries a TP-Link Smartplug and sends the data to a Zabbix server.
#   Currently supported models:
#     - HS110
#  
# Exit codes:
#   0: Successfully queried TP-Link Smartplug and send the data to Zabbix server
#   1: getopt --test failed
#   2: Failed to parse commandline options
#   3: TP-Link Smartplug hostname or IP address not given
#   4: Zabbix server hostname or IP address not given
#   5: Failed to retrieve or send an item from Smartplug/to Zabbix server
#
# log file                                      : no
# logrotate                                     : no
# zabbix script monitoring integration
#  - exit and error codes                       : no, not required, intended to use in a container
#  - runtime errors                             : yes, included within this script
# log file monitoring                           : no, not required, intended to use in a container
#
# Author:
# Steffen Scheib (steffen@scheib.me)
#
# Legend:
# + New
# - Bugfix
# ~ Change
# . Various
#
# Changelog:
# 23.05.2022: . Initial
#
# version: 1.0
VERSION=1.0

# option definitions for getopt
__LONG_OPTIONS="hostname:,zabbix-server:,help,verbose"
__SHORT_OPTIONS="z:,n:,h,v"

# verbose output, disabled by default
declare -i __VERBOSE=1

# items the TP-Link smartplug can deliver values to
declare -ar __ITEMS=(
  "active_mode"
  "alias"
  "current_ma"
  "dev_name"
  "deviceId"
  "err_code"
  "feature"
  "fwId"
  "hwId"
  "hw_ver"
  "icon_hash"
  "latitude_i"
  "led_off"
  "longitude_i"
  "mac"
  "model"
  "next_action"
  "oemId"
  "on_time"
  "power_mw"
  "relay_state"
  "rssi"
  "sw_ver"
  "total_wh"
  "type"
  "updating"
  "voltage_mv"
)

# let the whole pipe fail (exit with != 0) if a command in it fails
set -o pipefail

# required binaries by this script
declare -ar __REQUIRED_BINARIES=(
  "jq"
  "kasa"
)

# used to store energy data (kasa emeter) in order to minimize querying the smartplug
declare __ENERGY_METER=""
# used to store system information (kasa sysinfo) in order to minimize querying the smartplug
declare __SYSTEM_INFO=""

###
# function tplSmartplugQuery::init
#---
# Description:
#---
# Checks if all requirements to run this script are given.
#---
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#  none
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __REQUIRED_BINARIES                           | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | If all conditions to run this script are met
# (return)   1 | If one or more binaries defined in __REQUIRED_BINARIES are missing
#####
function tplSmartplugQuery::init () {
  for binary in "${__REQUIRED_BINARIES[@]}"; do
    command -v "${binary}" &> /dev/null || {
      echo "ERROR: Binary '${binary}' is not installed, but required by this script!"; 
      return 1; 
    };
  done

  return 0;
}; # function tplSmartplugQuery::init ( )


###
# function tplSmartplugQuery::init
#---
# Description:
#---
# Queries the given TP-Link smartplug and sends the given item to the given Zabbix server.
# Note: Data is queried in bulk (via kasa emeter and kasa sysinfo), however only one item is send to the Zabbix server.
#       To reduce the number of times the smartplug has to be queried, the data is stored in __ENERGY_METER and
#       __SYSTEM_INFO, which will be used for subsequent queries of this function.
#---
# Arguments:
#---
#   #  | name                                   | type        | description
#------+----------------------------------------+-------------+--------------------------------------------------------< 
#<  $1> | item                                  | string      | Item to query from the smartplug
#<  $2> | host                                  | string      | Hostname or IP address of the smartplug
#<  $3> | zabbixServer                          | string      | Hostname or IP address of the Zabbix server
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __ENERGY_METER                                | read/write  | Variable to store the queried data from emeter
#   02 | __SYSTEM_INFO                                 | read/write  | Variable to store the queried data from sysinfo
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | Value of given item successfully transmitted to the Zabbix server
# (return)   1 | Parameter $1 (item) not given
# (return)   2 | Parameter $2 (host) not given
# (return)   3 | Parameter $3 (zabbixServer) not given
# (return)   4 | Unknown item to query retrieved
#####
function gather_values() {
  [[ -n "${1}" ]] || {
    return 1;
  };
  declare item="${1}"

  [[ -n "${2}" ]] || {
    return 2;
  };
  declare host="${2}"

  [[ -n "${3}" ]] || {
    return 3;
  };
  declare zabbixServer="${3}"

  declare value=""
  case "${item}" in
    # the below items cannot be retrieved as a JSON (or similar) and thus have a human-readable name, which we 
    # need to search for and extract its value
    voltage_mv|current_ma|power_mw|total_wh)
      declare extractKeyword=""
      case "${item}" in 
        voltage_mv)
          extractKeyword="Voltage:"
        ;;
        current_ma)
          extractKeyword="Current:"
        ;;
        power_mw)
          extractKeyword="Power:"
        ;;
        total_wh)
          extractKeyword="Total consumption:"
        ;;
      esac

      # query the smartplug only if __ENERGY_METER is empty
      [[ -n "${__ENERGY_METER}" ]] || {
        __ENERGY_METER="$(kasa --type plug --host "${host}" emeter)"
      };

      # get the current values from the device (via the emeter function), replace the description (via extractKeyword) as well as any given unit symbol and round it to 2 decimal digits
      value="$(printf "%.2f\n" "$(echo "${__ENERGY_METER}" | grep -E "^${extractKeyword}" | sed "s/^${extractKeyword}//" | sed -E 's/[[:space:]](A|V|W|kWh)//')")"
    ;;
    # the below items can be retrieved as JSON from the smartplug
    active_mode|alias|dev_name|deviceId|err_code|feature|fwId|hwId|hw_ver|icon_hash|latitude_i|led_off|longitude_i|mac|model|next_action|oemId|on_time|relay_state|rssi|sw_ver|type|updating) 
      # query the smartplug only if __ENERGY_METER is empty
      [[ -n "${__SYSTEM_INFO}" ]] || {
        __SYSTEM_INFO="$(kasa --type plug --host "${host}" sysinfo)";
      }

      # get the last 23 lines from sysinfo, replace ' with " (to have proper json) and get the value for the provided key
      value="$(echo "${__SYSTEM_INFO}" | tail -n 23 | tr "\'" "\"" | jq -r ".${item}")"

      # special treatment for certain items
      case "${item}" in
        icon_hash)
          # icon_hash seems to be empty, which will result in an unsupported state in Zabbix, hence "translating" it to empty if value is not set
          [[ -n "${value}" ]] || {
            value="empty"
          };
        ;;
        led_off)
          # turn led_off to led_true - better readability in Zabbix .. kinda
          value="$(echo "${value}" | sed -e 's/1/0/' -e 's/0/1/')"
        ;;
        next_action)
          # next_action has a sub-element which is "type"
          value="$(echo "${value}" | jq -r ".type")" 
        ;;
        on_time)
          # substract the seconds provided from the current date and display the date in a 'proper' way
          value="$(date +'%d.%m.%Y %H:%M:%S' --date "-${value} sec")"
        ;;
      esac

      # finally store the value
      value="$(printf "%s\n" "${value}")"
    ;;
    *)
      # unknown item given
      return 4;
    ;;
  esac

  if [[ "${__VERBOSE}" -ne 0 ]]; then
    echo "- tplink_smartplug_hs110[${item}] ${value}" | zabbix_sender -i - -s "${host}" -z "${zabbixServer}" >> /dev/null || {
      # sending values to Zabbix failed
      return 5;
    };
  else
    echo "- tplink_smartplug_hs110[${item}] ${value}" | zabbix_sender -i - -s "${host}" -z "${zabbixServer}" -vv || {
      # sending values to Zabbix failed
      return 6;
    };
  fi

  # everything went fine
  return 0;
} #; gather_values ()

function tplSmartplugQuery::usage ( ) {
  echo "Usage of "$(basename "${0}")""
  echo "Available command line options:"
  echo "-z: IP address or hostname of a Zabbix server to send the values to"
  echo "-n: IP address or hostname of a TPLink Smartplug to query"
  echo "-h: Print this message"

  return 0;
} #; tplSmartplugQuery::usage ()

# if no commandline options are given, exit
[[ "${#@}" -ne 0 ]] || {
  tplSmartplugQuery::usage
  exit 0;
}; 

declare -i returnCode=-1
# check if getopt can be run in this environment
getopt --test > /dev/null 
returnCode="${?}"

# getopt returns 4 if everything is fine
[[ "${returnCode}" -eq 4 ]] || {
  echo "ERROR: getopt --test failed!";
  exit 1;
};

# parse the commandline options
__PARSED_OPTIONS="$(getopt --options="${__SHORT_OPTIONS}" --longoptions="${__LONG_OPTIONS}" --name "$0" -- "$@")"
[[ "${?}" -eq 0 ]] || {
  echo "ERROR: Parsing commandline options failed!";
  exit 2;
};

# the following has to be done in order to be able to iterate over all parsed commandline options
eval set -- "${__PARSED_OPTIONS}"

# iterate over all commandline options
while true; do
  case "${1}" in
    -h|--help)
      tplSmartplugQuery::usage
      shift

      # assuming nothing more to do once the help is requested
      exit 0;
    ;;
    -n|--hostname)
      __HOSTNAME="$2"
      shift 2
    ;;
    -v|--verbose)
      __VERBOSE=0
      shift
    ;;
    -z|--zabbix-server)
      __ZABBIX_SERVER="${2}"
      shift 2
    ;;
    --)
      shift
      break
    ;;
    *)
      echo "WARNING: Skipping unknown commandline argument: '${1}'"
      shift
    ;;
  esac
done

[[ -n "${__HOSTNAME}" ]] || {
  echo "ERROR: TP-Link Smartplug hostname or IP not given, although required!";
  echo "Please use --hostname <value> or -n <value> to pass the hostname or IP address of the TP-Link Smartplug to this script."
  exit 3;
};

[[ -n "${__ZABBIX_SERVER}" ]] || {
  echo "ERROR: Zabbix server hostname or IP not given, although required!";
  echo "Please use --zabbix-server <value> or -z <value> to pass the hostname or IP address of the Zabbix server to this script."
  exit 4;
};

# initialize the script
tplSmartplugQuery::init

# if any item failed, remember to exit with != 0
declare -i itemFailed=1
declare -a itemFailedReturnCodes=()

# iterate over all items and send the data to Zabbix
for item in "${__ITEMS[@]}"; do
  gather_values "${item}" "${__HOSTNAME}" "${__ZABBIX_SERVER}"
  returnCode="${?}"

  [[ "${returnCode}" -eq 0 ]] || {
    itemFailed=0;
    itemFailedReturnCodes+=("${returnCode}")
  };
done

# at least one item failed, exit accordingly
[[ "${itemFailed}" -ne 0 ]] || {
  echo "ERROR: One or more items failed to either be retrieved from the smartplug or failed to send to the Zabbix server."
  echo "ERROR: Following return codes have been gathered:"
  for rc in "${itemFailedReturnCodes[@]}"; do
    echo " - ${rc}"
  done
  exit 5;
};

exit 0;
#EOF
