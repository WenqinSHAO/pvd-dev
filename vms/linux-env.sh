#!/bin/bash -e
LAUNCH_DIR=$PWD
# directory where this script sits
CD="$( cd "$( dirname $0 )" && pwd )" 
cd $CD

# predefined module fetched by bootstrap.sh
. ../scripts/scriptlib/scriptlib.sh
scl_load_module net
scl_load_module vms
scl_load_module ui

# the root directory of the project
ROOT="$(realpath $CD/../)"
# all things here are ephemeral
TMP="$ROOT/tmp/linux-env"
# where we put the VM disk
RUN="$ROOT/run/linux-env"
mkdir -p $TMP
mkdir -p $RUN

# VM disk name
VM_DRIVE=$RUN/vm/disk.qcow2
# VM specs, please configure according your hardware capability
VM_RAM=8G
VM_CPUS=8
VM_DRIVE_SIZE=40G
VM_TELNET_PORT=12150
VM_VNC_PORT=12250
VM_MNGMT_PORT=12350

# where to fetch the installation image for ubuntu
UBUNTU_ISO=http://archive.ubuntu.com/ubuntu/dists/zesty/main/installer-amd64/current/images/netboot/mini.iso
UBUNTU_MIRROR=""
UBUNTU_KERNEL_GIT=git://kernel.ubuntu.com/ubuntu/ubuntu-artful.git

# where we put the kernel source code
KERNEL_SRC_DIR=$ROOT/src/linux-env/
# where we put the kernel patch
KERNEL_PATCH_DIR=$ROOT/src/pvd-kernel-path/
# the default kernel local version after patching
KERNEL_LOCAL_VERSION="thierry-pvd"

# VM setting
PRESEED_FILE=$CD/preseed.cfg
PRESEED_CUSTOM_FILE=$CD/preseed-custom.cfg

# where to fetch path and other pvd related projects
PVD_KERNEL_PATCH=https://github.com/IPv6-mPvD/pvd-linux-kernel-patch.git
PVD_RADVD=https://github.com/IPv6-mPvD/radvd.git
PVD_PVDD=https://github.com/IPv6-mPvD/pvdd.git

scl_cmd_add install dep install_dep
function install_dep {
	# this function installs the necessary packages for VM installation and kernel compilation
	sudo apt-get install git kernel-wedge libssl-dev gawk libudev-dev pciutils-dev byacc flex linux-tools-common libncurses5-dev
	sudo apt-get install qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils build-essential
	sudo apt-get build-dep linux-image-$(uname -r)
}

scl_cmd_add kernel download download_kernel
function download_kernel {
	# this function downloads the kernel src to $KERNEL_SRC_DIR
	if [ ! -d $KERNEL_SRC_DIR/linux-ubuntu ]; then
		mkdir -p $KERNEL_SRC_DIR
		git clone $UBUNTU_KERNEL_GIT $KERNEL_SRC_DIR/linux-ubuntu
	else
		scl_askyn "Kernel source repo already exist, do you want to clean it?" && clean_kernel
	fi
}

scl_cmd_add kernel patch patch_kernel
function patch_kernel {
	# this function patchs the kernel src in $KERNEL_SRC_DIR
	# first download patch
	if [ ! -d $KERNEL_PATCH_DIR ]; then
		mkdir -p $KERNEL_PATCH_DIR
		git clone $PVD_KERNEL_PATCH $KERNEL_PATCH_DIR
	elif scl_askyn "Kernel patch already exists in $KERNEL_PATCH_DIR, do you want to enforce the new one?"; then
		rm -rf $KERNEL_PATCH_DIR
		mkdir -p $KERNEL_PATCH_DIR
		git clone $PVD_KERNEL_PATCH $KERNEL_PATCH_DIR
	fi
	# then patch
	if [ -d $KERNEL_SRC_DIR/linux-ubuntu ]; then
		clean_kernel
		cd $KERNEL_SRC_DIR/linux-ubuntu
		patch -p1 < $KERNEL_PATCH_DIR/patch* 
	else
		echo "Kernel source is absent at $KERNEL_SRC_DIR/linux-ubuntu, patching failed." 
		echo "Please consider first dowload it using option: $0 kernel download." 
		cd $CD && return 1
	fi

	cd $CD
}

