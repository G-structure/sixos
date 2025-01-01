# Overview

- At the top level, you have a scope `hosts` with an attribute for each
  machine you care about.  This scope of hosts is built up out of `(final: prev:
  { ... })` overlays, just like the nixpkgs scope of packages.

- For each host you will also have a scope of packages, which is almost always
  an instantiation of nixpkgs with some choice of parameters
  (e.g. `hostPlatform`) and any packageset overlays you like.

- For each host, you also have a scope of *targets* which are available on that
  machine.  There are two kinds of targets:

  1. *instances of services*

     - FIXME: use wpa-supplicant as a better example.
     - For example, `services.opensshd` is a *service*; you might decide to run
       two separate instances of this service on ports 23 and 2323, and call
       them `targets.sshd-port23` and `targets.sshd-port2323`.  You would have
       two targets but only one service.

  2. *abstract targets*

     Abstract targets describe common waypoints in the startup and shutdown
     process, independent of any particular choice of software.

     - Example: by convention the abstract target named `default` depends on
       ("is `after`") all the targets that should be started automatically at
       boot time.

     - Example: by convention targets that expect device nodes to exist in `/dev`
       declare themselves `after` the `coldplug` abstract target.  Users of
       `mdevd` will create an instance of the `mdevd-coldplug` service which is
       `before` the `coldplug` target; users of `eudev` do the same with
       `eudevd`.

# Understanding the s6 ecosystem

It looks complicated at first, but it's actually really simple.  There are four
"layers":

- `s6-linux-init` the short-lived pid1; it `exec()`s the long-lived pid1
- `s6`, which includes
  - `s6-svscan` the long-lived pid1
  - `s6-supervise` child processes of `s6-svscan`, one for each service
- `s6-rc` which understands *dependencies* between services
- `six` (this repository) which integrates `nix` with `s6`

It is easy to get `s6` confused with `s6-rc`; this is an unfortunate naming
choice.  The `s6` software is very mature, rock-solid, and well-tested.  It
supervises long-running processes.  However it *has absolutely no understanding
of dependencies between processes*.  The newer `s6-rc` software is essentially a
"frontend" to `s6` that allows you to express dependencies, and then ask for
state changes which respect those dependencies.  Without `s6-rc` you have to
manually start and stop each individual service, and nothing will prevent you
from starting/stopping them in the wrong order.

You can use any of these layers without the ones above it.

s6 just supervises processes.  It doesn't understand anything about
*dependencies* between processes.  It also doesn't understand any kind of
procedure which doesn't involve supervising a process -- for example, mounting
a filesystem or bringing up a network interface that has a static IP address.
s6-rc is a layer on top of s6 that expresses and understands dependencies
among both supervised processes and also unsupervised actions.

s6-rc has two kinds of services: oneshots and longruns.  The only difference
between them is that a longrun supervises a process (e.g. sshd), whereas
oneshots don't (e.g. the up/down state of a network interface). [*]

Longruns are organized into stdio "funnels", which deal with the stdout/stderr
of supervised processes.  In fact, the main use for funnels is logging.  A
longrun must appear exactly once in one funnel.  If you pretend that
`s6-svscan` (which can be pid 1) is a longrun "supervised" by the kernel then
all the longruns form one huge funnel with pid1 at the root.  Each longrun's
stdout+stderr goes to its parent, and each non-leaf longrun receives the
outputs of all of its children on its stdin.  So there's a big huge tree where
every node except the root is a longrun.

Dependencies are completely separate from the funnel-tree, and different in
two important ways: (1) it is a DAG and (2) both longruns and oneshots may
participate.

Each service has an `sname`, which is the name by which s6 will identify the
service.  This is the name you use when starting and stopping a service from
the command line.  It is a goal to leave the choice of these names up to the
end user; therefore, all services take their `sname` as an argument.  The
default value of this argument for funnel apexes is the attrname of the funnel
in the service attrset; non-leaf funnel nodes are responsible for generating
`snames` for their children by suffixing the provided `sname` with "." and
some additional text.

