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
LINK_RADVD=https://github.com/WenqinSHAO/radvd.git

scl_cmd_add install dep install_dep
function install_dep {
	# this function installs the necessary packages
	sudo apt-get install iproute2 net-tools flex bison autotools-dev autoconf bridge-utils
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
        if [-f $DIR_RADVD/radvd]; then
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
    sudo ip netns add endhost
    sudo ip netns add router
    # first creat the bridge between the endhost and the router
    sudo brctl addbr brpvd
    # veth pair between endhost and the bridge
    sudo ip link add eh0 type veth peer name brif0
    # 1st veth pair between router and the bridge
    sudo ip link add rt0 type veth peer name brif1
    # 2nd veth pair between router and the bridge
    sudo ip link add rt1 type veth peer name brif2
    #3rd veth pair between router and the bridge
    sudo ip link add rt2 type veth peer name brif3
    # add brif* to the bridge
    sudo brctl addif brpvd brif0
    sudo brctl addif brpvd brif1
    sudo brctl addif brpvd brif2
    sudo brctl addif brpvd brif3
    # add the other side the veth pair to corresponding network namespaces
    sudo ip link set eh0 netns endhost
    sudo ip link set rt0 netns router
    sudo ip link set rt1 netns router
    sudo ip link set rt2 netns router
    # turn up the devices
    sudo ip link set brpvd up
    sudo ip link set brif0 up
    sudo ip link set brif1 up
    sudo ip link set brif2 up
    sudo ip link set brif3 up
    sudo ip netns exec endhost ip link set eh0 up
    sudo ip netns exec router ip link set rt0 up
    sudo ip netns exec router ip link set rt1 up
    sudo ip netns exec router ip link set rt2 up
    # disable RA acceptance on router interfaces
    sudo ip netns exec router sysctl -w net.ipv6.conf.rt0.accept_ra=0
    sudo ip netns exec router sysctl -w net.ipv6.conf.rt1.accept_ra=0
    sudo ip netns exec router sysctl -w net.ipv6.conf.rt2.accept_ra=0
    sudo ip netns exec endhost sysctl -w net.ipv6.conf.eh0.accept_ra_rtr_pref=1
    sudo ip netns exec endhost sysctl -w net.ipv6.conf.eh0.accept_ra_rt_info_max_plen=64
    sudo sysctl -w net.ipv6.conf.brpvd.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif0.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif1.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif2.accept_ra=0
    sudo sysctl -w net.ipv6.conf.brif3.accept_ra=0
}

scl_cmd_add cleanup network_reset
function network_reset {
    # it seems deleting the network namespace will as well delete the contaning devices
    # see if we can remove all the turn down intf and delete part
    sudo ip netns exec router ip link set rt0 down 2>&1 || true
    sudo ip netns exec router ip link set rt1 down 2>&1 || true
    sudo ip netns exec router ip link set rt2 down 2>&1 || true
    sudo ip netns exec endhost ip link set eh0 down 2>&1 || true
    
    sudo ip link set brif0 down 2>&1 || true
    sudo ip link set brif1 down 2>&1 || true
    sudo ip link set brif2 down 2>&1 || true
    sudo ip link set brif3 down 2>&1 || true

    sudo ip link delete brif0 2>&1 || true
    sudo ip link delete brif1 2>&1 || true
    sudo ip link delete brif2 2>&1 || true
    sudo ip link delete brif3 2>&1 || true

    sudo ip netns delete endhost 2>&1 || true
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

scl_main $@