{ lib
, six
, pkgs
, listen-port ? 22
, package ? pkgs.openssh
}:
let
  package' = package.overrideAttrs (previousAttrs: {
    configureFlags = (previousAttrs.configureFlags or []) ++ [
      # unfortunately this can be set only at compile time; there is no way to
      # override it from sshd_config.  the "default default" is
      # /bin:/usr/bin:... which is unusable
      "--with-default-path=/run/current-system/sw/bin"
    ];
  });
in let package = package'; in
let
  configFile = builtins.toFile "sshd_config" ''
Port ${toString listen-port}
#ListenAddress 0.0.0.0
# see https://bugzilla.mindrot.org/show_bug.cgi?id=1357#c1
AddressFamily inet

# I can't figure out how to get `ssh-keygen -A` to put the end result anywhere
# other than directly in /etc, ugh
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
#SyslogFacility AUTH
#LogLevel INFO
PermitRootLogin yes
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
UsePAM no
#AllowAgentForwarding yes
#AllowTcpForwarding yes
#GatewayPorts no
X11Forwarding yes
#PermitTTY yes
PrintMotd no
#PrintLastLog yes
#TCPKeepAlive yes
#Compression delayed
#ClientAliveInterval 0
#ClientAliveCountMax 3
UseDNS no
#PidFile /var/run/sshd.pid
#MaxStartups 10:30:100
#PermitTunnel no
#ChrootDirectory none
#VersionAddendum none
Banner none

# read ~/.ssh/environment, which we need in order to guarantee that nix-store is
# in root's $PATH for `nix copy`
PermitUserEnvironment yes

# Allow client to pass locale environment variables
AcceptEnv LANG LC_*
Subsystem sftp internal-sftp
  '';
  options = lib.concatStringsSep " " [
    "-e"   # log to stderr
    "-4"   # disable ipv6
    "-D"   # don't detach (double-fork)
    "-f" configFile
  ];
in
six.mkFunnel {
  run = pkgs.writeScript "run"
# FIXME: use a oneshot for the setup
''
#!${pkgs.runtimeShell}
exec 2>&1

# nixpkgs has a patch to pass this var through from sshd to children
export LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive

${pkgs.coreutils}/bin/mkdir -p -m 0755 /var/empty # privilege separation directory for nixpkgs
${pkgs.coreutils}/bin/mkdir -p -m 0755 /run/sshd  # privilege separation directory for debian

# generate host keys if not present
# ugly kludge due to `ssh-keygen -f` taking a prefix rather than a destination
mkdir -p /etc/ssh
TEMP="$(mktemp -d)"
(cd "$TEMP"
 ln -s /etc/ssh etc
 ssh-keygen -A -f ./
 rm etc)
rmdir "$TEMP"

exec ${package}/bin/sshd ${options}
'';
}
