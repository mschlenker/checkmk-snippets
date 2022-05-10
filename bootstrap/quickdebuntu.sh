#!/bin/bash 

# Script for debootstrapping and running an Ubuntu, choose any recent Ubuntu.
# If installing a newer Ubuntu than the one you are running this script on,
# make sure you have installed the most recent debootstrap!
#
# (c) Mattias Schlenker for tribe29 GmbH
#
# License: Three clause BSD

# For building, please adjust! 

TARGETDIR="$1"
# Only specify one of ! If two or more are specified, Ubuntu will get precedence! Sorry, Debian folks.
UBUEDITION="jammy" # jammy: 22.04, impish: 21.10, focal: 20.04
DEBEDITION="bullseye" # Takes precedence over Devuan
DEVEDITION="chimaera" # Devuan is Debian without systemd
# Make sure you have devootstrap scripts or install Devuan debootstrap
# http://deb.devuan.org/devuan/pool/main/d/debootstrap/
SYSSIZE=32 # Size of the system partition GB
SWAPSIZE=3 # Size of swap GB
BOOTSIZE=3 # Keep a small boot partition, 3GB is sufficient for kernel, initrd and modules (twice)
ARCH=amd64
ROOTFS=btrfs # You might choose ext4 or zfs (haven't tried)
SSHKEYS="/home/${SUDO_USER}/.ssh/id_ecdsa.pub"
NAMESERVER=8.8.8.8 # Might or might not be overwritten later by DHCP.
HOSTNAME="throwawaybian"
EXTRADEBS="apache2"
ADDUSER="" # "karlheinz" If non-empty a user will be added. This means interaction!
ROOTPASS=0 # Set to 1 to prompt for a root password. This means interaction!
PKGCACHE="" # Set to nonzero length directory name to enable caching of debs
UBUSERVER="http://archive.ubuntu.com/ubuntu" # You might change to local mirror, but
DEBSERVER="http://deb.debian.org/debian"     # this is less relevant when using caching!
DEVSERVER="http://deb.devuan.org/merged"

# For running, please adjust!

CPUS=2
MEM=2048
VNC=":23"
DAEMONIZE="-daemonize" # set to empty string to run in foreground
EXTRAS="" # add additional CLI parameters
# This redirects port 8000 on the local machine to 80 on the virtualized Ubuntu
# and port 2222 to 22 on the Ubuntu. This is often sufficient for development:
NET="-net nic,model=e1000 -net user,hostfwd=tcp::8000-:80,hostfwd=tcp::2222-:22"
# This uses a real tun/tap bridge, use for stationary machines that should be
# exposed, if using Mattias' bridge script you have tap0 to tap9 available:
# NET="-device virtio-net-pci,netdev=network3,mac=00:16:17:12:23:11 -netdev tap,id=network3,ifname=tap3,script=no,downscript=no"

# network3 in both parameters is just an identifier to make qemu know, both 
# parameters belong together. 
#
# tap3 is the name of the tap device the interface is bonded to. This has to
# be unique for each virtual machine.
#
# The MAC address also has to be unique for each virtual machine!
#
# You might just snip the lines above and copy to the target dir than these
# lines will be sourced, so you do not have to modify this script. Just run:
#
# vim.tiny /path/to/installation/config.sh
# chmod a+x /path/to/installation/config.sh
#
# quickdebuntu.sh /path/to/installation
#
####################### SNIP HERE ############################################

if [ -z "$TARGETDIR" ] ; then 
	echo "Please specify a target directory."
	exit 1
fi

CFG="config.sh"
if [ -f "${TARGETDIR}" ] ; then 
	# A file is specified, assume that this is a config file in the folder containing the VM"
	echo "File instead of directory given, splitting..."
	chmod +x "${TARGETDIR}"
	CFG=` basename  "${TARGETDIR}" `
	TARGETDIR=` dirname  "${TARGETDIR}" `
	echo "cfg file: $CFG"
	echo "cfg dir: $TARGETDIR"
fi

if [ -x "${TARGETDIR}/${CFG}" ] ; then
	echo "Found config: ${TARGETDIR}/${CFG}, sourcing it..."
	. "${TARGETDIR}/${CFG}"
else
	echo "Creating config: ${TARGETDIR}/config.sh..."
	lines=`grep -n 'SNIP HERE' "$0" | head -n 1 | awk -F ':' '{print $1}' `
	mkdir -p "${TARGETDIR}"
	head -n $lines "$0" | sed  's/^TARGETDIR/# TARGETDIR/g' > "${TARGETDIR}/config.sh"
	chmod +x "${TARGETDIR}/config.sh"
