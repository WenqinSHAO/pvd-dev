#!/bin/bash -e

CD="$( cd "$( dirname $0 )" && pwd )"
cd $CD

. ../scripts/scriptlib/scriptlib.sh
scl_load_module net
scl_load_module vms
scl_load_module ui

ROOT="$(realpath $CD/../)"
TMP="$ROOT/tmp/linux-env"
RUN="$ROOT/run/linux-env"
mkdir -p $TMP
mkdir -p $RUN

VM_DRIVE=$RUN/vm/disk.qcow2
VM_RAM=8G
VM_CPUS=8
VM_DRIVE_SIZE=40G
VM_TELNET_PORT=12150
VM_VNC_PORT=12250
VM_MNGMT_PORT=12350

UBUNTU_ISO=http://archive.ubuntu.com/ubuntu/dists/zesty/main/installer-amd64/current/images/netboot/mini.iso
UBUNTU_MIRROR=""

KERNEL_SRC_DIR=$ROOT/src/linux-env/

PRESEED_FILE=$CD/preseed.cfg
PRESEED_CUSTOM_FILE=$CD/preseed-custom.cfg

scl_cmd_add install dep install_dep
function install_dep {
	sudo apt-get install qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils build-essential
	sudo apt-get build-dep linux-image-$(uname -r)
}

scl_cmd_add kernel compile compile_kernel
function compile_kernel {
	if [ ! -d $KERNEL_SRC_DIR/linux-ubuntu-zesty ]; then
		mkdir -p $KERNEL_SRC_DIR
		git clone git://kernel.ubuntu.com/ubuntu/ubuntu-zesty.git $KERNEL_SRC_DIR/linux-ubuntu-zesty
		cd $KERNEL_SRC_DIR/linux-ubuntu-zesty
		fakeroot debian/rules clean
	fi
	cd $KERNEL_SRC_DIR/linux-ubuntu-zesty
	fakeroot debian/rules binary-headers binary-generic binary-perarch
}

scl_cmd_add vm create create_host_vm
function create_host_vm {
	vm_is_running && echo "VM is already running" && return 1
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
}

scl_cmd_add kernel install install_kernel
function install_kernel {
	mkdir -p $TMP/mount
	pkg="$KERNEL_SRC_DIR/linux-image-4.10.0-40-generic_4.10.0-40.44_amd64.deb"
	
	if [ ! -e $pkg ]; then
		compile_kernel
		[ ! -e $pkg ] && echo "Package not found" && return 1
	fi
	
	qcow2_mount $VM_DRIVE $TMP/mount
	sudo mount -o bind /proc $TMP/mount/proc
	sudo mount -o bind /dev  $TMP/mount/dev
	
	mkdir -p $TMP/mount/tmp/
	cp $pkg $TMP/mount/tmp/$pkg
	sudo chroot $TMP/mount/ dpkg -i /tmp/$pkg || /bin/true
	rm $TMP/mount/tmp/$pkg
	
	sudo umount $TMP/mount/proc
	sudo umount $TMP/mount/dev
	qcow2_umount $TMP/mount
}

function vm_is_running {
	[ -f "$VM_DRIVE" ] && [ -f $TMP/qemu.pid ] && \
		[ -e "/proc/$(cat $TMP/qemu.pid)" ]
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
	[ ! -e "$VM_DRIVE" ] && scl_askyn "Create VM ?" && create_host_vm
	[ ! -e "$VM_DRIVE" ] && { echo "VM Driver does not exist" && return 1; }
	vm_is_running && echo "VM is already running" && return 1
	
	IP_ADDRESS=$(scl_local_ip)
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
	! vm_is_running && echo "VM is already running" && return 1
	sudo kill $(sudo cat $TMP/qemu.pid)
}

scl_main $@
