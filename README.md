# vz [![Join the chat at https://gitter.im/nponeccop/vz](https://badges.gitter.im/nponeccop/vz.svg)](https://gitter.im/nponeccop/vz?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

A distributed independent cloud capable of running Podman pods on low RAM hosts.

- cloud := an API to deploy applications and allocate resources across more than one VPS
- distributed cloud := a cloud with VPS provided by more than one vendor
- independent cloud := a cloud with command & control system not controlled by VPS vendors (talk less locked to a single vendor)

Distibuted means reliable, independent means free as in freedom, low RAM means cheaper as the VPS cost is dominated by the RAM amount.

Workflow of 2.x
---------------

Prepare the pods:

  - Build your containers as usual
  - Use `smith-strace` to minify them (optional) 
  - Define a pod in YAML

Configure the nodes:

  - Create a user with your current user name and passwordless `sudo` on the hosts

Configure the master

  - Configure Ansible and your hosts so `ansible all -m ping` is all green
  - Generate an ansible playbook from the Ansible inventory and the pod files

Enjoy `ansible-playbook -i hosts.ini deploy.yaml`

Bootstrap on RockyLinux 8
-------------------------

AlmaLinux 8 and RHEL 8 should work too.

- have your SSH public key listed in `ssh-add -l`
- `ssh-copy-id root@{server-ip}`
- `./bootstrap.sh {server-ip}`
- `ssh {server-ip}` - now it should let you in with your key (note no `root@` - the previous step created the same remote user as  `whoami`!)
- `sudo yum update --security`

Status
------

- Slowly migrating the production from 1.x
- `smith-strace` script work
- Image push over SSH works
- Handcrafted playbooks work, but they are not robust enough yet (mostly performance, idempotency and image upgrades are missing)

Why
---

with such low operation cost even a hobbyist can afford operating a complex multi-server web service for years. And I hope that such improved longevity of hobbyist projects will bring more innovations to the web, as entry cost is at least twice as lower.

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
- 512 MB nodes. More RAM means more money. Fat runtimes for fat containers already exist.
- Stock RHEL8 software via free downstream distributions (RockyLinux 8 is the primary target, AlmaLinux 8 works)
- image push over SFTP via Ansible `copy` (not pull over HTTPS, so no image registry)

Non-goals
---------

- It's not a full k8s replacement

Competitors
-----------
Rootfs:
- CoreOS
- RancherOS
- PhotonOS
- Ubuntu Snap
- RedHat Atomic
- Alpine Linux
- Intel Clear Linux

Container runners:
- docker/runc
- garden/warden
- Intel Clear Containers
- udocker/proot

Command and control:
- fleet/etcd
- kubernetes
- Heroku
- Dokku

Supervision/zombie reaping:
- systemd
- openrc
- raw busybox-based /sbin/init
- supervisord
- pidunu

Image building:

- Dockerfile/Docker build/buildkit
- smith
- s2i
- Heroku

Features as of 1.0-pre
----------------------

- Manual installation (with help from `bootstrap`)
- PoC operation on RockyLinux 8 and AlmaLinux 8 CentOS 6/OpenVZ with manually created images (with help from `strace-chroot` to create the `rootfs` part)
- `vzmaster {push|start|kill}` as a front end to Ansible
- `runch {start|kill}`
- `runch start` monitors using a shell loop

Master-slave:

- remote container start/stop
- image transfer and storage

Slave only:

- `vzexec` container runner with integrated container crash supervision and auto restart
- stdout/strderr are logged to syslog

Goals for 0.2
-------------

- more automation in `bootstrap`
- shift some work from start/stop Ansible playbooks to `bootstrap` to avoid repetition
- deploy to Ansible host groups other than `all`
- seamless update - autostop older image
- register rc.d services for container autostart
- `iptables` setup to open ports

Goals for 0.3
-------------

- differential image compression using `xdelta3` or `bsdiff`
- Ansible role
- Syslog downloader

Goals for 1.0
-------------

Less ad hoc implementation of what was in 0.x, and in addition:

Slave only:

- ability to substitute `runch` with `runc`

Master only:

- container rootfs build system
- assembly of OCI bundles

Goals for 2.0
-------------

Master-slave:

- logging and monitoring
 
Slave only:

- rootfs
- rootfs installer

Master only:
- central management, orchestration and monitoring console

Available Components
--------------------

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

