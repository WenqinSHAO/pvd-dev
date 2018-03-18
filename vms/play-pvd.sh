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
# where lies the pvd-aware iproute src
DIR_IPROUTE="$ROOT/iproute"
# where we put the VM disk
DIR_RADVD="$ROOT/radvd"

LINK_IPROUTE=https://github.com/IPv6-mPvD/iproute2.git
# TODO: change to the official repo once pull request accepted
LINK_RADVD=https://github.com/IPv6-mPvD/radvd.git

scl_cmd_add install dep install_dep
function install_dep {
	# this function installs the necessary packages
	sudo apt-get install iproute2 net-tools flex bison autotools-dev autoconf bridge-utils libglib2.0-dev
}

scl_cmd_add install radvd install_radvd
function install_radvd {
    # downlods the source code of radvd and installs it
    if [ ! -d $DIR_RADVD ]; then
        git clone $LINK_RADVD $DIR_RADVD
        cd $DIR_RADVD
        git checkout pvd-draft-01
        sudo autoscan
        sudo aclocal
        sudo autoheader
        sudo autoconf
        sudo automake --add-missing
        sudo ./configure
        sudo make
        if [ -f ./radvd ]; then
            echo "PvD-aware radvd is installed in $DIR_RADVD."
        else
            echo "Radvd installation failed."
        fi
        cd $ROOT
    else
        if [ -f $DIR_RADVD/radvd ]; then
            echo "PvD-aware radvd is already installed in $DIR_RADVD."
        else
            sudo rm -rf $DIR_RADVD
            install_radvd
        fi
    fi
}

scl_cmd_add install iproute install_iproute
function install_iproute {
    # download the source code of iproute2 and install it
    if [ ! -d $DIR_IPROUTE ]; then
        git clone $LINK_IPROUTE $DIR_IPROUTE
        cd $DIR_IPROUTE
        git checkout pvd
        sudo ./configure
        sudo make
        if [ -f ip/ip ]; then
            echo "PvD-aware iproute2 is installed in $DIR_IPROUTE/ip/."
        else
            echo "iproute2 installation failed."
        fi
        cd $ROOT
    else
        if [ -f $DIR_IPROUTE/ip/ip ]; then
            echo "PvD-aware iproute2 already installed in $DIR_IPROUTE/ip/."
        else
            sudo rm -rf $DIR_IPROUTE
            install_iproute
        fi
    fi
}

