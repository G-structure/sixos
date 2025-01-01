{ lib
, pkgs
, six
, targets
, seatd        ? throw "you must pass sway a seatd target"
, user         ? throw "username under which to run sway"
, extra-groups ? [ ] # extra GIDs to grant to the user
, tty-dev      ? throw "the /dev/tty* device on which to run sway"
, is-mali-gpu  ? throw "fixme"
, sway-config  ? throw "path to the sway configuration file"
, sway-args    ? [ ]  # extra command line arguments for sway
, sway-env     ? { }  # extra environment variables to set

}@args:

# TODO
# - `nice -n -19 ionice -c Realtime` -- but this isn't right because child processes inherit the elevated priority

# useful variables
#export WLR_LIBINPUT_NO_DEVICES=1     # start even if no input devices
#export WLR_DIRECT_TTY=/dev/tty1
#export WLR_RENDERER=gles2
#export LIBGL_DEBUG=1
#export EGL_PLATFORM=gbm
#export EGL_LOG_LEVEL=debug
#export WLR_BACKENDS=libinput,drm
#export WLR_NO_HARDWARE_CURSORS=1
#export WLR_DRM_DEVICES=/dev/dri/card0
#export WLR_RENDERER_ALLOW_SOFTWARE=1
#export MESA_LOADER_DRIVER_OVERRIDE=radeon
#export MESA_DEBUG=1
#export SWAY_ARGS="-d $SWAY_ARGS"
#export SWAY_ARGS=-V
#export SWAY_ARGS="-Dnoatomic"
#export SWAY_ARGS="-Dnoscanout"
#export WLR_RDP_TLS_CERT_PATH=/home/user/sway/tls.crt
#export WLR_RDP_TLS_KEY_PATH=/home/user/sway/tls.key
#export WLR_DRM_NO_ATOMIC=1
#export WLR_DRM_NO_MODIFIERS=1
#export EGL_PLATFORM=gbm
#export MESA_GL_VERSION_OVERRIDE=3.3
#export MESA_GLSL_VERSION_OVERRIDE=330

let

sway-script = pkgs.writeScript "sway-script" (''
#!${pkgs.runtimeShell}
# this directory is not freely chosen; nixpkgs hardwires the string
# below into the RPATHs of several libraries, and configure/meson
# flags of several packages.
MESA_DRIVERS_PATH=/run/opengl-driver

'' + lib.optionalString (sway-env ? WLR_RENDER_DRM_DEVICE) ''
test -e ${sway-env.WLR_RENDER_DRM_DEVICE} || \
  (echo "${sway-env.WLR_RENDER_DRM_DEVICE} does not exist yet; will retry"; exit -1)
${pkgs.busybox}/bin/busybox groups
ls -l ${sway-env.WLR_RENDER_DRM_DEVICE}
'' + ''
exec ${pkgs.sway}/bin/sway ${lib.escapeShellArgs sway-args} -c "${sway-config}"
'');

  # Mali GPU does "one pixel [fragment] per clock", so with a 600mhz GPU
  # each shader core can paint a 4k display at 72hz, or paint at 60hz
  # with on average 1.2 paintings per pixel.  There are four shader
  # cores, so actually you get 4.8 paintings per pixel at 4k@60hz
  gpu-freq =
    #800 * 1000 * 1000
    600 * 1000 * 1000
    #500 * 1000 * 1000
    #400 * 1000 * 1000
    #297 * 1000 * 1000
    #200 * 1000 * 1000
    ;

  gpu-governor =
    if gpu-freq > 600000000
    then "powersave" # 800mhz is stable only when "powersave" governor is used
    else "performance";

in
six.mkFunnel {
  passthru.after = [ targets.global.coldplug seatd ];
  passthru.essential = true;
  run = pkgs.writeScript "run"
(''
  #!${pkgs.runtimeShell}
  exec 2>&1

  # make sure the opengl driver link exists
  ${pkgs.coreutils}/bin/ln -sfT /run/current-system/sw /run/opengl-driver || exit -1

  # swaylock wont start on non-pam systems unless it can read /etc/shadow
  ${pkgs.busybox}/bin/busybox chmod a+r /etc/shadow

'' + lib.optionalString is-mali-gpu ''
  echo ${gpu-governor} > /sys/devices/platform/${"*"}.gpu/devfreq/${"*"}.gpu/governor
  echo ${toString gpu-freq} > /sys/devices/platform/${"*"}.gpu/devfreq/${"*"}.gpu/max_freq
'' + ''

  # create /run/user/$uid just in case
  USER_UID=$(${pkgs.coreutils}/bin/id -u ${user})

  # FIXME use s6-setuidgid here instead
  USER_GROUPS=$(${pkgs.coreutils}/bin/groups ${user} | ${pkgs.gnused}/bin/sed 's_.* : __' | ${pkgs.coreutils}/bin/tr ' ' ':')${lib.concatStrings (map (g: ":${g}") extra-groups)}
  USER_HOME=$(${pkgs.getent}/bin/getent passwd ${user} | ${pkgs.gawk}/bin/awk -F: '{ print $6 }')
  XDG_RUNTIME_DIR=/run/user/$USER_UID/xdg
  ${pkgs.coreutils}/bin/rm -rf $XDG_RUNTIME_DIR
  ${pkgs.coreutils}/bin/mkdir -p $XDG_RUNTIME_DIR
  ${pkgs.coreutils}/bin/chmod 0700 $XDG_RUNTIME_DIR
  ${pkgs.coreutils}/bin/chown -R ${user} /run/user/$USER_UID
'' + lib.optionalString (sway-env ? WLR_RENDER_DRM_DEVICE) ''
  ${pkgs.busybox}/bin/busybox chmod g+rw ${sway-env.WLR_RENDER_DRM_DEVICE} || exit -1
  ls -l ${sway-env.WLR_RENDER_DRM_DEVICE}
'' + ''
  cd "$USER_HOME"
  exec < ${tty-dev}
  exec \
    ${pkgs.coreutils}/bin/env \
    XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
    HOME="$USER_HOME" \
    PATH=/run/current-system/sw/bin \
    ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: lib.escapeShellArg "${k}=${v}") sway-env)} \
    ${pkgs.runit}/bin/chpst -u ${user}:"$USER_GROUPS" -U user:user \
    ${sway-script}
'');
}
