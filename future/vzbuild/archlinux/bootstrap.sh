#!/bin/bash

set -ex
mkdir -p build/tmp-minstrap

# minstrap.spec - a minimal pacstrap capable to install a normal pacstrap :)
sudo ../strace-trace.sh build/tmp-minstrap.spec pacstrap -dc build/tmp-minstrap arch-install-scripts
sudo chown $UID build/tmp-minstrap.spec
echo /usr/bin/pacstrap >>build/tmp-minstrap.spec
echo /usr/bin/busybox >>build/tmp-minstrap.spec
echo /usr/bin/cat >>build/tmp-minstrap.spec
grep -vE "build/tmp-1|^/var/cache/pacman/pkg/|^/var/lib/pacman/sync/|^/home/" build/tmp-minstrap.spec | sort -u -o build/minstrap.spec
sudo rsync -al / build/minstrap --files-from=build/minstrap.spec
# docker run --rm -v $(readlink -m ../newroot):/root -v /var/lib/pacman/sync:/root/var/lib/pacman/sync -v /var/cache/pacman/pkg:/var/cache/pacman/pkg minstrap bash /root/run.sh