scl_cmd_add kernel clean clean_kernel
function clean_kernel {
	# this function reset the kernel src repo to git head and removes untracked files
	cd $KERNEL_SRC_DIR/linux-ubuntu
	git reset --hard
	git clean -fd
	rm -f .config
	cd $CD
}

scl_cmd_add kernel config configure_kernel
function configure_kernel {
	# this function configures the kernel
	# it seems the kernel config can be already done with proper kernel patch?
	cd $KERNEL_SRC_DIR/linux-ubuntu
	if [ -f .config ]; then
		echo "Set local kernel version to $KERNEL_LOCAL_VERSION and enable pvd"
		make olddefconfig
		sed -i "s/^CONFIG_LOCALVERSION.*/CONFIG_LOCALVERSION=\"$KERNEL_LOCAL_VERSION\"/" .config
		sed -i 's/^CONFIG_NETPVD.*/CONFIG_NETPVD=y/' .config
	else
		echo "Something must have gone wrong with the kernel patching" && cd $CD && return 1
	fi

	cd $CD
}

scl_cmd_add kernel bltpkg build_kernel
function build_kernel {
	# this function compiles the kernel into .deb
	configure_kernel
	cd $KERNEL_SRC_DIR/linux-ubuntu
	n_core=$(grep -c ^processor /proc/cpuinfo)
	echo "Now compiling the kernel with all your $n_core cores. It's going to take a while."
	let n_core++
	make -j$n_core deb-pkg
	cd $CD
}


scl_cmd_add kernel compile compile_kernel
function compile_kernel {
	# this function downloads the kernel source and compile it right away
	if [ ! -d $KERNEL_SRC_DIR/linux-ubuntu ]; then
		mkdir -p $KERNEL_SRC_DIR
		git clone $UBUNTU_KERNEL_GIT $KERNEL_SRC_DIR/linux-ubuntu
		cd $KERNEL_SRC_DIR/linux-ubuntu
		fakeroot debian/rules clean
	fi
	cd $KERNEL_SRC_DIR/linux-ubuntu
	fakeroot debian/rules binary-headers binary-generic binary-perarch

	cd $CD
}

