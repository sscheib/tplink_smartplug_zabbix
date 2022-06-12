#!/bin/bash

###
# Description:
#   Queries a TP-Link Smartplug and sends the data to a Zabbix server.
#   Currently supported models:
#     - HS110 (EU)
#     - KP115 (EU)
#  
# Exit codes:
#   0: Successfully queried TP-Link Smartplug and send the data to Zabbix server
#   1: getopt --test failed
#   2: Failed to parse commandline options
#   3: TP-Link Smartplug hostname or IP address not given
#   4: Zabbix server hostname or IP address not given
#   5: Initialization of the script failed
#   6: Failed to retrieve or send an item from Smartplug/to Zabbix server
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
# 12.06.2022:
#  + Added the possibility to specify the name of the host object in Zabbix from the smartplug
#    Note: If not specified, it will use the value passed via -n/--host
#  - Fixed documentation of tplSmartplugQuery::gather_values
#  - Minor fixes
#  ~ Bumped version to 1.5
#
# 25.05.2022:
#  - Removed unnecessary call to unset mapItem 
#  - Fixed documentation of tplSmartplugQuery::gather_values
#  ~ Bumped version to 1.4
#
# 24.05.2022:
#  ~ Renamed function gather_values to tplSmartplugQuery::gather_values to be consistent throughout 
#    the code
#  ~ Redirect error output to stderr
#  ~ Added support for TP-Link KP115 (EU)
#  ~ Bumped version to 1.3
#  
#
# 24.05.2022:
#  + Added the ability to use the environment variable VERBOSE to enable
#    verbostity (additionally to --verbose)
#  ~ Bumped version to 1.2
# 
# 23.05.2022:
#  + Added check for the return code of tplSmartplugQuery::init
#  + Introduced exit code in case tplSmartplugQuery::init fails
#  ~ Changed previously exit code 5 to 6 in order to be consistent throughout the exit codes
#  ~ Bumped version to 1.1
#
# 23.05.2022: . Initial
#
# version: 1.5
VERSION=1.5

# option definitions for getopt
__LONG_OPTIONS="host:,zabbix-host:,zabbix-server:,help,verbose"
__SHORT_OPTIONS="n:,a:,z:,h,v"

# verbose output, disabled by default
declare -i __VERBOSE=1
[[ -z "${VERBOSE}" ]] || {
  __VERBOSE=0
}

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

# holds additional (to those defined in __ITEMS) items per hardware model
# format: ["<hw_model>"]="<item>[:<mapped_to>],<item>[:<mapped_to>],<item>"
# Note:
#   - <hw_model> is the model name as determined in tplSmartplugQuery::determine_hardware_model
#   - the optional <:mapped_to> sets the retrieved value to the item specified after the colon 
#     in the Zabbix template
#     -> Example: "mic_type:model", will map the value of 'mic_type' to the Zabbix item 'model'
declare -Ar __HARDWARE_MODEL_ADDITIONAL_ITEMS=(
  ["KP115_EU_"]="mic_type:type,ntc_state,obd_src,status"
) 