s6-rc organizes its longruns into a set of *funnels*; each funnel is a tree of
longruns.  Each longrun must appear exactly once in one funnel.  Funnels are
also given names.  Therefore, we specify all of the longruns as attrsets.

[*] Technically there is a third kind of service called a "bundle" but those are
equivalent oneshots (using `dependencies.d` instead of `contents.d`) with
`${coreutils}/bin/true` as the `up` script.  So we don't bother with them.


# sharp edges

The `s6-rc change` command changes the system state.  Basically you specify a
set of services you want started and a set you want stopped; it stops all the
services you want stopped and then starts the ones you want started.  It does
this in an order that respects the dependencies.

There are three very sharp edges here to be aware of:

- If a service *fails to stop*, `s6-rc` will immediately stop what it is doing.
- If a oneshot *fails to start*, `s6-rc` will immediately stop what it is doing.
- If a longrun *times out while starting*, `s6-rc` will *kill it* and then immediately stop what it is doing.

These are sharp edges because:
1. when a service needs to be restarted, `s6-rc` treats that like stopping the service and then starting it
2. `s6-rc` will stop any service which is `after` a service which needs to be restarted.

If the stop fails, `s6-rc` *won't even try* to start it.  If the start times
out, `s6-rc` will kill it and stop what it is doing.  If a (re)start of a
service fails, `s6-rc` won't try to start any service marked as `after` the
failed service.

Fortunately the failures above can only happen a few ways, so if you're aware of
them you can make sure they never happen:

1. Never, ever, ever allow a `finish` script to exit with a nonzero exit status.
   This is easy; if a `finish` script fails there isn't much you can do about
   it, so discarding the failure (after perhaps logging it somewhere) is all you
   can hope for anyways.

2. Never, ever, ever allow a oneshot `up` or `down` script to exit with a
   nonzero exit status.  This is more difficult; for example, network interfaces
   with static IP addresses are generally oneshots; if these fail 

`s6-rc` doesn't consider a service to have started until that process *signals
its readiness*.  This happens one of three ways:

- A longrun without a `notification-fd` is ready as soon as it is started.
- A longrun with a `notification-fd` is ready 


