# vzbuild — image build & minification

`vzbuild` builds the OCI images vz pushes to nodes. It has two back-ends behind
one front-end: a **traditional** minimal-runtime build (declared RPM closure →
`FROM scratch`) and an opt-in **strace-trace minifier**. `oci.sh` wraps either
result into the two-layer (base + app) OCI image `podman kube play` consumes.
See [`../../SPEC-v3.md`](../../SPEC-v3.md) for where this sits in the pipeline and
[`../../TASKS.md`](../../TASKS.md) (section C) for status and the size comparisons.

## strace-trace (image minification)

`vzbuild` minifies a rootfs by tracing the program with `strace` and keeping only
the files it actually opens. `strace-trace` is the Linux-only tracer:

```shell
  $ strace-trace perl -MHTTP::Date -e 'print time2str(time())."\n"'
  $ cat spec
  /etc/localtime
  /usr/bin/perl
  /usr/lib/libc.so.6
  /usr/lib/libcrypt.so.1
  /usr/lib/libdl.so.2
  /usr/lib/libm.so.6
  /usr/lib/libpthread.so.0
  /usr/lib/locale/locale-archive
  /usr/lib/perl5/core_perl/CORE/libperl.so
  /usr/lib/perl5/core_perl/Config.pm
  /usr/share/perl5/core_perl/Carp.pm
  /usr/share/perl5/core_perl/Exporter.pm
  /usr/share/perl5/core_perl/Time/Local.pm
  /usr/share/perl5/core_perl/constant.pm
  /usr/share/perl5/core_perl/strict.pm
  /usr/share/perl5/core_perl/vars.pm
  /usr/share/perl5/core_perl/warnings.pm
  /usr/share/perl5/core_perl/warnings/register.pm
  /usr/share/perl5/vendor_perl/HTTP/Date.pm
```

The `spec` file is the input to building a minimal OCI rootfs. The minifier is
**same-system only**: install, trace, and build on one host (`ROOT=/`).
`oci.sh` then wraps the minified rootfs into a loadable OCI image.

Minification is **inherently unsafe** (a stripped `.so`, locale, or CA bundle can
break at runtime), so it is strictly opt-in; the traditional back-end is the safe
default. A containerized, rootless version of the minifier runs as a k8s build
Job — see [`../../TASKS.md`](../../TASKS.md) section C.
