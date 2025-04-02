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

BASE=/sys/devices/pci0000:00/0000:00:14.0/i2c*/*-002f

echo 1 > ''${BASE}/pwm1_enable
#test -e ''${BASE}/hwmon/hwmon6/pwm1_enable && echo 1 > ''${BASE}/hwmon/hwmon6/pwm1_enable
while true; do
    echo
    temp_southbridge=$(${pkgs.lm_sensors}/bin/sensors w83795g-i2c-1-2f | grep temp1: | sed s_[^C]*\+__ | sed s_\\..*__) 
    temp_cpu0=$( ${pkgs.lm_sensors}/bin/sensors k10temp-pci-00c3                                      | grep temp1: | sed s_[^C]*\+__ | sed s_\\..*__)
    temp_cpu1=$((${pkgs.lm_sensors}/bin/sensors k10temp-pci-00d3 2>/dev/null || echo 'temp1: +0.0°C') | grep temp1: | sed s_[^C]*\+__ | sed s_\\..*__)
    echo "southbridge = "''${temp_southbridge}" (ignored)"
    temp_southbridge=$(( ''${temp_southbridge} - 20 ))
    echo "cpu0        = "''${temp_cpu0}
    echo "cpu1        = "''${temp_cpu1}
    temp=$(( ''${temp_cpu1} > ''${temp_cpu0} ? ''${temp_cpu1} : ''${temp_cpu0} ))
   #temp=$(( ''${temp}  >''${temp_southbridge} ? ''${temp}   : ''${temp_southbridge} ))
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
    echo
    sleep 1
done
  '';
}