fi

if [ -n "$PKGCACHE" ]; then
	if [ -n "$UBUEDITION" ] ; then
		mkdir -p "${PKGCACHE}/ubuntu/archives"
	elif [ -n "$DEBEDITION" ] ; then
		mkdir -p "${PKGCACHE}/debian/archives"
	else
		# Well that's not perfect, everything above the base
		# system should be taken from matching Debian!
		mkdir -p "${PKGCACHE}/devuan/archives"
	fi
fi

DISKSIZE=$(( $SYSSIZE + $SWAPSIZE + $BOOTSIZE ))
freeloop=""

if [ "$UID" -gt 0 ] ; then
	echo "Please run as root."
	exit 1
fi
neededtools="extlinux parted dmsetup kpartx debootstrap mkfs.btrfs qemu-system-x86_64 tunctl"
for tool in $neededtools ; do
	if which $tool > /dev/null ; then
		echo "Found: $tool"
	else
		echo "Missing: $tool, please install $neededtools"
		exit 1
	fi
done

for key in $SSHKEYS ; do
	if [ '!' -f "$key" ] ; then
		echo "Missing SSH key $key, you would not be able to login."
		exit 1
	fi
done

# Create a hard disk and partition it:

mkdir -p "${TARGETDIR}"
if [ -f "${TARGETDIR}/disk.img" ] ; then
	echo "Disk exists, skipping."
else
	dd if=/dev/zero bs=1M of="${TARGETDIR}/disk.img" count=1 seek=$(( ${DISKSIZE} * 1024 - 1 ))
	freeloop=` losetup -f `
	losetup $freeloop "${TARGETDIR}/disk.img"
	# Partition the disk
	parted -s $freeloop mklabel msdos
	parted -s $freeloop unit B mkpart primary ext4  $(( 1024 ** 2 )) $(( 1024 ** 3 * $BOOTSIZE - 1 ))
	parted -s $freeloop unit B mkpart primary ext4  $(( 1024 ** 3 * $BOOTSIZE )) $(( 1024 ** 3 * ( $BOOTSIZE + SWAPSIZE ) - 1 ))
	parted -s $freeloop unit B mkpart primary ext4  $(( 1024 ** 3 * ( $BOOTSIZE + SWAPSIZE ) )) 100%
	parted -s $freeloop unit B set 1 boot on
	parted -s $freeloop unit B print
fi

# Mount and debootstrap:

if [ -f "${TARGETDIR}/.bootstrap.success" ] ; then
	echo "Already bootstrapped, skipping."