# defines the number of lines to retrieve from 'kasa sysinfo'
# format: ["<hw_model>"]="<num_lines>"
# Note:
#   - <hw_model> is the model name as determined in tplSmartplugQuery::determine_hardware_model
#   - <num_lines> specifies the number of lines to gather from 'kasa sysinfo'
declare -Ar __HARDWARE_MODEL_NUM_RETRIEVE_LINES=(
  ["HS110_EU_"]=23
  ["KP115_EU_"]=25
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
# used to store the hardware model
declare __HARDWARE_MODEL=""
# used to store the number of lines to retrieve when using 'kasa sysinfo'
declare -i __NUM_RETRIEVE_LINES=-1

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
#   02 | __HOSTNAME                                    | read        | --
#   03 | __HARDWARE_MODEL_NUM_RETRIEVE_LINES           | read        | --
#   04 | __HARDWARE_MODEL                              | read        | --
#   05 | __NUM_RETRIEVE_LINES                          | read/write  | --
#   06 | __HARDWARE_MODEL_ADDITIONAL_ITEMS             | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | If all conditions to run this script are met
# (return)   1 | If one or more binaries defined in __REQUIRED_BINARIES are missing
# (return)   2 | If we were unable to determine the hardware model 
# (return)   3 | If __HARDWARE_MODEL is not (properly) defined in __HARDWARE_MODEL_NUM_RETRIEVE_LINES
# (return)   4 | If a malformed item in __HARDWARE_MODEL_ADDITIONAL_ITEMS is found
#####
function tplSmartplugQuery::init () {
  for binary in "${__REQUIRED_BINARIES[@]}"; do
    command -v "${binary}" &> /dev/null || {
      echo "ERROR: Binary '${binary}' is not installed, but required by this script!" >&2; 
      return 1; 
    };
  done

  declare -i returnCode=-1
  # determine hardware model
  tplSmartplugQuery::determine_hardware_model "${__HOSTNAME}"
  returnCode="${?}"
  [[ "${returnCode}" -eq 0 ]] || {
    return 2;
  };

  # set the lines to retrieve according to the hardware model
  for model in "${!__HARDWARE_MODEL_NUM_RETRIEVE_LINES[@]}"; do
    [[ "${model}" =~ ${__HARDWARE_MODEL} ]] || {
      continue;
    };

    # found hardware model
    __NUM_RETRIEVE_LINES="${__HARDWARE_MODEL_NUM_RETRIEVE_LINES["${model}"]}"    
  done

  # __NUM_RETRIEVE_LINES should differ by now from the default of -1
  [[ "${__NUM_RETRIEVE_LINES}" -ne -1 ]] || {
    return 3;
  };

  declare -i malformedItemFound=1
  for item in "${__HARDWARE_MODEL_ADDITIONAL_ITEMS[@]}"; do
    [[ "${item}" =~ ^([[:alnum:]_]+):?([[:alnum:]_]+,?){1,}$ ]] || {
      echo "ERROR: Item definition in __HARDWARE_MODEL_ADDITIONAL_ITEMS malformed!" >&2;
      echo "ERROR: The following line seems to be malformed:" >&2;
      echo " line: '${item}'" >&2;
      malformedItemFound=0;
    };
  done

  [[ "${malformedItemFound}" -ne 0 ]] || {
    return 4;
  };

  return 0;
}; # function tplSmartplugQuery::init ( )


###
# function tplSmartplugQuery::gather_values
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
#<  $4> | zabbixHost                            | string      | Name of the host object in Zabbix for the smartplug
#[  $5] | mapItem                               | string      | Name of the key the item should be mapped to
#---
# Global variables:
#---
#   #  | name                                          | access-type | notes
#------+-----------------------------------------------+-------------+-------------------------------------------------< 
#   01 | __ENERGY_METER                                | read/write  | Variable to store the queried data from emeter
#   02 | __SYSTEM_INFO                                 | read/write  | Variable to store the queried data from sysinfo
#   03 | __NUM_RETRIEVE_LINES                          | read        | --
#   03 | __VERBOSE                                     | read        | --
#---
# Return values:
#---
# return code  | description
#--------------+-------------------------------------------------------------------------------------------------------< 
# (return)   0 | Value of given item successfully transmitted to the Zabbix server
# (return)   1 | Parameter $1 (item) not given
# (return)   2 | Parameter $2 (host) not given
# (return)   3 | Parameter $3 (zabbixServer) not given
# (return)   4 | Parameter $4 (zabbixHost) not given
# (return)   5 | Sending values to Zabbix failed
#####
function tplSmartplugQuery::gather_values() {
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

  [[ -n "${4}" ]] || {
    return 4;
  };
  declare zabbixHost="${4}"

  # set the mapItem as default to the retrieving item and override if $5 is given
  declare mapItem="${item}"
  [[ -z "${5}" ]] || {
    mapItem="${5}"
  };

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
    # all other values should be retrievable via kasa sysinfo
    *)
      # query the smartplug only if __SYSTEM_INFO is empty
      [[ -n "${__SYSTEM_INFO}" ]] || {
        __SYSTEM_INFO="$(kasa --type plug --host "${host}" sysinfo)";
      };

      # get the last lines from sysinfo, replace ' with " (to have proper json) and get the value for the provided key
      value="$(echo "${__SYSTEM_INFO}" | tail -n "${__NUM_RETRIEVE_LINES}" | tr "\'" "\"" | jq -r ".${item}")"

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
  esac

  if [[ "${__VERBOSE}" -ne 0 ]]; then
    echo "- tplink_smartplug[${mapItem}] ${value}" | zabbix_sender -i - -s "${zabbixHost}" -z "${zabbixServer}" >> /dev/null || {
      # sending values to Zabbix failed
      return 5;
    };
  else
    echo "- tplink_smartplug[${mapItem}] ${value}" | zabbix_sender -i - -s "${zabbixHost}" -z "${zabbixServer}" -vv || {
      # sending values to Zabbix failed
      return 5;
    };
  fi

  # everything went fine
  return 0;
} #; tplSmartplugQuery::gather_values ( <item>, <host>, <zabbixServer>, <zabbixHost> [mapItem] )

function tplSmartplugQuery::determine_hardware_model () {
  [[ -n "${1}" ]] || {
    return 1;
  };
  declare host="${1}"
  # query the smartplug only if __SYSTEM_INFO is empty
  [[ -n "${__SYSTEM_INFO}" ]] || {
    __SYSTEM_INFO="$(kasa --type plug --host "${host}" sysinfo)";
  }

  # retrieve the hardware model
  __HARDWARE_MODEL="$(echo "${__SYSTEM_INFO}" | grep -E "^[[:space:]]+'model':" | awk '{print $2}')"
  
  # sanitize the hardware model:
  # - remove trailing comma
  # - remove all occurrences of '
  # - replace all characters but alphanumeric ones (0-9 + A-z) with an underscore
  # Example:
  # HS110(EU) -> HS110_EU_
  # KP115(EU) -> KP115_EU_
  __HARDWARE_MODEL="$(echo "${__HARDWARE_MODEL}" | sed 's/,//' | tr -d "'" | sed 's/[^[:alnum:]]/_/g')"
  [[ -n "${__HARDWARE_MODEL}" ]] || {
    return 2;
  };
  
  # everything went fine
  return 0;
} #; tplSmartplugQuery::determine_hardware_model ( <host> )

