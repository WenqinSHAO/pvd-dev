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
#mkdir -p $DIR_IPROUTE
#mkdir -p $DIR_RADVD

LINK_IPROUTE=https://github.com/IPv6-mPvD/iproute2.git
LINK_RADVD=https://github.com/IPv6-mPvD/radvd.git

scl_cmd_add install dep install_dep
function install_dep {
	# this function installs the necessary packages
	sudo apt-get install net-tools
}

scl_cmd_add install radvd install_radvd
function install_radvd {
    echo "todo"
}

scl_cmd_add install iproute install_iproute
function install_iproute {
    echo "todo"
}

scl_cmd_add setup network_setup
function network_setup {
    # separate router and endhost in two network namespaces
    echo "Add network namespaces."
    sudo ip netns add endhost
    sudo ip netns add router
    # first creat the bridge between the endhost and the router
    echo "Create network devices."
    sudo brctl addbr brpvd
    # veth pair between endhost and the bridge
    sudo ip link add eh0 type veth peer name brif0
    # 1st veth pair between router and the bridge
    sudo ip link add rt0 type veth peer name brif1
    # 2nd veth pair between router and the bridge
    sudo ip link add rt1 type veth peer name brif2
    # add brif* to the bridge
    sudo brctl addif brpvd brif0
    sudo brctl addif brpvd brif1
    sudo brctl addif brpvd brif2
    # add the other side the veth pair to corresponding network namespaces
    sudo ip link set eh0 netns endhost
    sudo ip link set rt0 netns router
    sudo ip link set rt1 netns router
    # turn up the devices
    sudo ip link set brpvd up
    sudo ip link set brif0 up
    sudo ip link set brif1 up
    sudo ip link set brif2 up 
    sudo ip netns exec endhost ip link set eh0 up
    sudo ip netns exec router ip link set rt0 up
    sudo ip netns exec router ip link set rt1 up
    # disable RA acceptance on router interfaces
    sudo ip netns exec router sysctl -w net.ipv6.conf.rt0.accept_ra=0
    sudo ip netns exec router sysctl -w net.ipv6.conf.rt1.accept_ra=0
}

scl_cmd_add cleanup network_reset
function network_reset {
    echo "to do"
}

scl_main $@