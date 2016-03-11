# vz [![Join the chat at https://gitter.im/nponeccop/vz](https://badges.gitter.im/nponeccop/vz.svg)](https://gitter.im/nponeccop/vz?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

A distributed private cloud capable of running "containers" on OpenVZ hosts.

- cloud := an API to deploy applications and allocate resources across more than one VPS
- distributed cloud := a cloud with VPS provided by more than one vendor
- private cloud := a cloud with command & control system not controlled by VPS vendors (talk less by a single vendor)
- container := a partition of a VPS allowing multiple POSIX/libc applications coexist without clashes of dependency versions

Workflow of 0.1
---------------

- Create a user with your current user name and passwordless `sudo` on the hosts
- Configure Ansible and your hosts so `ansible all -m ping` is all green
- Have your app installed somewhere (in full OS, Docker, chroot etc)
- create `bundles/myapp` folder (`myapp` is an image name, you can use anything else)
- Install `strace` there, run `strace-chroot` to get `myapp/rootfs` folder
- Write `myapp/config.json` according to the Open Containers Initiative specification
- Test the bundle (OCI term for rootfs+config) using `runch start myname` / `runch kill myname` (`runch` uses the basename as the OCI container id, so it shouldn't be '.')
- tar-xz your OCI bundle (`rootfs` and `config.json`) to get an image (`images/appname.txz`)
- run `vzmaster push appname && vzmaster start appname`

Status
------

- `strace-trace` minimizes pre-existing rootfs
- `vzmaster push` uploads images using Ansible
- `vzmaster start` installs `runch` remotely, unpacks image and starts resuting OCI bundle using `ranch`
- `runch start` reads chroot configuration from OCI `config.json` and runs basic bundles. To be generally useful it needs to support:
  - auto-restart on crashes
  - mounting instructions from OCI `config.json` or at least `arch-chroot` default mounts
- `runch kill` works
- `vzmaster kill` is missing, but it is only an Ansible wrapper of `runch`

Why
---

The weak definition of containers allows for such weak forms of isolation as chroots or even NIX-style isolation. So unlike
cgroups/namespaces/LXC-based containers (runc, docker, rkt..) it's possible to run multiple containers inside OpenVZ containers 
with older kernels. It has an advantage of very low cost (e.g. twice as cheaper as KVM/Xen, e.g. BudgetVM vs DigitalOcean). And with such low operation cost even a hobbyist can afford operating a complex multi-server web service for years. And I hope that such improved longevity of hobbyist projects will bring more innovations to the web, as entry cost is at least twice as lower.

One problem of using cheaper VPS providers is that many of them die each year. So some provisions for redundancy must be made,
as a VPS can just disappear along with its hosting company without any notice.

Idealized Workflow
------------------

- Spend $15/month in total for a few VPS from different hostings
- Run `vzmaster newnode` with only IPs and root passwords from activation emails
- The preinstalled OS is detected and replaced with VzOS, SSH keys are used from now on
- Define application pods configuration in the spirit of Kubernetes/Dokku/Heroku
- Run `vzmaster deploy` to build and push a new version of your application
- Go to sleep
- Notice that one of your VPSes has gone without any emails from the company
- Order a new node from someone else
- Rerun `newnode`/`deploy`
- Go to sleep again
- Write another application and deploy it across the same redundant array of inexpensive VPSes
- Migrate to Docker or VMs and back as your financial power changes over time

Architecture
------------

- all security is provided by OpenSSH and not by inmature TLS server implementations
- all management is peformed by `ansible`. No management or data collection daemon processes whatsoever on slaves besides `init` and `sshd`.
- ideally all containers are directly supervised by `init`/`PID 0` in the spirit of `/etc/inittab`
- 32-bit `i686` as the main target architecture to save RAM. RAM is what is paid for. More RAM means more money, and saving 200 MB of RAM gives significant advantages on 512MB VPS. Fat runtimes for fat containers already exist.
- `vzmaster` works as a frontend to `ansible`
- `vzslave` works as a shell or an SSH subsystem
- `runch` implements an open Open Containers Initiative (OCI) specification, along with Docker/libcontainer `runc` and VM `runv`
- ideally no interactive shell whatsoever, except for emergencies
- image push over SFTP (not pull over HTTPS, so no image registry)
- flat images without layers in 1.0 (i.e. simple tarballs of OCI bundles)


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
- kubernetes
- Heroku
- Dokku

Supervision:
- systemd
- openrc
- raw busybox-based /sbin/init

Goals for 0.1
-------------

- Manual installation
- PoC operation on CentOS 6/OpenVZ with manually created images (with help from `strace-chroot` to create the `rootfs` part)
- `vzmaster {push|start|kill}` as a front end to Ansible ad hoc commands
- `runch {start|kill}`
- `runch start` monitors using a shell loop

Master-slave:

- remote container start/stop
- image transfer and storage

Slave only:

- container runner with integrated container crash supervision and auto restart

Goals for 1.0
-------------

Less ad hoc implementation of what was in 0.x, and in addition:

Master only:

- container rootfs build system
- assembly of OCI images

Goals for 2.0
-------------

Master-slave:

- logging and monitoring
- differential image compression
 
Slave only:

- rootfs
- rootfs installer

Master only:
- central management, orchestration and monitoring console

Available Components
--------------------

### runch

A clone of `runc` but for chroots. Start, kill.

### vzmaster

A front-end to Ansible. Push, start, kill.

### ldd-trace

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

### strace-trace

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

The `spec` file created in current directory can be used to create a minimal OCI rootfs/chroot 
