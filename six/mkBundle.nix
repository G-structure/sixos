{ lib
, six
, passthru ? {}
}:
six.mkService {
  inherit passthru;
  type = "bundle";
  timeout-up = null;
  timeout-down = null;
  extraCommands = "";
  up = null;
  down = null;
}