# reasoning through services that failed to start
- "If an up transition fails, s6-rc sends an explicit ‘s6-svc -d’ command to the
  longrun.  This ensures the service is in a known down state when failing to go
  up, instead of (for instance) being stuck in a not-ready limbo state."
  - Note: for longruns, an `up` transition can fail only if the service has both
    `notification-fd` *and* either (`timeout-up` or the `-t` flag to `s6-rc
    change`).
      - Without `notification-fd`, `s6-rc` assumes the service is up as soon as
        `s6-svc -u` returns success (which happens immediately as long as the
        service directory isn't messed up)
      - Without `timeout-up`, `s6-rc change` will wait forever.
  - down transitions can fail if (a) the service ignores SIGTERM or (b) the
    service has a `finish` script which fails.  In these cases s6-rc just gives
    up and stops trying to change the system state.
  - This is sort of a problem; it diverges from the runit/s6-svc behavior of "if
    I ask for it to be up, it keeps trying forver"
  - Combined with up-timeout this is sort of a footgun.
  - "Currently, the only case where s6-rc's view can diverge from s6's view is
    when a service has been brought up via a s6-rc change command, then has
    failed at some point with a permanent failure - which means its supervisor
    has stopped trying to bring it back up."
  - If `./finish` exits with the magic value 125, `s6-supervise` will *not*
    attempt to restart the service.  This provides a way for services to change
    their own state.
  - `s6-supervise` throttles the rate at which it will fork `./run` to a maximum
    of once every 1-2 seconds (the exact rate depends on a few things, but it is
    never less than 1 second and never more than 2).



# scope and ecosystem

The most important thing to understand about the `s6` ecosystem is which duties
it takes responsibility for, and which duties are left to higher layers built on
top of the `s6` tools.  The choice of responsibilities was made very carefully,
and is the reason why `s6` can be both powerful and simple at the same time.  It
is also one of the most unexpected differences for users coming from experience
with other supervisors like systemd.

The key points are:

1. `s6-svc` implements process supervision, which means that it takes
   responsibility for restarting services which *die after having started
   successfully*.  It is important for a process supervisor to take this
   responsibility, because there is often nowhere to report the failure to.

2. `s6-rc` (which is layered on top `s6-svc`) implements service dependencies.
   This means that `s6-rc start` takes responsibility for *waiting for a service
   to be ready before starting its dependees*, and `s6-rc stop` similarly takes
   responsibility for shutting down services in the correct order.

3. None of the tools in the `s6` ecosystem takes responsibility for *dealing with
   services which fail to start*.  This is not a problem, because *starting* a
   service is always initiated by some external caller who invoked `s6-svc -u` or
   `s6-rc start`.  Each of these tools will carefully note any failure to start a
   service, and report that failure back to the process which called it.  It is
   the *caller's* duty to decide how to deal with the failure.

The third point is the most critical for systemd users to understand.  It is
also the reason why `s6` needs only one kind of dependency instead of the twelve
kinds (six kinds, each with or without an ordering constraint) of dependency
found in systemd.  Eleven of those twelve dependency types exist in order to
deal with failures while starting or stopping a service -- specifically,
failures that occur during the lifetime of a single `systemctl` invocation.

Instead of trying to be a monolithic tool that solves every problem, `s6`
chooses simplicity.  If a failure occurs during the lifetime of `s6-rc start`
(the equivalent of `systemctl start`), `s6-rc` doesn't try to deal with it.
Instead, it reports the failure back to its caller.  `s6-rc` is modular and
properly layered: it interfaces well with layers above it instead of trying to
absorb them.  This keeps it simple without sacrificing any power.

## systemd vocabulary and equivalents

Six borrows vocabulary from systemd when it is possible and accurate, but an
automatic systemd unit to s6 converter is "extremely impossible."  An
excellent "cheat sheet," which also explains why this can never be automatic,
and is also hilariously entertaining to read, can be found [here][systemd-units].

### States

`s6` and `six` do not natively support the systemd concepts of: "failed (to
start)", "inactive" or "idle" because the functionality that needs these states
can be implemented modularly in a higher layer.

### `after` and `before`

Six includes the `after` and `before` ordering constraints, which work
essentially the same way as systemd's `After+Requires` and `Before+RequiredBy`
since these are the ones whose behavior matches `s6-rc`'s native dependency
type.  So when you write this in six:

```
sshd.after = [ eth0 ];
```

is like saying this in systemd's `sshd` unit:

```
[Unit]
Requires=eth0
After=eth0
```

This dependency is implemented directly as an `s6-rc` dependency.

### Other Dependencies

Systemd has a very large number of [dependency flavors][systemd-manpage]:

- Wants
- Requires
- Requisite
- BindsTo
- PartOf
- Upholds
- Conflicts
- OnFailure -- only relevant to *failed to start* state
- OnSuccess -- only relevant to *inactive* state

Most of these dependency types are used only in situations where either the
dependency or dependee is a non-service, like a `target`, `device`, or `mount`.
Since `six` deals only with services, these non-service dependency types aren't
relevant.

#### Likely to be Implemented

##### `PropagatesReloadTo`

##### `Wants` and `WantedBy`

Starting a service causes its wanted dependencies to be concurrently started.
Stopping or restarting a wanted dependency has no effect on the service which
wants it.

When you write this in six (not yet implemented!):

```
chrony.wants = [ gpsd ];
```

is (would be) like saying this in systemd's `chrony` unit:

```
[Unit]
Wants=gpsd
```

These unordered constraints are useful when a service already has its own robust
and efficient mechanism for awaiting the readiness of its dependencies.  For
example: if two services communicate over a named pipe, the kernel will block
one until both of them are ready.  In this sort of situation it is safe to start
both services concurrently.

##### Possible to Implement if Proven Useful