scl_cmd_add setup network_setup
function network_setup {
    # separate router and endhost in two network namespaces
    sudo ip netns add host_pvd  # pvd parsing enabled
    sudo ip netns add host_classic # host does not parse pvd
    sudo ip netns add router
    # first creat the bridge between the endhost and the router
    sudo brctl addbr brpvd
    # veth pair between host_pvd and the bridge
    sudo ip link add eh0 type veth peer name brif0
    # veth pair between host_classic and the bridge
    sudo ip link add eh1 type veth peer name brif1
    # 1st veth pair between router and the bridge
    sudo ip link add rt0 type veth peer name brif2
    # 2nd veth pair between router and the bridge
    sudo ip link add rt1 type veth peer name brif3
    #3rd veth pair between router and the bridge
    sudo ip link add rt2 type veth peer name brif4
    # add brif* to the bridge
    sudo brctl addif brpvd brif0
    sudo brctl addif brpvd brif1
    sudo brctl addif brpvd brif2
    sudo brctl addif brpvd brif3
    sudo brctl addif brpvd brif4
    # add the other side the veth pair to corresponding network namespaces
    sudo ip link set eh0 netns host_pvd
    sudo ip link set eh1 netns host_classic
    sudo ip link set rt0 netns router
    sudo ip link set rt1 netns router
    sudo ip link set rt2 netns router
    # turn up the devices
    sudo ip link set brpvd up
    sudo ip link set brif0 up
    sudo ip link set brif1 up
    sudo ip link set brif2 up
    sudo ip link set brif3 up
    sudo ip link set brif4 up
    sudo ip netns exec host_pvd ip link set eh0 up
    sudo ip netns exec host_pvd ip link set dev lo up
    sudo ip netns exec host_classic ip link set eh1 up
    sudo ip netns exec host_classic ip link set dev lo up
    sudo ip netns exec router ip link set rt0 up
    sudo ip netns exec router ip link set rt1 up
    sudo ip netns exec router ip link set rt2 up
    sudo ip netns exec router ip link set dev lo up
    # TCP UDP server listens on these addresses on the dummy interface
    sudo ip netns exec router ip link add dev dummy0 type dummy
    sudo ip netns exec router ip addr add 2001:1111:1111::8888/128 dev dummy0
    sudo ip netns exec router ip addr add 2001:1111:1111::8844/128 dev dummy0
    sudo ip netns exec router ip addr add 2001:2222:2222::2/128 dev dummy0
    sudo ip netns exec router ip link set dev dummy0 up
    # these static routes need to be changed in accordance to RA announces
    sudo ip netns exec router ip route add 2001:db8:1::/64 dev rt0
    sudo ip netns exec router ip route add 2001:db8:1:beef::/64 dev rt0
    sudo ip netns exec router ip route add 2001:db8:1:abcd::/64 dev rt0
    sudo ip netns exec router ip route add 2001:db8:2::/64 dev rt1
    sudo ip netns exec router ip route add 2001:db8:3::/64 dev rt2
    # disable RA acceptance on router interfaces
    sudo ip netns exec router sysctl -w net.ipv6.conf.rt0.accept_ra=0
    sudo ip netns exec router sysctl -w net.ipv6.conf.rt1.accept_ra=0
    sudo ip netns exec router sysctl -w net.ipv6.conf.rt2.accept_ra=0
    # turn on/off pvd parsing and route pref option on host
    sudo ip netns exec host_pvd sysctl -w net.ipv6.conf.eh0.parse_pvd=1
    sudo ip netns exec host_pvd sysctl -w net.ipv6.conf.eh0.accept_ra_pinfo=1
    sudo ip netns exec host_pvd sysctl -w net.ipv6.conf.eh0.accept_ra_rtr_pref=1
    sudo ip netns exec host_pvd sysctl -w net.ipv6.conf.eh0.accept_ra_rt_info_max_plen=64
    sudo ip netns exec host_classic sysctl -w net.ipv6.conf.eh1.parse_pvd=0
    sudo ip netns exec host_classic sysctl -w net.ipv6.conf.eh1.accept_ra_pinfo=1
    sudo ip netns exec host_classic sysctl -w net.ipv6.conf.eh1.accept_ra_rtr_pref=1
    sudo ip netns exec host_classic sysctl -w net.ipv6.conf.eh1.accept_ra_rt_info_max_plen=64
    # turn of ra acceptance on bridge interface
    sudo sysctl -w net.ipv6.conf.brpvd.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif0.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif1.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif2.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif3.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif4.accept_ra=0
}

scl_cmd_add cleanup network_reset
function network_reset {
    # it seems deleting the network namespace will as well delete the contaning devices
    # TODO: bug fix needed in cleanup
    sudo ip netns exec router ip link set rt0 down 2>&1 || true
    sudo ip netns exec router ip link set rt1 down 2>&1 || true
    sudo ip netns exec router ip link set rt2 down 2>&1 || true
    sudo ip netns exec host_pvd ip link set eh0 down 2>&1 || true
    sudo ip netns exec host_classic ip link set eh1 down 2>&1 || true

    sudo ip link set brif0 down 2>&1 || true
    sudo ip link set brif1 down 2>&1 || true
    sudo ip link set brif2 down 2>&1 || true
    sudo ip link set brif3 down 2>&1 || true
    sudo ip link set brif4 down 2>&1 || true

    sudo ip link delete brif0 2>&1 || true
    sudo ip link delete brif1 2>&1 || true
    sudo ip link delete brif2 2>&1 || true
    sudo ip link delete brif3 2>&1 || true
    sudo ip link delete brif4 2>&1 || true

    sudo ip netns delete host_pvd 2>&1 || true
    sudo ip netns delete host_classic 2>&1 || true
    sudo ip netns delete router  2>&1 || true

    sudo ip link set brpvd down 2>&1 || true
    sudo ip link delete brpvd 2>&1 || true
}

