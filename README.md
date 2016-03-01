# vz

[![Join the chat at https://gitter.im/nponeccop/vz](https://badges.gitter.im/nponeccop/vz.svg)](https://gitter.im/nponeccop/vz?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
OpenVZ MAD Profile

A way to run chroot-based "containers" on OpenVZ hosts.

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