else
	if [ -z "$freeloop" ] ; then
		freeloop=` losetup -f `
		losetup $freeloop "${TARGETDIR}/disk.img"
	fi
	sync
	sleep 5
	kpartx -a $freeloop
	mkdir -p "${TARGETDIR}/.target"
	mkfs.ext4 /dev/mapper/${freeloop#/dev/}p1
	mkfs.${ROOTFS} /dev/mapper/${freeloop#/dev/}p3
	# When using btrfs create a subvolume _install and use as default to make versioning easier
	MOUNTOPTS="defaults"
	case ${ROOTFS} in 
		btrfs)
			mount -o rw /dev/mapper/${freeloop#/dev/}p3 "${TARGETDIR}/.target"
			btrfs subvolume create "${TARGETDIR}/.target/_install"
			umount /dev/mapper/${freeloop#/dev/}p3
			MOUNTOPTS='subvol=_install'
		;;
	esac
	mkswap /dev/mapper/${freeloop#/dev/}p2
	mount -o rw,"${MOUNTOPTS}" /dev/mapper/${freeloop#/dev/}p3 "${TARGETDIR}/.target"
	mkdir -p "${TARGETDIR}/.target/boot"
	mount -o rw /dev/mapper/${freeloop#/dev/}p1 "${TARGETDIR}/.target/boot"
	mkdir -p "${TARGETDIR}/.target/boot/modules"
	mkdir -p "${TARGETDIR}/.target/boot/firmware"
	mkdir -p "${TARGETDIR}/.target/lib"
	ln -s /boot/modules "${TARGETDIR}/.target/lib/modules"
	ln -s /boot/firmware "${TARGETDIR}/.target/lib/firmware"
	# This is the installation!
	archivedir=""
	if [ -n "$PKGCACHE" ]; then
		if [ -n "$UBUEDITION" ] ; then
			archivedir="${PKGCACHE}/ubuntu/archives"
		elif [ -n "$DEBEDITION" ] ; then
			archivedir="${PKGCACHE}/debian/archives"
		else
			archivedir="${PKGCACHE}/devuan/archives"
		fi
	fi
	mkdir -p "${TARGETDIR}/.target"/var/cache/apt/archives
	if [ -n "$PKGCACHE" ]; then
		mount --bind "$archivedir" "${TARGETDIR}/.target"/var/cache/apt/archives
	else
		mount -t tmpfs -o size=4G,mode=0755 tmpfs "${TARGETDIR}/.target"/var/cache/apt/archives
	fi
	if [ -n "$UBUEDITION" ] ; then
		debootstrap --arch $ARCH $UBUEDITION "${TARGETDIR}/.target" $UBUSERVER
	elif [ -n "$DEBEDITION" ] ; then
		debootstrap --arch $ARCH $DEBEDITION "${TARGETDIR}/.target" $DEBSERVER
	else
		debootstrap --arch $ARCH $DEVEDITION "${TARGETDIR}/.target" $DEVSERVER
	fi
	mount -t proc none "${TARGETDIR}/.target"/proc
	mount --bind /sys "${TARGETDIR}/.target"/sys
	mount --bind /dev "${TARGETDIR}/.target"/dev
	mount -t devpts none "${TARGETDIR}/.target"/dev/pts
	echo 'en_US.UTF-8 UTF-8' > "${TARGETDIR}/.target"/etc/locale.gen
	chroot "${TARGETDIR}/.target" locale-gen
	chroot "${TARGETDIR}/.target" shadowconfig on
	if [ -n "$UBUEDITION" ] ; then
	
cat > "${TARGETDIR}/.target"/etc/apt/sources.list << EOF

deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} main restricted
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} main restricted
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates main restricted
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates main restricted
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} universe
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} universe
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates universe
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates universe
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} multiverse
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} multiverse
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates multiverse
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates multiverse
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-backports main restricted universe multiverse
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${UBUEDITION}-security main restricted
deb-src http://security.ubuntu.com/ubuntu ${UBUEDITION}-security main restricted
deb http://security.ubuntu.com/ubuntu ${UBUEDITION}-security universe
deb-src http://security.ubuntu.com/ubuntu ${UBUEDITION}-security universe
deb http://security.ubuntu.com/ubuntu ${UBUEDITION}-security multiverse
deb-src http://security.ubuntu.com/ubuntu ${UBUEDITION}-security multiverse

EOF

	elif [ -n "$DEBEDIDION" ] ; then

cat > "${TARGETDIR}/.target"/etc/apt/sources.list << EOF

deb http://deb.debian.org/debian/ ${DEBEDITION} main contrib non-free
deb https://security.debian.org/debian-security ${DEBEDITION}-security main contrib non-free
deb http://deb.debian.org/debian/ ${DEBEDITION}-updates main contrib non-free
deb http://deb.debian.org/debian ${DEBEDITION}-proposed-updates main contrib non-free
deb http://deb.debian.org/debian-security/ ${DEBEDITION}-security main contrib non-free
# deb http://deb.debian.org/debian/ ${DEBEDITION}-backports main contrib non-free

EOF
	
	else
cat > "${TARGETDIR}/.target"/etc/apt/sources.list << EOF

deb http://deb.devuan.org/merged ${DEVEDITION}          main
deb http://deb.devuan.org/merged ${DEVEDITION}-updates  main
deb http://deb.devuan.org/merged ${DEVEDITION}-security main
	
