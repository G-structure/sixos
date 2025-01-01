#
# mdevd-coldplug is a separate service from mdevd (i.e. rather than using `mdevd
# -C`) for two reasons:
#
# 1. `mdevd -C` doesn't let you pass arguments to mdevd-coldplug.  In
#    particular, the `-O` option is important for backpressure.  Without this
#    option you will frequently overflow the kernel buffer and be forced to
#    increase the `-b` value to obscenely large magic values.
#
# 2. `mdevd -C` will signal its readiness as soon as it is listening on the
#    netlink socket and has forked the child `mdevd-coldplug`.  It does *not*
#    wait for the `mdevd-coldplug` process to terminate before signaling
#    readiness!  Most downstream consumers (seatd, etc) want to wait until
#    `mdevd-coldplug` terminates before they launch.
#
{ lib
, pkgs
, six
, targets
, mdevd ? targets.mdevd or (throw "mdevd missing")
}:
assert !mdevd.passthru.performColdplug;

six.mkOneshot {
  passthru.logger = false;  # loggers require mounting read-write, which requires mdevd
  passthru.essential = true;
  passthru.after = [ mdevd ];
  up = pkgs.writeScript "run"
''
#!${pkgs.runtimeShell}
export PATH=
exec \
  ${lib.getBin pkgs.mdevd}/bin/mdevd-coldplug \
  -v ${toString mdevd.passthru.verbosity} \
  -b ${toString mdevd.passthru.kernelBufferSize} \
  -s ${mdevd.passthru.sysMountPoint} \
  ${lib.optionalString (mdevd.passthru.rebroadcastEvents!=null) " -O ${toString mdevd.passthru.rebroadcastEvents} "}
'';
}
