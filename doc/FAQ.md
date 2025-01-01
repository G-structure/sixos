# s6-rc supports longrun funnels/pipelines; does six support them?

Six supports pipelines only for one specific case: a non-logger longrun may send
its stdout (optionally tied to its stderr) to a logger.  In fact, *every* six
longrun does this -- if you do not define a logger, six will synthesize one
whose `run` script is simply `cat`.

Loggers may not be chained.

Six does not use the `pipeline-name` feature, which creates a bundle for each
pipeline; if you want that, simply use `mkBundle`.

# why does six require longrun loggers and prohibit chaining or funneling?

This is due to limitations in the underlying s6-rc architecture.  Unfortunately
s6-rc's longrun pipelines [are not in fact as general as they seem](https://skarnet.org/lists/supervision/3042.html).

In s6-rc, every longrun's stdout may go to one of two places:

1. A `fdup()` of its supervisor's stdout (also called the "catch-all logger").
2. The stdin of some other longrun (aka a "pipeline consumer").

Unfortunately a service's stdout may be changed *only* at the time the service
is started.  This means that in order to change where a service's stdout is
sent, the service must be restarted.  This means that any of the following
changes will force a service to restart:

1. changing an unlogged service to a logged service
2. changing a logged service to an unlogged service
3. changing which logger recevies the stdout of a service
4. changing the `run` script of a service's logger

This forced restart then propagates to *all the dependencies* of the restarted
service!  These forced restarts are extremely disruptive for
workstation/desktop/laptop systems.  They frequently lead to the user's display
server being killed, which causes angry users.

To prevent this, six imposes a simple restriction:

- Every longrun is logged by its own individual logger.

This restriction eliminates the first three types of forced restart: there are
no unlogged longruns, and the logger of a longrun cannot change.  If you want
your service's logs to go to the catch-all logger you can simply use `cat` as
your logger's `run` script.

For the fourth type of restart, six includes a patch to `s6-rc-update` which
allows a *non-propagated restart* of a service whose `run` script changes.  This
is achieved by invoking `s6-svc -r` to cause the logger to restart *without
restarting the logged service*.