EOF

	fi
	# Devuan users shall manually adjust their sources.list, since they mix in matching Debian! 
	
	chroot "${TARGETDIR}/.target" apt-get -y install ca-certificates
	chroot "${TARGETDIR}/.target" apt-get -y update
	chroot "${TARGETDIR}/.target" apt-get -y install screen linux-image-generic openssh-server \
		rsync btrfs-progs openntpd ifupdown net-tools syslinux-common extlinux locales
	chroot "${TARGETDIR}/.target" apt-get -y dist-upgrade
	extlinux -i "${TARGETDIR}/.target/boot"
	if [ -z "$UBUEDITION" ] ; then
		kernel=` ls "${TARGETDIR}/.target/boot/" | grep vmlinuz- | tail -n 1 `
		initrd=` ls "${TARGETDIR}/.target/boot/" | grep initrd.img- | tail -n 1 `
		ln -s $kernel "${TARGETDIR}/.target/boot/vmlinuz"
		ln -s $initrd "${TARGETDIR}/.target/boot/initrd.img"
		chroot "${TARGETDIR}/.target" locale-gen
	fi
	for d in $EXTRADEBS ; do
		chroot "${TARGETDIR}/.target" apt-get -y install $d
	done
	rm "${TARGETDIR}/.target"/etc/resolv.conf
	echo "nameserver $NAMESERVER" > "${TARGETDIR}/.target"/etc/resolv.conf
	echo "$HOSTNAME" > "${TARGETDIR}/.target"/etc/hostname
	# echo btrfs >> "${TARGETDIR}/.target"/etc/initramfs-tools/modules # Brauchen wir das?
	mkdir -m 0600 "${TARGETDIR}/.target/root/.ssh"
	for key in $SSHKEYS ; do
		cat "$key" >> "${TARGETDIR}/.target/root/.ssh/authorized_keys"
	done
	eval ` blkid -o udev /dev/mapper/${freeloop#/dev/}p1 `
	UUID_BOOT=$ID_FS_UUID
	eval ` blkid -o udev /dev/mapper/${freeloop#/dev/}p2 `
	UUID_SWAP=$ID_FS_UUID
	eval ` blkid -o udev /dev/mapper/${freeloop#/dev/}p3 `
	UUID_ROOT=$ID_FS_UUID
cat > "${TARGETDIR}/.target"/etc/fstab << EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=${UUID_ROOT} /               ${ROOTFS}   ${MOUNTOPTS} 0       1
UUID=${UUID_BOOT} /boot           ext4        defaults 0       0
UUID=${UUID_SWAP} none            swap        sw       0       0

EOF

cat > "${TARGETDIR}/.target"/etc/network/interfaces << EOF
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
# allow-hotplug eth0
auto eth0
iface eth0 inet dhcp

EOF

	dd if="${TARGETDIR}/.target"/usr/lib/EXTLINUX/mbr.bin of=${freeloop} count=1 bs=448 # max size of an MBR
	
cat > "${TARGETDIR}/.target"/boot/extlinux.conf << EOF
# No frills bootloader config for extlinux/syslinux
DEFAULT ubuntu
TIMEOUT 50
PROMPT 1

LABEL ubuntu
	KERNEL /vmlinuz 
	APPEND initrd=/initrd.img root=/dev/vda3 ro nosplash net.ifnames=0 biosdevname=0

EOF

	# Tunneled devices are not seen from the outside until at least one outgoing
	# packet has occured, so just ping the nameservers to make sure, hosts
	# with static address configuration are seen from the outside.

cat > "${TARGETDIR}/.target"/etc/rc.local << EOF
#!/bin/bash

ping -c 1 $NAMESERVER
exit 0

EOF

	chmod 0755 "${TARGETDIR}/.target"/etc/rc.local
	if [ -n "$ADDUSER" ] ; then
		echo "Adding user $ADDUSER"
		chroot "${TARGETDIR}/.target" adduser "$ADDUSER"
	fi
	if [ "$ROOTPASS" -gt 0 ] ; then
		echo "Adding a root password for console login"
		chroot "${TARGETDIR}/.target" passwd
	fi
	for d in dev/pts dev sys proc boot var/cache/apt/archives ; do umount -f "${TARGETDIR}/.target"/$d ; done 
	umount "${TARGETDIR}/.target"
	dmsetup remove /dev/mapper/${freeloop#/dev/}p3
	dmsetup remove /dev/mapper/${freeloop#/dev/}p2
	dmsetup remove /dev/mapper/${freeloop#/dev/}p1
	losetup -d $freeloop && touch "${TARGETDIR}/.bootstrap.success"
fi

# First run

# apt install qemu-system-x86 qemu 
qemu-system-x86_64 -enable-kvm -smp cpus="$CPUS" -m "$MEM" -drive \
	file="${TARGETDIR}"/disk.img,if=virtio,format=raw \
	-pidfile "${TARGETDIR}/qemu.pid" \
	$NET $DAEMONIZE $EXTRAS \
	-vnc "$VNC"
retval="$?"
if [ "$retval" -lt 1 ] ; then
	echo "Successfully started, use"
	echo ""
	echo "    vncviewer localhost${VNC}"
	echo ""
	echo "to get a console."
else 	
	echo ""
	echo "Ooopsi."
	echo "Start failed, please check your configuration."
fi
