{ lib
, stdenv
, pkgs
, alsaSupport ? !stdenv.hostPlatform.isMips
, modprobe-command ? "/run/current-system/boot/modprobe-wrapped"
, host
}:

# FIXME still need:
/*
# conway
options snd_hda_intel tsched=0 power_save=0

# ostraka
options snd_hda_intel power_save=999 power_save_controller=0 bdl_pos_adj=256
${alsa-utils}/bin/amixer -c HDMI set IEC958,3 unmute
*/

# FIXME: every user/group in mdev.conf needs to appear in /etc/{passwd,group} --
# if not, mdevd will refuse to start (or coldplug)

let
  mdev-like-a-boss =
    let
      pname = "mdev-like-a-boss";
      version = "20200119";
    in
      stdenv.mkDerivation {
        inherit pname version;
        src = pkgs.fetchFromGitHub {
          owner = "slashbeast";
          repo = pname;
          rev = "f77310ea8e039282a545f17df676f2e42f112746";
          hash = "sha256-dGUSyE4/0od7CGM600+51JZZsJtYt1qLK2oSa92blzw=";
        };
        nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
        dontBuild = true;
        installPhase = ''
          runHook preInstall
        '' + lib.optionalString alsaSupport ''
          substituteInPlace helpers/sound-control \
            --replace "alsactl " \
                      "alsactl -f /run/alsa-state "
        '' + ''
          mkdir $out
          mv helpers $out/bin
        '' + lib.optionalString alsaSupport ''
          wrapProgram $out/bin/sound-control  --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils alsa-utils ]}
        '' + lib.optionalString (!alsaSupport) ''
          rm -f $out/bin/sound-control
        '' + ''
          wrapProgram $out/bin/settle-nics    --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils iproute2 nettools]}
          wrapProgram $out/bin/dev-bus-usb    --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils gnugrep ]}
          wrapProgram $out/bin/storage-device --prefix PATH : ${with pkgs; lib.makeBinPath [ coreutils gawk util-linux ]}
          chmod +x $out/bin/*
          runHook postInstall
        '';
      };
  helpers = "${mdev-like-a-boss}/bin";
  busybox = "${pkgs.busybox}/bin/busybox ";
in
pkgs.writeText "mdevd-conf" (''
# mdev-like-a-boss

# Syntax:
# [-]devicename_regex user:group mode [=path]|[>path]|[!] [@|$|*cmd args...]
# [-]$ENVVAR=regex    user:group mode [=path]|[>path]|[!] [@|$|*cmd args...]
# [-]@maj,min[-min2]  user:group mode [=path]|[>path]|[!] [@|$|*cmd args...]
#
# [-]: do not stop on this match, continue reading mdev.conf
# =: move, >: move and create a symlink
# !: do not create device node
# @|$|*: run cmd if $ACTION=remove, @cmd if $ACTION=add, *cmd in all cases

-.* root:root 660 ! *${busybox} sh -c '(${busybox}/env | ${busybox}/sort; echo) >> /run/mdevd-events.log'

# support module loading on hotplug
$MODALIAS=.*    root:root 660 @${modprobe-command} "$MODALIAS"

# null may already exist; therefore ownership has to be changed with command
null        root:root 666 @${busybox} chmod 666 $MDEV
zero        root:root 666
full        root:root 666
random      root:root 444
urandom     root:root 444
hwrandom    root:root 444
grsec       root:root 660

# Kernel-based Virtual Machine.
kvm     root:kvm 660

# vhost-net, to be used with kvm.
vhost-net   root:kvm 660

kmem        root:root 640
mem         root:root 640
port        root:root 640
# console may already exist; therefore ownership has to be changed with command
console     root:tty 600 @${busybox} chmod 600 $MDEV
ptmx        root:tty 666
pty.*       root:tty 660

# Typical devices
tty         root:tty 666
tty[0-9]*   root:tty 660
vcsa*[0-9]* root:tty 660
ttyS[0-9]*  root:uucp 660

# block devices
ram([0-9]*)        root:disk 660 >rd/%1
loop([0-9]+)       root:disk 660 >loop/%1
sr[0-9]*           root:cdrom 660 @${busybox} ln -sf $MDEV cdrom
fd[0-9]*           root:floppy 660
SUBSYSTEM=block;.* root:disk 660 *${helpers}/storage-device

# Run settle-nics every time new NIC appear.
# If you don't want to auto-populate /etc/mactab with NICs, run 'settle-nis' without '--write-mactab' param.
#-SUBSYSTEM=net;DEVPATH=.*/net/.*;.*     root:root 600 @${helpers}/settle-nics --write-mactab

net/tun[0-9]*   root:kvm 660
net/tap[0-9]*   root:root 600

'' + lib.optionalString alsaSupport ''
# alsa sound devices and audio stuff
SUBSYSTEM=sound;.*  root:audio 660 @${helpers}/sound-control
'' + ''

adsp        root:audio 660 >sound/
audio       root:audio 660 >sound/
dsp         root:audio 660 >sound/
mixer       root:audio 660 >sound/
sequencer.* root:audio 660 >sound/


# raid controllers
cciss!(.*)  root:disk 660 =cciss/%1
ida!(.*)    root:disk 660 =ida/%1
rd!(.*)     root:disk 660 =rd/%1


fuse        root:root 666

card[0-9]   root:video 660 =dri/
dri/.*      root:video 660

agpgart     root:root 660 >misc/
psaux       root:root 660 >misc/
rtc         root:root 664 >misc/


# input stuff
SUBSYSTEM=input;.* root:input 660


# v4l stuff
vbi[0-9]    root:video 660 >v4l/
video[0-9]  root:video 660 >v4l/

# dvb stuff
dvb.*       root:video 660

# Don't create old usbdev* devices.
usbdev[0-9].[0-9]* root:root 660 !

# Stop creating x:x:x:x which looks like /dev/dm-*
[0-9]+\:[0-9]+\:[0-9]+\:[0-9]+ root:root 660 !

# /dev/cpu support.
microcode       root:root 600 =cpu/
cpu([0-9]+)     root:root 600 =cpu/%1/cpuid
msr([0-9]+)     root:root 600 =cpu/%1/msr

# Populate /dev/bus/usb.
-SUBSYSTEM=usb;DEVTYPE=usb_device;.* root:root 660 *${helpers}/dev-bus-usb

'' + lib.optionalString (host.name == "ostraka") ''
# gnuk
SUBSYSTEM=usb;PRODUCT=234b/0/200;.* user:user 660
'' + ''

# Catch-all other devices, Right now useful only for debuging.
#.* root:root 660 *${helpers}/catch-all

'')
