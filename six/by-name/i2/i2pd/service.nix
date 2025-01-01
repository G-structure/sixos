{ lib
, six
, pkgs
, targets
, package ? pkgs.i2pd
, user-name ? "i2pd"
, group-name ? "i2pd"
, datadir ? throw "datadir is required"
, bandwidth-kbytes-per-second ? throw "required"
, listen-ip ? throw "required"
, http-proxy-listen ? null
, http-proxy-port ? 4444
, socks-proxy-listen ? null
, socks-proxy-port ? 7777
, sam-address-listen ? null
, sam-address-port ? 7656
, extra-args ? []
}:
let
  args = [
      # chpst
      "-u" "${user-name}:${group-name}"
      "-U" "${user-name}:${group-name}"
      # recommended by https://i2pd.readthedocs.io/en/latest/user-guide/run/
      "-o" "4096"

      "${package}/bin/i2pd"

      "--log" "stdout"
      "--conf" "/dev/null"
      "--bandwidth" (toString bandwidth-kbytes-per-second)
      "--host" listen-ip
      "--datadir" datadir
    ] ++ lib.optionals (http-proxy-listen != null) [
      "--httpproxy.enabled" "1"
      "--httpproxy.address" http-proxy-listen
      "--httpproxy.port" (toString http-proxy-port)
    ] ++ lib.optionals (socks-proxy-listen != null) [
      "--socksproxy.enabled" "1"
      "--socksproxy.address" socks-proxy-listen
      "--socksproxy.port" (toString socks-proxy-port)
    ] ++ lib.optionals (sam-address-listen != null) [
      "--sam.address" sam-address-listen
      "--sam.port" (toString sam-address-port)
    ] ++ extra-args;
in
six.mkFunnel {
  run = pkgs.writeScript "run"
''
#!${pkgs.runtimeShell}
exec 2>&1

# FIXME: ugly
${pkgs.shadow}/bin/useradd \
  --system \
  --shell /run/current-system/sw/bin/nologin \
  --no-create-home \
  --force-badname \
  ${lib.escapeShellArg user-name} \
  < /dev/null 2>/dev/null || true

export HOME=$(${pkgs.getent}/bin/getent passwd ${user-name} | cut -f6 -d:)
cd $HOME
exec ${pkgs.runit}/bin/chpst ${lib.escapeShellArgs args}
'';
}