scl_cmd_add send ra send_ra 
function send_ra {
    # send RA in router nework namespace according to specified configuration file
    if [ $# -lt 1 ]; then
        echo "Usage: $0 send ra path/to/ra/config/file"
        return 1
    fi
    cd $LAUNCH_DIR
    if ! sudo ip netns show | grep router; then
        if scl_askyn "It seems network setting is not ready, setup now?"; then
            network_reset
            network_setup
        else
            echo "Operation aborted for inappropriate network setting."
            return 1
        fi
    fi
    if [ ! -f $DIR_RADVD/radvd ]; then
        if scl_askyn "Radvd is not yet installed, install now?"; then
            install_radvd
        else
            echo "RA can not be sent from router namespace, as Radvd is absent."
            return 1
        fi
    fi
    sudo ip netns exec router $DIR_RADVD/radvd -C $1 -d 5 -m stderr -n
}

scl_cmd_add show ip_wrapper
function ip_wrapper {
    # show address link or route for specified network namespace
    if [ $# -lt 2 ]; then
        echo "Usage: $0 show NAME_OF_NETWORK_NAMESPACE OBJECT."
        AVAIL_NETNS=$(sudo ip netns show | cut -d' ' -f 1 | tr '\n' '|')
        AVAIL_NETNS=${AVAIL_NETNS%?}
        echo "NAME_OF_NETWORK_NAMESPACE := {$AVAIL_NETNS}"
        echo "OBJECT := {address|link|route}"
        return 1
    fi
    if [ ! -f $DIR_IPROUTE/ip/ip ]; then
        if scl_askyn "iproute2 is not yet installed, install now?"; then
            install_iproute
        else
            echo "Address can not be shown, as iproute is absent."
            return 1        
        fi
    else
        sudo ip netns exec $1 $DIR_IPROUTE/ip/ip -6 $2 show
    fi
}

function e {
	echo ==== $@
	$@
}

scl_cmd_add hack_start_radvd hack_start_radvd
function hack_start_radvd {
	A=2001:67c:1230:

	mkdir -p ./tmp

	for e in big=e001 ben=f001 fettered=f101 ; do
		pvd=$(echo $e | sed 's/=/ /g' | awk '{print $1}')
		addr=$(echo $e | sed 's/=/ /g' | awk '{print $2}')

cat > ./tmp/${pvd}.conf << EOF
interface ve1br0 {
	MaxRtrAdvInterval 500;
	AdvLinkMTU 1500;
	AdvSendAdvert on;

	prefix ${A}${addr}::/64 {
		AdvAutonomous on;
		AdvRouterAddr off;
	};

	RDNSS 2001:4860:4860::8844 {
		AdvRDNSSLifetime 800;
	};

	pvd ${pvd}.mpvd.io {
		AdvPvdIdHttpExtraInfo on;
		AdvPvdIdLegacy off;
		AdvPvdAdvHeader on;
		AdvPvdIdSequenceNumber 113;

		DNSSL mpvd.io {
			AdvDNSSLLifetime 800;
		};

	};

};
EOF

		e sudo ip netns exec e1 $DIR_RADVD/radvd -C ./tmp/${pvd}.conf -m stderr -p ./tmp/${pvd}.pid
	done
}

scl_cmd_add hack_stop_radvd hack_stop_radvd
function hack_stop_radvd {
	set +e
	for pvd in big ben fettered; do
		if [ -f ./tmp/${pvd}.pid ]; then
			e sudo kill $(cat ./tmp/${pvd}.pid)
		fi
	done
}

scl_cmd_add hack_start hack_start
function hack_start {
	A=2001:67c:1230:

	IF_UP1=enx00e08f009c4c
	IF_UP2=enx00e08f009c41
	IF_DOWN=enx00e1000001a8

	for ns in u1 u2 r1 r2 e1 h1 h2 br0; do
		echo "Creating namespace $ns"
		e sudo ip netns add $ns
		e sudo ip netns exec $ns   ip link set lo up
	done

	for ns in u1 u2 r1 r2 e1; do
		echo "Enable routing in $ns"
		e sudo ip netns exec $ns   sysctl -w net.ipv6.conf.all.accept_ra=0
		e sudo ip netns exec $ns   sysctl -w net.ipv6.conf.all.forwarding=1
		e sudo ip netns exec $ns   sysctl -w net.ipv6.conf.default.accept_ra=0
		e sudo ip netns exec $ns   sysctl -w net.ipv6.conf.default.forwarding=1
	done


	links="u1:r1:e0a0 u2:r1:f0a0 u2:r2:f1a0 r1:e1:e0a1 r2:e1:f1a1 e1:br0 h1:br0 h2:br0"

	# Simple connexions between namespaces
	for e in $links; do
		i1=$(echo $e | sed 's/:/ /g' | awk '{print $1}')
		i2=$(echo $e | sed 's/:/ /g' | awk '{print $2}')
		a=$(echo $e | sed 's/:/ /g' | awk '{print $3}')
		echo "Connecting $i1 and $i2"
		e sudo ip link add v$i1$i2 type veth peer name v$i2$i1
		e sudo ip link set v$i1$i2 netns $i1
		e sudo ip link set v$i2$i1 netns $i2
		e sudo ip netns exec $i1    ip link set v$i1$i2 up
		e sudo ip netns exec $i2    ip link set v$i2$i1 up
		if [ "$a" != "" ]; then
			p=$A$a
			echo "Configuring prefix $p::/64"
			e sudo ip netns exec $i1    ip addr add $p::1/64 dev v$i1$i2
			e sudo ip netns exec $i2    ip addr add $p::2/64 dev v$i2$i1
		fi
	done

	e sudo ip netns exec br0  brctl addbr br0
	e sudo ip netns exec br0  brctl addif br0 vbr0e1
	e sudo ip netns exec br0  brctl addif br0 vbr0h1
	e sudo ip netns exec br0  brctl addif br0 vbr0h2
	e sudo ip netns exec br0  ip link set br0 up

	e sudo ip link set $IF_UP1 netns u1
	e sudo ip link set $IF_UP2 netns u2
	e sudo ip link set $IF_DOWN netns e1

	addr="u1=$IF_UP1=103::2 u2=$IF_UP2=103::3 e1=$IF_DOWN=e0a2::1 e1=ve1br0=e001::1 e1=ve1br0=f001::1 e1=ve1br0=f101::1"
	echo $addr

	# More specific address configuration
	for e in $addr ; do
		ns=$(echo $e | sed 's/=/ /g' | awk '{print $1}')
		if=$(echo $e | sed 's/=/ /g' | awk '{print $2}')
		addr=$(echo $e | sed 's/=/ /g' | awk '{print $3}')
		echo "Configuring address $A$addr/64 on $if"
		e sudo ip netns exec $ns    ip addr add $A$addr/64 dev $if
	done

	e sudo ip netns exec e1  ip -6 route add ::/0 from ${A}e000::/56 via ${A}e0a1::1
	e sudo ip netns exec e1  ip -6 route add ::/0 from ${A}f000::/56 via ${A}e0a1::1
	e sudo ip netns exec e1  ip -6 route add ::/0 from ${A}f100::/56 via ${A}f1a1::1

	for pvd in e0 f0 f1; do
		for nh in 2 3; do
			e sudo ip netns exec e1  ip -6 route add ${A}${pvd}0${nh}::/64 via ${A}e0a2::${nh}
		done
	done

	e sudo ip netns exec r1  ip -6 route add ::/0 from ${A}e000::/56 via ${A}e0a0::1
	e sudo ip netns exec r1  ip -6 route add ::/0 from ${A}f000::/56 via ${A}f0a0::1

	e sudo ip netns exec r2  ip -6 route add ::/0 via ${A}f1a0::1

	e sudo ip netns exec r1  ip -6 route add ${A}e000::/56 via ${A}e0a1::2
	e sudo ip netns exec r1  ip -6 route add ${A}f000::/56 via ${A}e0a1::2
	e sudo ip netns exec r2  ip -6 route add ${A}f100::/56 via ${A}f1a1::2

	e sudo ip netns exec r1  ip -6 route add ${A}e0a2::/64 via ${A}e0a1::2
	e sudo ip netns exec r2  ip -6 route add ${A}e0a2::/64 via ${A}f1a1::2

	e sudo ip netns exec u1  ip -6 route add ::/0 via ${A}103::1
	e sudo ip netns exec u2  ip -6 route add ::/0 via ${A}103::1

	e sudo ip netns exec u1  ip -6 route add ${A}e000::/56 via ${A}e0a0::2
	e sudo ip netns exec u2  ip -6 route add ${A}f000::/56 via ${A}f0a0::2
	e sudo ip netns exec u2  ip -6 route add ${A}f100::/56 via ${A}f1a0::2

	e sudo ip netns exec u1    ip link set $IF_UP1 up
	e sudo ip netns exec u2    ip link set $IF_UP2 up
	e sudo ip netns exec e1    ip link set $IF_DOWN up

	for ns in u1 u2 r1 r2 e1 h1 h2 br0; do
		echo ======================== $ns ==========================
		echo ========== link
		sudo ip netns exec $ns   ip link
		echo ========== addr
		sudo ip netns exec $ns   ip addr
		echo ========== route
		sudo ip netns exec $ns   ip -6 route
	done


	hack_start_radvd
}

# Switch to IOL mode
scl_cmd_add hack_iol hack_iol
function hack_iol {
	for e in u1 u2 e1; do
		e sudo ip netns exec r1    ip link set vr1$e down
		e sudo ip netns exec r1    ip link set netns 1 dev vr1$e
		e sudo brctl addbr br$e
		e sudo brctl addif br$e vr1$e
		e sudo ip link set vr1$e up
		e sudo ip link set br$e up
	done
}

# Switch to Linux mode mode
scl_cmd_add hack_linux hack_linux
function hack_linux {
	A=2001:67c:1230:

	list="u1=e0a0::2 u2=f0a0::2 e1=e0a1::1"

	for a in $list ; do
		e=$(echo $a | sed 's/=/ /g' | awk '{print $1}')
		addr=$(echo $a | sed 's/=/ /g' | awk '{print $2}')
		e sudo ip link set vr1$e down
		e sudo ip link set br$e down
		e sudo brctl delif br$e vr1$e
		e sudo brctl delbr br$e
		e sudo ip link set netns r1 dev vr1$e

		e sudo ip netns exec r1    ip link set vr1$e up
		e sudo ip netns exec r1    ip addr add ${A}${addr}/64 dev vr1$e
	done

	e sudo ip netns exec r1    ip -6 route add ::/0 from ${A}e000::/56 via ${A}e0a0::1
	e sudo ip netns exec r1    ip -6 route add ::/0 from ${A}f000::/56 via ${A}f0a0::1
	e sudo ip netns exec r1    ip -6 route add ${A}e000::/56 via ${A}e0a1::2
	e sudo ip netns exec r1    ip -6 route add ${A}f000::/56 via ${A}e0a1::2
	e sudo ip netns exec r1    ip -6 route add ${A}e0a2::/64 via ${A}e0a1::2
}

scl_cmd_add hack_test hack_test
function hack_test {
	#TARGET=2001:4860:4860::8888
	TARGET=2001:67c:1230:103::1
	for ns in u1 u2 r2 e1 h1 h2; do
		e sudo ip netns exec $ns    ping6 -c 1 $TARGET
	done
}

scl_cmd_add hack_stop hack_stop
function hack_stop {
	set +e
	hack_stop_radvd

	for ns in u1 u2 r1 r2 e1 h1 h2 br0; do
		e sudo ip netns del $ns
	done

	for e in u1 u2 e1; do
		e sudo ip link set br$e down
		e sudo brctl delbr br$e
		e sudo ip link del vr1$e
	done
}

scl_main $@