scl_cmd_add vm create create_host_vm
function create_host_vm {
	# this function installs the VM from iso
	vm_is_running && return 1
	if [ -e "$VM_DRIVE" ]; then
		echo "VM drive $VM_DRIVE exists."
		if scl_askyn "Would you like to delete the disk and reinstall ?" ; then
			rm $VM_DRIVE
		else
			return 1
		fi
	fi
	
	IP_ADDRESS=$(scl_local_ip)
	
	echo "Getting Ubuntu installer"
	wget -N $UBUNTU_ISO -O $TMP/mini.iso
	mkdir -p $TMP/mini
	sudo mount -o loop $TMP/mini.iso $TMP/mini
	[ -e "$TMP/linux" ] && rm -f $TMP/linux
	[ -e "$TMP/initrd.gz" ] && rm -f $TMP/initrd.gz
	cp $TMP/mini/linux $TMP/linux
	cp $TMP/mini/initrd.gz $TMP/initrd.gz
	sudo umount $TMP/mini
	rmdir $TMP/mini
	
	echo "Generating preseed file"
	cp $PRESEED_FILE $TMP/preseed.cfg
	if [ -f $PRESEED_CUSTOM_FILE ]; then
		while read -r line
		do
			a=( $line )
			if [ "${a[1]}" != "" ]; then
				echo "  Custom preseed line: $line"
				sed -i "s:d-i[ \t][ \t]*${a[1]}[ \t][ \t]*.*::" $TMP/preseed.cfg
				echo >> $TMP/preseed.cfg
				echo -n $line >> $TMP/preseed.cfg
			fi
		done < "$PRESEED_CUSTOM_FILE"
	fi
	
	echo "Updating installer with custom preseed file"
	mkdir -p $TMP/irmod
	sudo -s <<EOF
cd "$TMP/irmod"
gzip -d < $TMP/initrd.gz | cpio --extract --make-directories --no-absolute-filenames 2>/dev/null
cp $TMP/preseed.cfg $TMP/irmod/preseed.cfg
find . | cpio -H newc --create | gzip -9 > $TMP/initrd.mod.gz 2>/dev/null
rm -fr "$TMP/irmod"
EOF

	echo "Creating VM disk"
	mkdir -p $(dirname "$VM_DRIVE")
	qemu-img create -f qcow2 $TMP/vmdrive $VM_DRIVE_SIZE
	
	echo "Installation will now start. This can take a while."
	echo "Connect to VNC with vnc://$IP_ADDRESS:$VM_VNC_PORT/ with passwd 'pvd' to see progress."
	sudo qemu-system-x86_64 -enable-kvm \
		-monitor "telnet:127.0.0.1:$VM_TELNET_PORT,server,nowait" \
		-cpu host -m $VM_RAM -smp $VM_CPUS \
		-drive file=$TMP/vmdrive,format=qcow2,index=1 \
		-display vnc=0.0.0.0:$(($VM_VNC_PORT - 5900)),password \
		-vga std \
		-device e1000,netdev=nat \
		-netdev user,id=nat,hostfwd=tcp::$VM_MNGMT_PORT-:22 \
		-net nic,model=virtio,macaddr=00:16:3e:00:01:01,netdev=nic-0 \
		-netdev tap,id=nic-0,vhost=on \
		-no-reboot -kernel $TMP/linux -initrd $TMP/initrd.mod.gz \
		-daemonize -pidfile $TMP/qemu.pid \
		-append "netcfg/choose_interface=ens4 apt-setup/proposed=true nomodeset fb=false priority=critical locale=en_US preseed/file=/preseed.cfg" || true
	
	echo "change vnc password pvd" | nc -q 0 127.0.0.1 $VM_TELNET_PORT >/dev/null 2>&1
		
	sleep 5
	PID=$(sudo cat $TMP/qemu.pid)
	trap "sudo kill $PID" SIGINT SIGTERM
	rm -f $TMP/linux $TMP/initrd.mod.gz $TMP/qemu.pid
	
	spin='-\|/'
	i=0
	while [ -e /proc/$PID ]
	do
		i=$(( (i+1) %4 ))
		printf "\r${spin:$i:1} $(du -h $TMP/vmdrive)"
	    sleep 0.5
	done
	
	mv $TMP/vmdrive $VM_DRIVE

	cd $CD
}

scl_cmd_add vm isoboot isoboot_vm
function isoboot_vm() {
	# this function boots the VM from an ISO image speficified as argument
	# it is useful when it comes to boot repair
	IP_ADDRESS=$(scl_local_ip)
	cd $LAUNCH_DIR

	[ ! -f $1 ] && echo "ISO file $1 does not exist" && cd $CD && return 1
	
	vm_is_running && cd $CD && return 1
	
	# suppose that if /dev/nbd0* is mounted, it must be with our qcow2 img
	# it is though not necessarily true...
	MOUNT_DIR=$(mount | grep -F "/dev/nbd0" | cut -d' ' -f3)
	if [ ! $MOUNT_DIR = "" ]; then
		echo "$VM_DRIVE is already mounted at $MOUNT_DIR."
		if scl_askyn "Unmount $VM_DRIVE and then continue ?"; then
			scl_qcow2_umount $MOUNT_DIR
		else
			cd $CD && return 1
		fi
	fi

	echo "Booting VM with ISO: `realpath $1`"
	echo "vnc://$IP_ADDRESS:$VM_VNC_PORT/ with passwd 'pvd'"
	sudo qemu-system-x86_64 -enable-kvm \
		-monitor "telnet:127.0.0.1:$VM_TELNET_PORT,server,nowait" \
		-cpu host -m $VM_RAM -smp $VM_CPUS \
		-drive file=$VM_DRIVE,format=qcow2,index=1 \
		-cdrom $1 -boot d \
		-display vnc=0.0.0.0:$(($VM_VNC_PORT - 5900)),password \
		-vga std \
		-device e1000,netdev=nat \
		-netdev user,id=nat,hostfwd=tcp::$VM_MNGMT_PORT-:22 \
		-net nic,model=virtio,macaddr=00:16:3e:00:01:01,netdev=nic-0 \
		-netdev tap,id=nic-0,vhost=on \
		-daemonize -pidfile $TMP/qemu.pid
	
	echo "change vnc password pvd" | nc -q 0 127.0.0.1 $VM_TELNET_PORT >/dev/null 2>&1
	sudo chmod a+r $TMP/qemu.pid

	cd $CD
}

