{ lib
, six
, timeout-up ? null   # milliseconds
, timeout-down ? null # milliseconds
, up   ? null
, down ? null
, passthru ? {}
}:
six.mkService {
  inherit timeout-up timeout-down passthru up down;
  type = "oneshot";
  extraCommands = "";
}
