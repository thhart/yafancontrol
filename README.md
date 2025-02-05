# Fan Control Script

This bash script is designed to control the fan speed on a computer based on temperature thresholds for **Thinkpad
Laptops**. Thinkpad Laptops tend to cap the fan speed at certain level to keep them calm. Unfortunately this leads to
extreme performance loss when the system is under stress. The script has been tested with a Thinkpad Extreme Gen 2.
Let us know when you have used it elsewhere.
The script reads temperature and fan speed information from specified files, and adjusts the fan speed using predefined
levels (auto, high, full) to maintain the desired temperature range. Please be aware of the **Disclaimer**
below.

## Information

**To measure the thresholds the script is starting in a measure mode in the beginning for 60 seconds, fans will spin
high
in this time.**

## Configuration

The script can be configured using a `/etc/yafancontrol/yafancontrol.cfg` file. The available configuration options are:

- `temp_raise`: Temperature threshold (in millidegrees Celsius) at which the script will increase the desired fan speed.
- `temp_lower`: Temperature threshold (in millidegrees Celsius) at which the script will decrease the desired fan speed.
- `temp_kick_in`: Temperature threshold (in millidegrees Celsius) at which the script will activate the fan speed
  control mechanism (kicking in).
- `temp_kick_off`: Temperature threshold (in millidegrees Celsius) at which the script will deactivate the fan speed
  control mechanism (kicking out).
- `verbosity`: Verbosity level of the script. The higher the value, the more detailed the output. Currently level 7
  prints out standard messages, level 8 is spamming out, use with care. Check journalctl for details.

## Disclaimer

This script is provided "as is" without warranty of any kind. The author and copyright holder, Thomas Hartwig, is not
responsible for any damages or issues that may arise from using this script. Use this script at your own risk.

## Note

It is nowhere documented by Lenovo what happens if running the fan beyond the standard threshold, from my expirience
this
should not be an issue at all, but also here the disclaimer applies.
In general running the fan this high is loud and due to the fact of adjusting it to a fixed RPM is is pulsing a bit.  