scl_cmd_add kernel install install_kernel
function install_kernel() {

	if vm_is_running; then
		if scl_askyn "Would like to turn off VM right now to continue ?"; then
			stop_host_vm && sleep 0.5
		else
			return 1
		fi
	fi

	mkdir -p $TMP/mount

	scl_qcow2_mount $VM_DRIVE $TMP/mount
	sudo mount -o bind /proc $TMP/mount/proc
	sudo mount -o bind /dev  $TMP/mount/dev
	
	mkdir -p $TMP/mount/tmp/
	echo "Installing following complied .deb to the VM:"
	ls -la $KERNEL_SRC_DIR | grep linux-.*.deb$
	cp $KERNEL_SRC_DIR/linux-*.deb $TMP/mount/tmp/
	sudo chroot $TMP/mount/ dpkg -i -R /tmp/ || /bin/true
	sudo chroot $TMP/mount/ sed -i 's/^GRUB_HIDDEN/#&/' /etc/default/grub
	rm $TMP/mount/tmp/*.deb
	
	sudo umount $TMP/mount/proc
	sudo umount $TMP/mount/dev
	scl_qcow2_umount $TMP/mount
}

scl_cmd_add vm status vm_is_running
function vm_is_running {
	if [ -f "$VM_DRIVE" ] && [ -f $TMP/qemu.pid ] && \
		[ -e "/proc/$(cat $TMP/qemu.pid)" ]; then
		local IP_ADDRESS=$(scl_local_ip)
		echo "VM is already running, accessible via vnc://$IP_ADDRESS:$VM_VNC_PORT/ with passwd 'pvd'"
	else
		return 1
	fi
}

scl_cmd_add vm ssh ssh_host_vm
function ssh_host_vm () {
	! vm_is_running && echo "VM is not running" && return 1
	username=$(scl_ask "Enter VM's username")
	ip=$(scl_local_ip)
	ssh -p $VM_MNGMT_PORT $username@$ip $@
}

scl_cmd_add vm start start_host_vm
function start_host_vm {
	IP_ADDRESS=$(scl_local_ip)

	[ ! -e "$VM_DRIVE" ] && scl_askyn "Create VM ?" && create_host_vm
	[ ! -e "$VM_DRIVE" ] && { echo "VM Driver does not exist" && return 1; }

	# suppose that if /dev/nbd0* is mounted, it must be with our qcow2 img
	# it is though not necessarily true...
	local mount_dir=$(mount | grep -F "/dev/nbd0" | cut -d' ' -f3)
	if [ ! $mount_dir = "" ]; then
		echo "$VM_DRIVE is already mounted at $mount_dir."
		if scl_askyn "Unmount $VM_DRIVE and then continue ?"; then
			scl_qcow2_umount $mount_dir
		else
			cd $CD && return 1
		fi
	fi

	vm_is_running && return 1
	
	echo "vnc://$IP_ADDRESS:$VM_VNC_PORT/ with passwd 'pvd'"
	sudo qemu-system-x86_64 -enable-kvm \
		-monitor "telnet:127.0.0.1:$VM_TELNET_PORT,server,nowait" \
		-cpu host -m $VM_RAM -smp $VM_CPUS \
		-drive file=$VM_DRIVE,format=qcow2,index=1 \
		-display vnc=0.0.0.0:$(($VM_VNC_PORT - 5900)),password \
		-vga std \
		-device e1000,netdev=nat \
		-netdev user,id=nat,hostfwd=tcp::$VM_MNGMT_PORT-:22 \
		-net nic,model=virtio,macaddr=00:16:3e:00:01:01,netdev=nic-0 \
		-netdev tap,id=nic-0,vhost=on \
		-daemonize -pidfile $TMP/qemu.pid
	
	echo "change vnc password pvd" | nc -q 0 127.0.0.1 $VM_TELNET_PORT >/dev/null 2>&1
	sudo chmod a+r $TMP/qemu.pid
}

scl_cmd_add vm stop stop_host_vm
function stop_host_vm {
	! vm_is_running &> /dev/null && echo "VM is already turned off" && return 1
	sudo kill $(sudo cat $TMP/qemu.pid)
}

scl_main $@
