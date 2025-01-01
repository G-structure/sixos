{ lib
, pkgs
, six
, targets
, interval-seconds ? 60
}:
six.mkFunnel {
  passthru.after = with targets; [ global.coldplug ];
  run = [
    "${pkgs.p.lascar-usb-thermometer}/bin/lascar-usb-thermometer"
    "-f"
  ];
  timeout-finish = "${toString ((interval-seconds+1) * 1000)}";
  finish = [
    "${pkgs.busybox}/bin/busybox"
    "sleep"
    (toString interval-seconds)
  ];
}