The following systemd constraint types are not implemented in Six, but could
easily be implemented if they are deemed useful:

- `Conflicts` -- a kind of "anti-dependency"; conflicting services are stopped
  prior to starting a service.

  This could easily be supported by checking for conflicts in `six start` or
  `six activate` before `exec()`ing into `s6-rc`.  However:

  - The main use for this seems to be managing system shutdown by having the
    "shutdown target" conflict with services; `s6-linux-init` simply shuts down
    *every* service, since it is very carefully designed to not depend on
    *anything* -- an option which has been unavailable to systemd for at least a
    decade.

  - The only other use of this in NixOS appears to be sharing the console
    between the rescue console and the runtime console; `six-initrd` already
    accomplishes this more robustly using a statically-linked copy of `abduco`.

- `BindsTo` -- This is like `Requires+After`, but additionally the dependency
  will kill its dependee if the dependency dies.

  This can be implemented in six using `./finish` actions.  Currently a service
  `BindsTo` another service in only two places in all of NixOS, one of which is
  a dummy service which describes itself as a "fake graphical-session target for
  non-systemd-aware sessions".  Since there appears to be only one nontrivial
  use of this feature in the currently-largest Linux distribution it is probably
  best to simply add one extra command to the `./finish` script for the package
  that needs it than to invent a new dependency type.

##### Highly Unlikely to be Useful

The following systemd constraint types are of highly questionable usefulness:

- `Requisite` -- Like `Requires+After`, but merely *check if the dependency has
  already started and fail if it has not*, rather than starting it and waiting
  for it to be ready.

  It is unclear that this dependency type is useful in practice.  It is not used
  anywhere in NixOS.

- `PartOf` -- if the dependency is stopped or restarted, restart this service.
  Has no effect on starting.  In a sense this is the "dual" of `Wants`, which
  affects starting but does not affect restarting or stopping.

  I have not been able to find any useful examples of this combination.  It is
  not used anywhere in NixOS except for a comment mentioning that
  `switch-to-configuration.pl` will malfunction if a service uses this.


# `targets.global`

The `targets.global` attrset is a namespace for well-known target types which
should exist on any system where they are meaningful.  The `targets.global`
namespace is managed as part of the `six` software package; you should not
define your own custom attributes here.  The names in the `targets.global`
namespace are policy-agnostic (for example, we chose `targets.global.coldplug`
rather than `targets.global.mdevd-coldplug`).

- `targets.global.coldplug`: any service which is *after* this can safely assume
  that all of the following have happened (not necessarily in this order):
  1. The userspace hotplug daemon (i.e. `mdevd`, `udev`, `eudev`,
     `systemd-udevd`, or similar) is running and ready to respond to
     notifications from the kernel.
  2. A *coldplug* has occurred, meaning that any devices attached to the system
     prior to the readiness of the userspace hotplug daemon have been issued.
  3. All coldplug events have been completed.  This means that device nodes for
     coldplugged devices already exist.

- `targets.global.set-hostname`: the machine's hostname has been set.


# junk


In s6, "starting" and "stopping" are actions you can request; these actions
can fail.  A service reports its readiness (if it does not support doing so,
it is assumed to report readiness the instant its `./run` script has been
`execve()`d).  A request to start a service will fail if the service does not
report readiness before the `up-timeout`, whose default value is infinite --
therefore starting a service cannot fail unless a timeout is manually
specified.  A request to stop a service will fail if the service has not died
within `down-timeout` milliseconds (default: infinite) after receiving its
stop signal (defualt: SIGTERM+SIGCONT) or if its `./finish` script exits
nonzero.  The current handling of "failure to stop" in `s6-rc` is a bit
extreme: if any service fails to stop this is considered a very serious
failure; s6-rc will forcibly kill the process and will not perform any further
actions.  This may leave the system in an undesired state.  Therefore,
`down-timeout` is discouraged, and `./finish` scripts should never fail.




[systemd-units]: https://skarnet.org/software/s6/unit-conversion.html#unit-section
[systemd-manpage]: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
