{ lib
, six
, pkgs
, targets
, minpwm ? 30
, maxpwm ? 255
, mintemp ? 10
, maxtemp ? 40
}:
six.mkFunnel {
  passthru.after = [ targets.global.coldplug ];
  run = pkgs.writeScript "run" ''
#!${pkgs.runtimeShell}
exec 2>&1
modprobe w83795

export PATH=$PATH:${with pkgs; lib.makeBinPath [ gnugrep gnused ]}

# fancontrol gets upset if device paths change, and for some reason the kgpe
# motherboard randomly picks between two possibilities.  So we try both.

CPU0=$(grep -H k10temp /sys/class/hwmon/hwmon?/name | sed 's_.*hwmon/__' | sed 's_/.*__' | head -n1 | tail -n1)
CPU1=$(grep -H k10temp /sys/class/hwmon/hwmon?/name | sed 's_.*hwmon/__' | sed 's_/.*__' | head -n2 | tail -n1)
FANS=$(cd /sys/bus/i2c/drivers/w83795/*-002f/; ls hwmon | sed 's_/__')

echo CPU0=''${CPU0}
echo CPU1=''${CPU1}
echo FANS=''${FANS}

BASE=/sys/devices/pci0000:00/0000:00:14.0/i2c*/*-002f

echo 1 > ''${BASE}/pwm1_enable
#test -e ''${BASE}/hwmon/hwmon6/pwm1_enable && echo 1 > ''${BASE}/hwmon/hwmon6/pwm1_enable
while true; do
    echo
    temp_southbridge=$(sensors w83795g-i2c-1-2f | grep temp1: | sed s_[^C]*\+__ | sed s_\\..*__) 
    temp_cpu1=$(sensors k10temp-pci-00d3 | grep temp1: | sed s_[^C]*\+__ | sed s_\\..*__) 
    temp_cpu2=$(sensors k10temp-pci-00c3 | grep temp1: | sed s_[^C]*\+__ | sed s_\\..*__)
#    temp_southbridge=$(( $(cat ''${TEMP_SOUTHBRIDGE}/temp_cpu1_input) / 1000 ))
#    temp_cpu1=$(( $(cat ''${CPU1}/temp_cpu1_input) / 1000 ))
#    temp_cpu2=$(( $(cat ''${CPU2}/temp_cpu1_input) / 1000 ))
#    echo "cpu3        = "$(( $(cat ''${CPU3}/temp_cpu1_input) / 1000 ))
#    echo "cpu4        = "$(( $(cat ''${CPU4}/temp_cpu1_input) / 1000 ))
#    echo "southbridge = "''${temp_southbridge}""
    echo "southbridge = "''${temp_southbridge}" (ignored)"
    temp_southbridge=$(( ''${temp_southbridge} - 20 ))
#    echo "            = "''${temp_southbridge}" (normalized)"
    echo "cpu1        = "''${temp_cpu1}
    echo "cpu2        = "''${temp_cpu2}
    temp=$(( ''${temp_cpu1} > ''${temp_cpu2} ? ''${temp_cpu1} : ''${temp_cpu2} ))
#    temp=$(( ''${temp}  >''${temp_southbridge} ? ''${temp}   : ''${temp_southbridge} ))
    echo "temp        = "''${temp}
    maxtemp=${toString maxtemp}
    mintemp=${toString mintemp}
    maxpwm=${toString maxpwm}
    minpwm=${toString minpwm}
    pwm_range=$(( ''${maxpwm} - ''${minpwm} ))
    temp_range=$(( ''${maxtemp} - ''${mintemp} ))
    temp=$(( ''${temp} - ''${mintemp} ))
    pwm=$(( ( ( ''${pwm_range} * 1000 * ''${temp} * ''${temp}) / ''${temp_range} / ''${temp_range} ) / 1000 + ''${minpwm} ))
    pwm=$(( ''${pwm} > ''${maxpwm} ? ''${maxpwm} : ''${pwm} ))
    pwm=$(( ''${pwm} < ''${minpwm} ? ''${minpwm} : ''${pwm} ))
    echo "pwm         = "''${pwm}
    echo ''${pwm} > ''${BASE}/pwm1

##############################################################################
#    temp_radeon=$(sensors radeon-pci-0100  | grep temp1: | sed s_[^C]*\+__ | sed s_\\..*__)
#    echo "radeon      = "''${temp_radeon}""
#    temp=''${temp_radeon}
#    maxtemp=50
#    mintemp=39
#    maxpwm=255
##    minpwm=30
#    minpwm=20
#    pwm_range=$(( ''${maxpwm} - ''${minpwm} ))
#    temp_range=$(( ''${maxtemp} - ''${mintemp} ))
#    temp=$(( ''${temp} - ''${mintemp} ))
#    pwm=$(( ( ( ''${pwm_range} * 1000 * ''${temp}) / ''${temp_range} ) / 1000 ))
#    pwm=$(( ''${pwm} > ''${maxpwm} ? ''${maxpwm} : ''${pwm} ))
#    pwm=$(( ''${pwm} < ''${minpwm} ? ''${minpwm} : ''${pwm} ))
##    pwm=255
#    echo "pwm         = "''${pwm}
#    echo ''${pwm} > ''${BASE}/hwmon/hwmon6/pwm1

    echo
sleep 1
done
  '';
}
