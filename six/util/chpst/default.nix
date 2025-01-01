#
# chpst: Change Process STate (named after the runit tool)
#
# Sets the process state using `s6` and `execline` tools.
#
# Returns an argv list-of-strings.  If you're passing this to a shell,
# you need to run `lib.escapeShellArgs on` it.
#

{ lib
, execline
, s6
}:

# arguments are listed here in the order in which they are applied/invoked
{
  # set userid and groups to these; also set $UID and $GID environment variables
  user ? null,
  group ? null,
  groups ? [],

  # clear the environment
  env-clear ? false,

  # read environment variables from the specified directory
  envdir ? null,

  # read environment variables from the specified file
  envfile ? null,

  # add this value to the nice(2) of the program
  nice ? null,

  # set the umask
  umask ? null,

  # create a new session (and, within it, a new process group)
  new-session ? false,

  # create a new process group, and run the program within it
  new-process-group ? new-session,

  # fdmove -c 2 1
  redirect-stderr-to-stdout ? true,

  # replace argv0 with this value
  argv0 ? null,

  # chroot into the specified directory before running the program
  chroot ? null,

  # change to this directory; note that this is relative to `chroot` if it is set
  dir ? null,

  # argv to execute
  argv ? throw "you must set argv to the command you want to execute",
}:

assert new-session -> new-process-group;

assert chroot!=null && argv0!=null -> throw "once we enter the chroot we cannot access s6-exec";
assert chroot!=null && dir!=null -> throw "once we enter the chroot we cannot access execline-cd";

# not ready to commit to a specific precedence between these two
assert envdir==null || envfile==null;

# TODO: set $HOME?
# TODO: allow to use numerical uid/gid
# TODO: ionice
# TODO: put more of these settings into envdirs?
# TODO: explain why the `-f`, `-g`, and `-d` flags for s6-setsid are not useful here

[
] ++ lib.optionals env-clear [
  "${execline}/bin/emptyenv"
] ++ lib.optionals (envdir != null) [
  "${s6}/bin/s6-envdir" envdir
] ++ lib.optionals (envfile != null) [
  "${execline}/bin/envfile" envfile
] ++ lib.optionals (user != null) [
  "${s6}/bin/s6-applyuidgid" "-u" user
  "${s6}/bin/s6-envuidgid" "-u" user
] ++ lib.optionals (group != null) [
  "${s6}/bin/s6-applyuidgid" "-g" group
  "${s6}/bin/s6-envuidgid" "-g" group
] ++ lib.optionals (groups != []) [
  "${s6}/bin/s6-applyuidgid" "-G" groups
  "${s6}/bin/s6-envuidgid" "-G" groups
] ++ lib.optionals (nice != null) [
  "${s6}/bin/s6-nice" "-n" (toString nice)
] ++ lib.optionals (umask!=null) [
  "${execline}/bin/execline-umask" umask
] ++ lib.optionals new-session [
  "${s6}/bin/s6-setsid" "-s"
] ++ lib.optionals (new-process-group && !new-session) [
  "${s6}/bin/s6-setsid" "-b"
] ++ lib.optionals redirect-stderr-to-stdout [
  "${execline}/bin/fdmove" "-c" "2" "1"
] ++ lib.optionals (chroot != null) [
  "${s6}/bin/s6-chroot" chroot
] ++ lib.optionals (dir != null) [
  "${execline}/bin/execline-cd" dir
] ++ lib.optionals (argv0 != null) [
  "${s6}/bin/s6-exec" "-a" argv0
] ++ argv