function tplSmartplugQuery::usage ( ) {
  echo "Usage of "$(basename "${0}")""
  echo "Available command line options:"
  echo "--zabbix-server OR -z: IP address or hostname of a Zabbix server to send the values to"
  echo "--host OR -n         : IP address or hostname of a TPLink Smartplug to query"
  echo "--zabbix-host OR -a  : Name of the TPLink Smartplug host object in Zabbix"
  echo "--verbose OR -v      : Verbose output"
  echo "--help OR -h         : Print this message"

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
  echo "ERROR: getopt --test failed!" >&2;
  exit 1;
};

# parse the commandline options
__PARSED_OPTIONS="$(getopt --options="${__SHORT_OPTIONS}" --longoptions="${__LONG_OPTIONS}" --name "$0" -- "$@")"
[[ "${?}" -eq 0 ]] || {
  echo "ERROR: Parsing commandline options failed!" >&2;
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
    -n|--host)
      __HOSTNAME="${2}"
      shift 2
    ;;
    -a|--zabbix-host)
      __ZABBIX_HOST="${2}"
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
  echo "ERROR: TP-Link Smartplug hostname or IP not given, although required!" >&2;
  echo "Please use --host <value> or -n <value> to pass the hostname or IP address of the TP-Link Smartplug to this script." >&2;
  exit 3;
};

[[ -n "${__ZABBIX_SERVER}" ]] || {
  echo "ERROR: Zabbix server hostname or IP not given, although required!" >&2;
  echo "Please use --zabbix-server <value> or -z <value> to pass the hostname or IP address of the Zabbix server to this script." >&2;
  exit 4;
};

[[ -n "${__ZABBIX_HOST}" ]] || {
  echo "WARNING: Name of the TPLink Smartplug Zabbix host has not been given, will use given --host/-n value ('${__HOSTNAME}')" >&2;
  __ZABBIX_HOST="${__HOSTNAME}"
};

# initialize the script
tplSmartplugQuery::init
returnCode="${?}"
[[ "${returnCode}" -eq 0 ]] || {
  exit 5;
};

# if any item failed, remember to exit with != 0
declare -i itemFailed=1
declare -a itemFailedReturnCodes=()

# iterate over all default items and send the data to Zabbix
for item in "${__ITEMS[@]}"; do
  tplSmartplugQuery::gather_values "${item}" "${__HOSTNAME}" "${__ZABBIX_SERVER}" "${__ZABBIX_HOST}"
  returnCode="${?}"

  [[ "${returnCode}" -eq 0 ]] || {
    itemFailed=0;
    itemFailedReturnCodes+=("${returnCode}")
  };
done

# iterate over all "special" items - if the model has any
for model in "${!__HARDWARE_MODEL_ADDITIONAL_ITEMS[@]}"; do
  [[ "${model}" =~ ${__HARDWARE_MODEL} ]] || {
    continue;
  };

  declare itemList="${__HARDWARE_MODEL_ADDITIONAL_ITEMS["${model}"]}"
  # read in the itemList as array with the field seperator ','
  IFS="," read -ra items <<< "${itemList}"

  # iterate over the items
  for item in "${items[@]}"; do
    # set the mapItem to be item by default and override it only if required
    mapItem="${item}"

    # extract the mapped value if present
    [[ ! "${item}" =~ : ]] || {
      mapItem="$(echo "${item}" | awk -F ':' '{print $2}')"
      item="$(echo "${item}" | awk -F ':' '{print $1}')"
    };

    # finally gather and send the values to Zabbix    
    tplSmartplugQuery::gather_values "${item}" "${__HOSTNAME}" "${__ZABBIX_SERVER}" "${__ZABBIX_HOST}" "${mapItem}"
    returnCode="${?}"
    [[ "${returnCode}" -eq 0 ]] || {
      itemFailed=0;
      itemFailedReturnCodes+=("${returnCode}")
    };
  done
done

# at least one item failed, exit accordingly
[[ "${itemFailed}" -ne 0 ]] || {
  echo "ERROR: One or more items failed to either be retrieved from the smartplug or failed to send to the Zabbix server." >&2;
  echo "ERROR: Following return codes have been gathered:" >&2;

  # iterate over all gathered return codes
  for rc in "${itemFailedReturnCodes[@]}"; do
    echo " - ${rc}" >&2
  done

  exit 6;
};

exit 0;
#EOF
