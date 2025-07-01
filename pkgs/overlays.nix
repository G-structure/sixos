{
  lib,
  infuse,
}:
let
  mkBroken = { __output.meta.broken.__assign = true; };

in [

  (final: prev: infuse prev ({

    # replace systemd/udev with libudev-zero
    systemdMinimal.__assign = prev.libudev-zero;
    systemd.__assign = prev.libudev-zero;
    udev.__assign = prev.libudev-zero;

    # requires umockdev, which requires udev
    libgudev.__output.doCheck.__assign = false;
    openssh.__input = {
      etcDir.__assign = "/etc";
      withKerberos.__assign = false;
      withFIDO.__assign = false;
      withPAM.__assign = false;
      pam.__assign = null;
    };

    lvm2.__input.udevSupport.__assign = false;
    lvm2.__output.configureFlags.__append = [
      "--disable-udev_sync"
      "--enable-udev_rules"
      "--enable-udev-rule-exec-detection"
    ];

    # atk
    atkSupport.__assign = false;

    # avahi
    avahiSupport.__assign = false;

    # pipewire
    pipewireSupport.__assign = false;
    withPipewireLib.__assign = false;

    # PAM
    usePam.__assign = false;
    shadow.__input.pam.__assign = null;
    doas.__input.withPAM.__assign = false;

    # PulseAudio
    pulseaudioSupport.__assign = false;
    withPulse.__assign = false;
    withPulseAudio.__assign = false;
    pulseSupport.__assign = false;
    usePulseAudio.__assign = false;
    libpulseaudio.__assign = null;

    # systemd
    systemdSupport.__assign = false;
    enableSystemd.__assign = false;

    # polkit
    enablePolkit.__assign = false;
    withPolkit.__assign = false;
    polkitSupport.__assign = false;

    # dbus
    dbusSupport.__assign = false;
    withDbus.__assign = false;

    gssSupport.__assign = false;

    qt6.dbus.dbusSupport.__assign = false;
    bluezSupport.__assign = false;
    pamSupport.__assign = false;    # getting headaches from util-linux lately

    umockdev.__assign = null;

    secretstorage.__assign = null;  # for yt-dlp
    withGnome.__assign = false;
    enableGeoLocation.__assign = false;

    withLibsecret.__assign = false;
    openalSupport.__assign = false;

    # there are too many packages that don't check the withsupport
    # options for these, so we null them out:
    #pcsclite             .__assign = null;
    aalib                .__assign = null;   # broken on powerpc

    nmap.__input.withLua.__assign = false;

    flite.__input.audioBackend.__assign = "alsa";
    remmina.__input.at-spi2-core.__assign = null;
    remmina.__input.libdbusmenu-gtk3.__assign = null;
    girara.__input.dbus.__assign = null;
    libhandy.__input.at-spi2-atk.__assign = null;
    libhandy.__input.at-spi2-core.__assign = null;
    electrum.__input.enablePlugins.__assign = false;
    gpsd.__input.pythonSupport.__assign = false;
    gpsd.__input.guiSupport.__assign = false;
    gpsd.__input.dbusSupport.__assign = false;
    gpsd.__input.minimal.__assign = true;
    msmtp.__input.withKeyring.__assign = false;
    libftdi1.__input.docSupport.__assign = false;    # drags in X11, wtf?
    libdecor.__input.dbus.__assign = null;
    libdecor.__output.mesonFlags.__append = [ "-Ddbus=disabled" ];
    gtk3.__input.trackerSupport.__assign = false;
    gtk4.__input.trackerSupport.__assign = false;
    transmission-remote-gtk.__input.libappindicator.__assign = null;
    tiny.__input.useOpenSSL.__assign = false;
    tiny.__input.notificationSupport.__assign = false;
    sqlite.__input.interactive.__assign = true;

    # huge closure bloat
    nfs-utils.__input.enablePython.__assign = false;

    notmuch.__input.withEmacs.__assign = false;
    notmuch.__input.withRuby.__assign = false;  # cross wont build
    notmuch.__input.withSfsexp.__assign = false;  # cross wont build
    notmuch.__input.withVim.__assign = false;  # cross wont build
    gnupg24.__input = {
      guiSupport.__assign = false;
      withTpm2Tss.__assign = false;
      adns.__assign = null; bzip2.__assign = null; gnutls.__assign = null; openldap.__assign = null;
      sqlite.__assign = null; tpm2-tss.__assign = null;
    };
    pinentry.__input.enabledFlavors.__assign = [ "curses" "tty" ];
    qutebrowser.__input.withPdfReader.__assign = false;
    #SDL2.__input.udevSupport.__assign = false;
    mpv-unwrapped.__input.javascriptSupport.__assign = false;
    mpv-unwrapped.__input.openalSupport.__assign = false;
    evince.__input.supportMultimedia.__assign = false;
    #ripgrep.__input.asciidoctor.__assign = null;     # drags in all of ruby
    util-linux.__input.translateManpages.__assign = false;

    # libcardiacarrest assumes libpulseaudio.meta.license exists
    libcardiacarrest.__output.meta.license.__assign = [];
    cosmic-applets.__input.pulseaudio.__assign = final.libcardiacarrest;

    xdg-utils.__input.perlPackages.NetDBus.__assign = null;

    # libgcrypt's "jitter entropy generator" gets fussy if you build
    # it with any optimizations.  I don't trust crap like that.
    libgcrypt.__output.configureFlags.__append = [ "--disable-jent-support" ];

    busybox.__output.patches.__append = [
      ./patches/busybox/modprobe-dirname-flag.patch
    ];

    lvm2.__output.patches.__append = [
      (final.fetchpatch {
        name = "lvm-lvresize-btrfs-support-from-suse.patch";
        url = "https://code.opensuse.org/package/lvm2/raw/master/f/fate-31841-01_fsadm-add-support-to-resize-check-btrfs-filesystem.patch";
        hash = "sha256-dPbRPkKIgIKnMrdqZp63LRHfw9Yt+KGxiChqtqd4j9M=";
      })
    ];

    skawarePackages.s6-rc.__output.patches.__append = [
      ./patches/s6-rc/0001-doc-s6-rc-compile.html-document-bundle-flattening.patch
      ./patches/s6-rc/0002-doc-define-singleton-bundle-document-special-rules.patch
      ./patches/s6-rc/0003-libs6rc-s6rc_graph_closure.c-add-comments-explaining.patch
      ./patches/s6-rc/0004-s6-rc-update.c-add-define-constants-for-bitflags.patch
      ./patches/s6-rc/0005-s6-rc-update.c-rewrite-O-n-2-loop-as-O-n-complexity.patch
      ./patches/s6-rc/0006-WIP-s6-rc-update.c-add-additional-comments.patch
      #./patches/s6-rc/0007-Revert-Simplify-selfpipe-management.patch
      ./patches/s6-rc/0008-s6-rc-update.c-bugfix-for-failure-to-create-pipe-s6r.patch
      ./patches/s6-rc/0009-add-OLDSTATE_UNPROPAGATED_RESTART.patch
      ./patches/s6-rc/0010-disable-restart-if-acquired-new-dependency-behavior.patch
    ];

    abduco.__output.patches      .__append =  [ ./patches/abduco/dont-use-alternate-buffer.patch ];

    # sway/seatd

    swaylock.__output.patches.__append = [
      #
      # cherry-pick two patches that allow /etc/shadow to be world-readable
      # instead of having to make swaylock setuid-root
      #
      (final.fetchpatch {
        url = "https://github.com/swaywm/swaylock/commit/b63aaffcd17b4115aa779e49016c6c4dcf06ecd9.patch";
        hash = "sha256-ADKZ08shDRjtmxf3z88Yc4JocebQcMhy2kYMTO+YjOg=";
      })
      (final.fetchpatch {
        url = "https://github.com/swaywm/swaylock/commit/f9ce3f193bc2f035790372b550547686075f4923.patch";
        hash = "sha256-gl07xPOpdALmNEEkP5Xp8Sc6rRh2+leLqIai9Rkqo1I=";
      })
    ];

    gst_all_1.gst-plugins-good.__output.mesonFlags.__append = [ "-Daalib=disabled" ];

    # expose p.libhid as libhid
    libhid.__assign = final.p.libhid;

    cryptsetup.__output.enableParallelBuilding.__assign = true;

    libressl.__output.enableParallelBuilding.__assign = true;
    libressl.__output.doCheck.__assign = false;

    # nullify overrides in pkgs/top-level/all-packages.nix
    wireshark.__input.libpcap.__input.withBluez.__assign = false;
    wireshark-cli.__input.libpcap.__input.withBluez.__assign = false;

    inetutils.__output.configureFlags.__append = [ "--disable-servers" ];



    # Test disablement

    # libredirect has two tests which use system(3), which references /bin/sh (not $PATH or $SHELL); these fail on non-NixOS
    libredirect.__output.doInstallCheck.__assign = false;

    # same problem as: https://github.com/NixOS/nixpkgs/issues/148106
    #openssh.__output.doCheck.__assign = false;

    # absurdly bloated test suite, assumes ipv6, tries to start an ssh server, wtf
    curl.__output.doCheck.__assign = false;
    curl.__output.doInstallCheck.__assign = false;

    # incredibly slow test suites
    openldap.__output.doCheck.__assign = false;
    openldap.__output.doInstallCheck.__assign = false;
    libjxl.__output.doCheck.__assign = false;
    miniupnpc.__output.doCheck.__assign = false;
    rav1e.__output.doCheck.__assign = false;
    gtksourceview4.__output.doCheck.__assign = false;
    crosvm.__output.doCheck.__assign = false;
    girara.__output.checkPhase.__assign = "";

    # unsandboxed builds where librem can see /usr/bin/ccache
    bison.__output.doCheck.__assign = false;
    bison.__output.doInstallCheck.__assign = false;

    # FIXME: a bunch of python packages already `.override { packageOverrides =
    # }` on their `python`... we need to detect that mistake and force them to
    # fix it.
    python311.__input.packageOverrides.__overlay = {
      portend.__output.doCheck.__assign = false;
      portend.__output.doInstallCheck.__assign = false;
      cheroot.__output.doCheck.__assign = false;
      cheroot.__output.doInstallCheck.__assign = false;
      dnspython.__output.doCheck.__assign = false;
      dnspython.__output.doInstallCheck.__assign = false;
      apsw.__output.checkInputs.__assign = [];
      apsw.__output.doCheck.__assign = false;
      apsw.__output.doInstallCheck.__assign = false;
      trio.__output.doCheck.__assign = false;
      trio.__output.doInstallCheck.__assign = false;
      prev.python-socks.__output.doCheck.__assign = false;
      prev.python-socks.__output.doInstallCheck.__assign = false;
      uvloop.__output.doCheck.__assign = false;
      uvloop.__output.doInstallCheck.__assign = false;
      eventlet.__output.doCheck.__assign = false;
      eventlet.__output.doInstallCheck.__assign = false;
      twisted.__output.doCheck.__assign = false;
      twisted.__output.doInstallCheck.__assign = false;
      secretstorage.__assign = null;   # for yt-dlp
      btchip.__assign = null;
      pyscard.__assign = null;
      sphinx.__output.doCheck.__assign = false;
      sphinx.__output.doInstallCheck.__assign = false;
    };

  }))
]

