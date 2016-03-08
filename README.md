# vz [![Join the chat at https://gitter.im/nponeccop/vz](https://badges.gitter.im/nponeccop/vz.svg)](https://gitter.im/nponeccop/vz?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

A distributed private cloud capable of running "containers" on OpenVZ hosts.

Few definitions:

- cloud := an API to deploy applications and allocate resources across more than one VPS
- distributed cloud := a cloud with VPS provided by more than one vendor
- private cloud := a cloud with command & control system not controlled by VPS vendors (talk less by a single vendor)
- container := a partition of a VPS allowing multiple POSIX/libc applications coexist without clashes of dependency versions

The weak definition of containers allows for such weak forms of isolation as chroots or even NIX-style isolation. So unlike
cgroups/namespaces/LXC-based containers (runc, docker, rkt..) it's possible to run multiple containers inside OpenVZ containers 
with older kernels. It has an advantage of very low cost (e.g. twice as cheaper as KVM/Xen, e.g. BudgetVM vs DigitalOcean). And with such low operation cost even a hobbyist can afford operating a complex multi-server web service for years. And I hope that such improved longevity of hobbyist projects will bring more innovations to the web, as entry cost is at least twice as lower.

One problem of using cheaper VPS providers is that many of them die each year. So some provisions for redundancy must be made,
as a VPS can just disappear along with its hosting company without any notice.

Competitors
-----------
Rootfs:
- CoreOS
- RancherOS
- PhotonOS
- Ubuntu Snap
- RedHat Atomic
- Alpine Linux

Container runners:
- docker/runc
- garden/warden

Command and control:
- fleet/etcd

Supervision:
- systemd
- openrc
- raw busybox-based /sbin/init

Essential Components
--------------------

Master-slave:

- remote container start/stop
- image transfer and storage

Slave only:

- rootfs
- container runner
- autonomous container crash supervision and auto restart

Master only:

- container rootfs build system
- assembly of OCI images

Optional Components:
--------------------

Master-slave:

- logging and monitoring
- differential image compression

Master only:
- central management, orchestration and monitoring console

ldd-trace
---------

For executables that are known to rely only on dynamic libraries, `ldd-trace` provides a way to create minimal chroots:

```shell
  $ ldd-trace ls-chroot ls
  $ ./ldd-chroot.sh ls-chroot ls
  ++ mkdir -p ls-chroot/usr/lib
  + cp -a /usr/lib/libcap.so.2.25 ls-chroot/usr/lib/libcap.so.2
  + cp -a /usr/lib/libc-2.23.so ls-chroot/usr/lib/libc.so.6
  ++ mkdir -p ls-chroot/lib
  + cp -a /usr/lib/ld-2.23.so ls-chroot/lib/ld-linux.so.2
  ++ mkdir -p ls-chroot/usr/bin
  + cp -a /usr/bin/ls ls-chroot/usr/bin/ls
  $ sudo chroot ls-chroot ls
  dev  etc  lib  proc  run  sys  tmp  usr
  $ find ls-chroot -type f
  ls-chroot/usr/lib/libcap.so.2
  ls-chroot/usr/lib/libc.so.6
  ls-chroot/usr/bin/ls
  ls-chroot/lib/ld-linux.so.2
  ls-chroot/etc/resolv.conf
  $ du -sBK ls-chroot/
  2312K   ls-chroot/
```

strace-trace
------------

For more complex cases, `strace-trace` uses `strace` Linux only tool to trace system calls and find all files opened during the test run:

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

The `spec` file created in current directory can be used to create a minimal chroot 
