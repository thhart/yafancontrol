#!/bin/bash

# Copyright (c) 2023 Thomas Hartwig
#
# Disclaimer: This script is provided "as is" without warranty of any kind. The author and
# copyright holder, Thomas Hartwig, is not responsible for any damages or issues that may arise
# from using this script. Use this script at your own risk.

temp_raise=86000
temp_lower=84000
temp_kick_in=84000
temp_kick_off=74000
verbosity=9
temp_file="/sys/devices/virtual/thermal/thermal_zone0/temp"
fan_file="/proc/acpi/ibm/fan"

# Load the variables from the configuration file if it exists
config_file="yafancontrol.cfg"
if [ -f "$config_file" ]; then
  source "$config_file"
  # or use the dot operator:
  # . yafancontrol.cfg
fi

# Check the plausibility of the variables
if [[ $temp_raise -lt $temp_lower || $temp_kick_in -lt $temp_kick_off || $verbosity -lt 0 ]]; then
  echo "Error: Invalid configuration values. Please check the config file and try again."
  exit 1
fi

fan_level_auto="level auto"
fan_level_high="level 7"
fan_level_full="level disengaged"
fan_level_off="level 0"
fan_level="$fan_level_auto"
kicked=false
current=5000

# Check if the required files exist
if [ ! -f "$temp_file" ]; then
  echo "Error: Temperature file not found ($temp_file). Please check your system configuration and try again."
  exit 1
fi

if [ ! -f "$fan_file" ]; then
  echo "Error: Fan control file not found ($fan_file). Please check your system configuration and try again."
  exit 1
fi

if [ $verbosity -ge 7 ]; then
  echo "Measuring fan thresholds"
fi

# Measure minimum and maximum fan speeds
echo $fan_level_high >$fan_file
sleep 20
minimum=$(cat $fan_file | grep 'speed:' | awk '{print $2}')
if [ $verbosity -ge 7 ]; then
  echo "Using as minimum speed: $minimum"
fi

echo $fan_level_full >$fan_file
sleep 30
maximum=$(cat $fan_file | grep 'speed:' | awk '{print $2}')
if [ $verbosity -ge 7 ]; then
  echo "Using as maximum speed: $maximum"
fi

# Set the fan back to auto mode after measuring
echo $fan_level_auto >$fan_file

function set_fan_level {
  if [ "$fan_level" != "$1" ]; then
    if [ $verbosity -ge 7 ]; then
      echo "Setting speed: $1"
    fi
    echo -n "$1" >"$fan_file"
    fan_level="$1"
  fi
}

function cleanup {
  echo "Restoring fan control to auto mode..."
  set_fan_level "$fan_level_auto"
  exit 0
}

# Register the kill handler for SIGINT and SIGTERM signals
trap cleanup SIGINT SIGTERM

# Main loop
while true; do
  temp=$(cat $temp_file)
  fan=$(cat $fan_file | grep 'speed:' | awk '{print $2}')
  t=$(($temp / 1000))

  if [ $verbosity -ge 8 ]; then
    echo "Temperature read: $t°"
    echo "Fan speed read: $fan RPM"
  fi

  if [ $temp -gt $temp_kick_in ] && ! $kicked; then
    kicked=true
    [ $verbosity -ge 7 ] && echo "Kicking in at $t"
  fi

  if [ $temp -lt $temp_kick_off ] && $kicked == true; then
    kicked=false
    [ $verbosity -ge 7 ] && echo "Kicking out at $t"
  fi

  if $kicked; then
    if [ $temp -gt $temp_raise ]; then
      current=$(($current + 200))
      current=$(($current > $maximum ? $maximum : $current))
      [ $verbosity -ge 7 ] && echo "Raising: $current"
    fi

    if [ $temp -lt $temp_lower ]; then
      current=$(($current - 200))
      current=$(($current < $minimum ? $minimum : $current))
      [ $verbosity -ge 7 ] && echo "Lowering: $current"
    fi

    if [ $fan -lt $(($current - $current / 40)) ]; then
      set_fan_level "$fan_level_full"
    elif [ $fan -gt $current ]; then
      set_fan_level "$fan_level_high"
    fi
  elif [ "$fan_level" != "$fan_level_auto" ]; then
    set_fan_level "$fan_level_auto"
  fi

  sleep 1
done
