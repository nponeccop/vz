#!/bin/bash
# Author: https://tetsumaki.net/blog/article/2013-06-11-creation-dun-environnement-chroot-arch-linux.html

# Utilisation: $0 <chroot_path> <program list>
rep="$1"
shift

# Copie $1 vers $2 en créant les répertoires parents.
copie_dir ()
{
	[ -e "${2}" ] && return
 	rep_base=$(dirname "${2}")
 	[ -d "${rep_base}" ] || {
 		echo "++ mkdir -p ${rep_base}"
 		mkdir -p "${rep_base}"
 	}
 	echo "+ cp -a $1 $2"
 	cp -a "$1" "$2"
}
 
# Copie $1 vers $2 + copie des bibliothèques utilisées.
copie_ldd ()
{
	local src dest file f f_link
 	src="$1"
 	dest="$2"
 	[ -e "${dest}" ] && return
 	file=( $(ldd "$src" | awk '{print $3}' | grep '^/') )
 	file=( "${file[@]}" $(ldd "$src" | grep '/' | grep -v '=>' | awk '{print $1}') )
 	for f in "${file[@]}"
 	do
 		f_link=$(readlink -f "$f")
 		copie_dir "$f_link" "${rep}${f}"
 	done
 	copie_dir "$src" "${dest}"
}
 
for prog in "$@"
do
 	prog=$(which "$prog") || $prog
 	prog_real=$(readlink -f "$prog")
 	copie_ldd "$prog_real" "${rep}${prog}"	
done

mkdir $rep/{tmp,dev,sys,proc,run,etc,var/{tmp,cache,db,run,log}}
touch $rep/etc/resolv.conf
