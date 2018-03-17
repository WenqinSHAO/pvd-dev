# Multi-PvD Development Environment

This repository provides a series of abstraction/automation to facilate the envrionement setting for multi-PvD related projects.

Following steps will create an ubuntu VM with pvd kernel patch.
Instructions are as well given on how to install on that VM other pvd related tools, especially pvdd, radvd, iproute2 and wireshark. 

Table of Contents
=================

* [Multi\-PvD Development Environment](#multi-pvd-development-environment)
* [Table of Contents](#table-of-contents)
  * [Warmup/Revision:](#warmuprevision)
  * [VM setting and kernel patching](#vm-setting-and-kernel-patching)
    * [Repository organization](#repository-organization)
    * [Repo settings](#repo-settings)
    * [VM settings](#vm-settings)
    * [Bootstraping](#bootstraping)
    * [Get the VM ready](#get-the-vm-ready)
    * [PvD\-aware kernel patch](#pvd-aware-kernel-patch)
    * [VM manipulation](#vm-manipulation)
  * [Provision multiple IPv6 prefixes using PvD option](#provision-multiple-ipv6-prefixes-using-pvd-option)
    * [Repository organization and settings](#repository-organization-and-settings)
    * [Network settings](#network-settings)
    * [Install radvd](#install-radvd)
    * [Install iproute2](#install-iproute2)
    * [Send RAs](#send-ras)
    * [Inspect network settings](#inspect-network-settings)
    * [pvdd](#pvdd)
    * [Fetching extra\-info](#fetching-extra-info)
    * [pvd\-aware glibc](#pvd-aware-glibc)
    * [pvdd and NEAT](#pvdd-and-neat)
    * [Wireshark dissector](#wireshark-dissector)
  * [The whole picture](#the-whole-picture)
## Warmup/Revision:
If you know the answers to the following questions, please do skip this section ;)

<details><summary>1. What is a PvD?</summary><p>
A provision domain is a 'consistent set of networking configuration information'. For example, source address prefix, DNS server and default gateway that can work together. See more in <a href="https://tools.ietf.org/html/rfc7556">RFC7556</a>.
</p></details>

<details><summary>2. Why there could be multiple PvDs?</summary><p>
A very concrete need for multiple PvD comes from multi-homing without provider idenpendent (PI) address. A host in such client network might receive address allocation from multiple upstreams, along with other configuration settings, just like DNS servers. 
It especially tends to happen with IPv6, for the sake of address aggregation and NAT-free networking. Some further technical discussion can be found in <a href="https://tools.ietf.org/html/draft-ietf-rtgwg-enterprise-pa-multihoming-02">draft-ietf-rtgwg-enterprise-pa-multihoming-02</a>.
</p></details>

<details><summary>3. It seems that all the configuration items within a PvD should be considered and employed interaglly by a host or application instances on a host. How to do that?</summary>
<p>First 
<a href="https://tools.ietf.org/html/draft-ietf-intarea-provisioning-domains-00">draft-ietf-intarea-provisioning-domains</a> specifies a way to provision host with multiple PvDs by introducing a new IPv6 Router Advertisment (RA) option.</p>
<p>We as well modified <a href="https://github.com/IPv6-mPvD/radvd.git">radvd</a> and <a href="https://github.com/IPv6-mPvD/odhcpd">odhcpd</a> so that they can be configured to announce RA containing PvD option.</p>
<p><a href="https://github.com/IPv6-mPvD/wireshark">Wireshark</a> is now as well made capable of parsing RA with PvD option. Debugging made esay.</p>
<p>Host side, we deliver a <a href="https://github.com/IPv6-mPvD/pvd-linux-kernel-patch">linux kernel patch</a> to make the kernel aware of the PvD option in RA. Besides, an essential tool <a href="https://github.com/IPv6-mPvD/pvdd">pvdd</a> that organically groups configuration items of a single PvD together from various sources say RA and DHCP, is as well provided.</p>
<p>For application developpers, a PvD-aware glibc now provides interfaces with which you can easily access PvD datatructures and bind your applications to a set of PvDs (so that the application uses the corresponding DNS servers , and that the kernel route the traffic appropriately). TODO: todo add glibc repository.</p>
<p>TODO: one-liner for other projects as well.</p>
</details>


## VM setting and kernel patching
### Repository organization
```
.
├── README.md
├── ra_config /* where config for radvd is stored, not relevant at this stage */
├── scripts /* where some utility functions are stored */
│   └── bootstrap.sh
└── vms
    ├── linux-env.sh /* the script for VM setup and kernek patch */
    ├── play-pvd.sh  /* the script for mPvD provisioning and inspection */
    └── preseed.cfg
```
After we've just cloned this repo, we will see directoreis and files as shown above.

After performing operations specified in this section, we expect to see a repo organized as follows:
```
.
|-- README.md
├── ra_config /* where config for radvd is stored, not relevant at this stage */
|-- run
|   `-- linux-env
|       `-- vm
|           `- disk.qcow2 /* the VM disk */
|-- scripts
|   |-- bootstrap.sh
|   `-- scriptlib
|       `-- /* utility functions */
|-- src
|   |-- linux-env
|   |   |-- linux-.*.deb /* deb packages after kernel compilation */
|   |   `-- linux-ubuntu-zesty
|           `- /* where kernel source code is stored */
|   `-- pvd-kernel-path
|       `-- /* kernel patch */
|-- tmp
|   `-- linux-env
|       `-- /* some ephemeral stuffs that we are not supposed to manipulation manually */
`-- vms
    |-- linux-env.sh /* the script for VM setup and kernek patch */
    ├── play-pvd.sh  /* the script for mPvD provisioning and inspection */
    `-- preseed.cfg
```
The organization of the repo can be customized according to you preference by setting variables in [linux-env.sh](./vms/linux-env.sh).

### Repo settings
The placement of kernel source, patch, VM disk and etc., can all be customized. They are all specified in the [linux-env.sh](./vms/linux-env.sh). Here below their default values.
```bash
# directory where this script sits
CD="$( cd "$( dirname $0 )" && pwd )" 
# the root directory of the project
ROOT="$(realpath $CD/../)"
# all things here are ephemeral
TMP="$ROOT/tmp/linux-env"
# where we put the VM disk
RUN="$ROOT/run/linux-env"
# VM disk name
VM_DRIVE=$RUN/vm/disk.qcow2
# where we put the kernel source code
KERNEL_SRC_DIR=$ROOT/src/linux-env/
# where we put the kernel patch
KERNEL_PATCH_DIR=$ROOT/src/pvd-kernel-path/
# the default kernel local version after patching
KERNEL_LOCAL_VERSION="pvd-container-conflict-replace"
```
### VM settings
As mentioned earlier, we are going to creat a VM on which the mPvD related experiments can be carried out. The specs of the VM can as well be customized according to your needs and constraints in [linux-env.sh](./vms/linux-env.sh). Here below the default values.
```bash
# VM specs, please configure according your hardware capability
VM_RAM=8G
VM_CPUS=8
VM_DRIVE_SIZE=40G
VM_TELNET_PORT=12150
VM_VNC_PORT=12250
VM_MNGMT_PORT=12350
```

### Bootstraping
Once git cloned this repository, start by bootstraping the environment.
```shell
./scripts/bootstrap.sh
```
This script will simply download some other utlity functions on top of which the following abstraction is built.

### Get the VM ready
The so called development evniroement is mainly an Ubuntu Zesty VM.
As interested developper/user, you might want to:
1. test/develop the PvD-aware linux kernel;
2. test/explore multiprefix provisioning and endhost behaviour;
3. test/develop applications on top of PvD-aware endhosts.

All these happen on the Ubuntu VM.
Prepareing such a VM can be easily done with options provided by the ./vms/linux-env.sh script.

First, let's install some necessary packages on your host machine.
```shell
./vms/linux-env.sh install dep
```

Then, let's create the VM.
```shell
./vms/linux-env.sh vm create
```
You may see the installation progress via vnc with password pvd (a vnc link will be displayed).
The whole thing can take a while.
Don't sit there waiting, let's start preparing a PvD-aware kernel.

### PvD-aware kernel patch
While the VM is installing, let's download the kernel source code:
```shell
./vms/linux-env.sh kernel download
```

Once finished, let's patch the kernel source.
<!--There are two kernel patch branches implementing two slightly different PvD parsing behaviour:
1. the default branch is _pvd-draft-01-sequential_, it implements the sequential parsing behaviour. ND6 options in PvD will be handled sequentially (as if the PvD option header were not there) along with ND6 options outside the PvD. For two RIOs toward a same destination prefixes yet with different priority, the one appears later in the RA message (not matter inside or outside PvD) will eventually be considerded by the kernel. The only expection is for RA header (when a flag set) and other ND6 options with no more than 1 presence, e.g. MTU. These settings in PvD will be eventually effective and overwrite those outside the PvD. To apply this branch: -->
```shell
./vms/linux-env.sh kernel patch
```
<!-- 2. the other branch is called _pvd-draft-01-conflict-replace_. This branch priorities all the info (RA header if present + ND6 options) in PvD. That is for RIOs toward a same destination prefix, the last one present in the PvD option counts. Therefore, it behaves equivalently as if the PvD option is the last ND6 option in sequential parsing. To apply this branch:
```shell
./vms/linux-env.sh kernel patch replace
```
-->

Then, let's compile the kernel and build .deb packages needed for kernel installation.
```shell
./vms/linux-env.sh kernel bltpkg
```
This will take quite a while.
Meantime, let's have a quick look at what does this kernel patch actually bring:
1. It first modifies the IPv6 neighbour discovery option parser behaviour, so that it can understand what happens inside a PvD option. The parsing of an RA containing PvD that contains other RA options remains sequential, just as the original kernel parsing behaviour. More specifically ND6 options in PvD will be handled sequentially (as if the PvD option header were not there) along with ND6 options outside the PvD. For example, if we have two RIOs toward a same destination prefixes yet with different priority, the one appears later in the RA message (not matter inside or outside PvD) will eventually be considerded by the kernel. The only expection is RA header (when a flag set) and other ND6 options with no more than 1 presence, e.g. MTU. These settings in PvD will be eventually effective and overwrite those outside the PvD. 
2. This PvD parsing behaviour can be easily turn on/off via option _net.ipv6.conf.<interface>.parse_pvd_ in sysctl. The default value is 1, which means on. This option is only effective when the interface accepts RA, that is _net.ipv6.conf.<interface>.accept_ra=1_.
3. When applying learnt ND6 options in RAs, the patched kernel associates prefixes, routes, etc. to the corresponding PvD.
4. New RTNETLINK messages are defined for the anouncements of PvD creation, attributes updates, etc.
5. New getsockopt/setsockopt options are defined to allow the query and modification of PvD datastructure from userspace. 
6. A process/thread/socket can be bound to a specific PvD (via setsockopt), while obliges the kernel making consistent route and saddr selection.

Once kernel building finished, generated linux-.*.deb shall sit in $your_project_directory/src/linux-env/

Now you have to wait till the VM is ready and __TURN IT OFF__, as we are going to install PvD-aware kernel pakages on it, from the host machine of the VM.
```shell
./vms/linux-env.sh kernel install
```

Once done, restart the VM, update the VM grub config by (in the VM shell not the host shell)
```shell
sudo update-grub
```
and then restart the VM again you will be able to select the PvD-aware kernel in the grub menu.

### VM manipulation
Besides the above designed course, we offer as well commands to facilitate some common VM manipulation.
```shell
./vms/linux-env.sh vm start /* turn on the VM */
./vms/linux-env.sh vm ssh /* ssh to the VM */
./vms/linux-env.sh vm stop /* turn off the VM */
./vms/linux-env.sh vm isoboot path/to/an.iso /* boot the VM from optical driver containing the specified iso file */
./vms/linux-env.sh vm status /* prints the vnc link to the VM if it is on, otherwise nothing */
```
The boot-from-optical-driver command is pretty handy, when you screw up the grub config, and want to repair it through a boot-repair iso.

## Provision multiple IPv6 prefixes using PvD option
Once we have prepared a VM with PvD kernel patch, we can then explore how the endhosts behave in a multi-prefix IPv6 network.
Please git clone this project repository as well on the VM (no longer on the host machine).
We are going to rely on [./vms/play-pvd.sh](./vms/play-pvd.sh) for the following steps.
For following steps, please selected the PvD-aware kernel in grub menu when booting the VM.

### Repository organization and settings
After the operations in this section, which happen inside the VM, we'd expect to see a repo organization as follows:
```
.
├── README.md
├── ra_config /* where config for radvd is stored */
├── radvd /* where pvd-aware radvd src is downloaded and its binary compiled */
├── iproute  /* where the pvd-aware iproute2 src is downloaded and binary its compiled */
├── scripts /* where some utility functions are stored */
│   └── bootstrap.sh
└── vms
    ├── linux-env.sh /* the script for VM setup and kernek patch */
    ├── play-pvd.sh  /* the script for mPvD provisioning and inspection */
    └── preseed.cfg

```

Very similar to the previous section, the repo settings can be altered according to your preference in [./vms/play-pvd.sh](./vms/play-pvd.sh).

It is recommended to first boostrap:
```shell
./scripts/bootstrap.sh
```
Then install the required packages before kick-off:
```shell
./vms/play-pvd.sh install dep
```

### Network settings
In order to emulate the provisioning of multiple IPv6 prefixes from multiple router interfaces to endhosts (PvD aware and unaware) within in a single VM, we can create three network namespaces: __host\_pvd__, __host\_classic__ and __router__.
The difference between __host\_pvd__ and __host\_classic__ is that the latter has net.ipv6.conf.eh1.parse_pvd set to 0.
__host\_classic__ behavious very much a like a PvD unaware endhost.
hosts and the router, are connected to each other via a bridge called __brpvd__ attached to the root network namespace.
The hosts and the router namespace connects to the bridge through pairs of veth interfaces.
The diagram right below illustrates the above configuration.
```
+------------------------------------------------------------------------+
|host machine                                                            |
|                                                                        |
|  +------------------------------------------------------------------+  |
|  |Ubuntu VM with PvD kernel patch                                   |  |
|  |                                                                  |  |
|  |    +------------+   +----------------------+                     |  |
|  |    |host_pvd net|   |ROOT network namespace|                     |  |
|  |    |namespace   |   |                      |                     |  |
|  |    |            |   |    +-------------+   |   +------------+    |  |
|  |    |            |   |    |brpvd        |   |   | router net |    |  |
|  |    |            |   |    |(bridge)     |   |   |   namespace|    |  |
|  |    |            |   |    |             |   |   |            |    |  |
|  |    |         eh0+--------+brif0(veth)  |   |   |            |    |  |
|  |    +------------+   |    |             |   |   |            |    |  |
|  |    |            |   |    |  (veth)brif2+-------+rt0         |    |  |
|  |    |         eh1+--------+brif1(veth)  |   |   |       radvd|    |  |
|  |    |            |   |    |  (veth)brif3+-------+rt1         |    |  |
|  |    |            |   |    |             |   |   |            |    |  |
|  |    |            |   |    |  (veth)brif4+-------+rt2         |    |  |
|  |    |            |   |    +-------------+   |   +------------+    |  |
|  |    |host_classic|   |                      |                     |  |
|  |    +------------+   +----------------------+                     |  |
|  |                                                                  |  |
|  +------------------------------------------------------------------+  |
|                                                                        |
+------------------------------------------------------------------------+

```

All these can be setup with:
```shell
./vms/play-pvd.sh setup
```
In order to restore the inital network setting, run:
```shell
./vms/play-pvd.sh cleanup
```
<!TODO: cleanup, more specifically netdev delete blocked due to unablility in acquiring rtlink_mutex after sending RA. Note that without the PvD kernel patch, netdev can be soomthly removed after sending RA. Relative kernel bug: https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1711407>

### Install radvd
[radvd](https://github.com/IPv6-mPvD/radvd.git) is a tool that announces RA. 
We use it to mimic a router that provisons endhosts with multiple prefixes.
Several scenarios are possible. Here we domonstrate the one with RAs containing Prefix Information Option (PIO) that allow endhost auto-configuring the interface IPv6 address.
[radvd](https://github.com/IPv6-mPvD/radvd.git) is now made capable of parsing configurations with PvD option.
It can be installed with:
```shell
./vms/play-pvd.sh install radvd
```
The radvd binary will only remain in the ./radvd/ directory.

### Install iproute2
We as well modified the [iproute2](https://github.com/IPv6-mPvD/iproute2.git) so that it understands and shows the PvD scope for addresses and routes that the endhost kernel learns from RA.
It can be installed with:
```shell
./vms/play-pvd.sh install iproute
```
The already avaible iproute2 installation won't be impacted.
The generated runable ip command binary can only be found in ./iproute/ip/

### Send RAs
Once the two tools are installed, we can send RAs in router namespace according to a specific configuration.
Some example configurations are avaible in [./ra_config/](./ra_config/).
For example, [2pvd_1normal.conf](./ra_config/2pvd_1normal.conf) defines 3 RA messages for the 3 interfaces in the _router_ namespace.
Two RAs are of two different PvD names, PIO and RIO, the remaining RA is without PvD option.
These configuered RA can be sent with the following command:
```shell
./vms/play-pvd.sh send ra ./ra_config/2pvd_1normal.conf
```

### Inspect network settings
TODO: modify the output according to the new parsing behaviour

Once RAs are sent, it is time to inspect whether the hosts are correctly provisioned in this multiple-prefix environment.
We provide _show_ option as a shorthand to inspect network configurations in certain network namespaces.
```
Usage: ./vms/play-pvd.sh show NAME_OF_NETWORK_NAMESPACE OBJECT.
NAME_OF_NETWORK_NAMESPACE := {router|host_classic|host_pvd}
OBJECT := {address|link|route}
```

For example, the following command shows the IPv6 addresses configred in __host\_pvd__ network namespace.
```shell
./vms/play-pvd.sh show host_pvd addr
```
With the RAs defined in [2pvd_1normal.conf](./ra_config/2pvd_1normal.conf), you would proabably see outputs like this:
```shell
6: eh0@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2001:db8:1:beef:f87f:b4ff:fe76:5e7/64 scope global mngtmpaddr dynamic 
       valid_lft 86283sec preferred_lft 14283sec pvd test1.example.com. 
    inet6 2001:db8:1:abcd:f87f:b4ff:fe76:5e7/64 scope global mngtmpaddr dynamic 
       valid_lft 86283sec preferred_lft 14283sec pvd test1.example.com. 
    inet6 2001:db8:1:0:f87f:b4ff:fe76:5e7/64 scope global mngtmpaddr dynamic 
       valid_lft 1910sec preferred_lft 886sec pvd test1.example.com. 
    inet6 2001:db8:2:0:f87f:b4ff:fe76:5e7/64 scope global mngtmpaddr dynamic 
       valid_lft 1910sec preferred_lft 886sec pvd test2.example.com. 
    inet6 2001:db8:3:0:f87f:b4ff:fe76:5e7/64 scope global mngtmpaddr dynamic 
       valid_lft 1910sec preferred_lft 886sec 
    inet6 fe80::f87f:b4ff:fe76:5e7/64 scope link 
       valid_lft forever preferred_lft forever 
```
We can see that the automatically configured interface addresses are now annotated with the pvd name that RA message (in which the PIO is found) associates to.

For hosts that enable as well router preference, they are aware of:
1. default router preference conveyed in RA header;
2. router preference towarded prefixes specified in RIO.
 
For example in [2pvd_1normal.conf](./ra_config/2pvd_1normal.conf), traffic toward 2001:1a00::/40 should prefer the router interface sending out RA containing PvD test1.example.com. This preference for router interface is demonstrated in __host\_pvd__ routing table:
```shell
2001:db8:1::/64 dev eh0 proto kernel metric 256 expires 1898sec pref medium pvd test1.example.com. 
2001:db8:1:abcd::/64 dev eh0 proto kernel metric 256 expires 86271sec pref medium pvd test1.example.com. 
2001:db8:1:beef::/64 dev eh0 proto kernel metric 256 expires 86271sec pref medium pvd test1.example.com. 
2001:db8:2::/64 dev eh0 proto kernel metric 256 expires 1898sec pref medium pvd test2.example.com. 
2001:db8:3::/64 dev eh0 proto kernel metric 256 expires 1898sec pref medium 
2001:db8:1000::/40 via fe80::1cdc:b4ff:feab:c7c2 dev eh0 proto ra metric 1024 pref low pvd test1.example.com. 
2001:db8:1a00::/40 via fe80::1cdc:b4ff:feab:c7c2 dev eh0 proto ra metric 1024 pref high pvd test1.example.com. 
2001:db8:2000::/48 via fe80::ac30:ffff:feb4:f502 dev eh0 proto ra metric 1024 pref high pvd test2.example.com. 
2001:db8:3000::/40 via fe80::4d0:8fff:fe61:1578 dev eh0 proto ra metric 1024 pref high 
fe80::/64 dev eh0 proto kernel metric 256 pref medium 
default via fe80::4d0:8fff:fe61:1578 dev eh0 proto ra metric 1024 expires 1371sec hoplimit 64 pref medium 
default via fe80::ac30:ffff:feb4:f502 dev eh0 proto ra metric 1024 expires 65406sec hoplimit 64 pref low pvd test2.example.com. 
default via fe80::1cdc:b4ff:feab:c7c2 dev eh0 proto ra metric 1024 expires 65406sec hoplimit 64 pref medium pvd test1.example.com. 

```
In the above routing table, we can as well notice that the defualt router preference to that sends out RAs containing pvd test2.example.com is set to low. This router preference is actually overwriten by the RA header embeded in PvD option when A-flag is set.

### pvdd
[pvdd](https://github.com/IPv6-mPvD/pvdd.git) is an userspace application that needs to be run on the host side.
```
$ sudo ip netns exec host_pvd pvdd -v
```

It is the entry-point for PvD-aware applications to learn PvD-related information.
pvdd gathers and maintains pvd related information from various sources, for example kernel, the HTTPs server for extra-info (more in the section [Fetching extra-info](#fetching-extra-info)).
It learns about PvD from kernel via subscribing to rtnetlink updates.
Meantime, it listens to and receives messages on tcp 10101 of localhost (default port can be changed) and reactes to these commands.
For example, in order to query all the available PvDs on a host, we can do:
```shell
$ echo PVD_GET_LIST | sudo ip netns exec host_pvd nc -N 127.0.0.1 10101
PVD_LIST fe80:0000:0000:0000:704b:7dff:fe02:c762%eh0 test2.example.com. test1.example.com.
```
For the complete list of messages and operations supported by pvdd, we invite you to have a look at look at the [pvdd](https://github.com/IPv6-mPvD/pvdd.git) README.

In order to faciliate the dev of PvD-aware application, pvdd project as well provides a shared library (libpvd.so in pvdd/src/obj/ after make), which wraps the above TCP messaging mechnism into synchronous and asynchronous function calls. For a complete list of avaiable functions, please have a look at [libpvd.h](https://github.com/IPv6-mPvD/pvdd/blob/master/include/libpvd.h). 
The pvdd/tests/ folder provides examples on how to use these functions.

Apart from the above exchanges with pvdd, libpvd.so as well wraps the getsockopt/setsockopt calls towards the kernel. 
With these functions, a socket/thread/process can be bound to a specified PvD.

### Fetching extra-info
According to the [draft](https://github.com/IPv6-mPvD/mpvd-ietf-drafts/blob/master/draft-ietf-intarea-provisioning-domains.txt) on provisioning multiple PvDs, when the H-flag of the PvD ID Option is set, hosts MAY attempt to retrieve the additional attributes associated with a given PvD
by performing an HTTP over TLS GET query to https://<PvD-ID>/.well-known/pvd-id 

This task is NOT directly perfomed by pvdd. A supplementary tool called [pvd-monitor](https://github.com/IPv6-mPvD/pvdd/tree/master/utils) is offered in the pvdd project for this task.
pvd-monitor subscribtes to PvD notifications from pvdd. 
Once a PvD with H-flag set is observered, it performs HTTPS queries to fetch the additional attributes.
Finally, it updates the pvdd with the retrived extra-info.
With pvd-monitor, pvdd is eventually populated with all the information concerning a PvD, and thus is capable of serving as the only entry point for applications to learn about PvDs.

### pvd-aware glibc 
Provisioning hosts with multiple PvDs obliges as well that hosts perform name resolution with consistent provisioning information, i.e. send out the query towards the name server, using the source address and routes learnt within a same PvD.

The consistent usage of source address and route is implemented by the kernel patch.
As for the selection of name server, we bring forth a patch for [glibc](https://github.com/IPv6-mPvD/glibc).

With this patch, up on a getaddrinfo call from an application, glibc will
1. find out to which PvD the socket/thread/process is bound to through the getsockopt call wraped by libpvd.so/libpvd.h;
2. then it connects to pvdd to retrivel the list of rdnss attached to this PvD;
3. finally glibc makes name queries to the servers and reley the responds to the application.

In the tests folder of our [glibc](https://github.com/IPv6-mPvD/glibc) repo, we provide as well multiple examples to showcase the name resolutin under PvD binding.

### pvdd and NEAT
[NEAT](https://www.neat-project.org) offers to applications a rich description on the network services, such as pricing, instant performance, etc, in the purpose of encoraging innovations across protocol stacks.

In multi-homed IPv6 networks provisioned with PvDs in RA, an important source of network service infromation is thus pvdd that is presented here above.
In order to wire NEAT and pvdd together, [a http server](https://github.com/IPv6-mPvD/pvd-demo/blob/master/pvd-html-client/pvdHttpServer.js) is put in place to expose a series of REST APIs and a web page for the query of PvDs and their attributes.

PvD-unaware but NEAT enabled hosts can thus talk to the above http server that is setup on a PvD-aware host to learn the full set of information conveyed in RA, along with other valude-added metrics.

### Wireshark dissector 
Last but not least, [Wireshark](https://github.com/IPv6-mPvD/wireshark.git) is as well made capable of parsing RA's containing PvD options.

## The whole picture
```
+------------------------------------------------------------------------------------------+
|A PvD-aware Linux host                                                                    |
|                                                                                          |
|                                                                                          |
|      +-----------------------------------------------------+                             |
|      |                         APP                         |                             |
|      +----------------+------------------------------------+                             |
|  pvd binding          |        learn PvDs          |learn PvDs and other stuff           |
|         |             |            |       +---------------+                             |
|         |             |            |       |     NEAT      |                             |
|         |        name resolv       |       +-------+-------+                             |
|         |             |            |               |                                     |          +-----------------------------+
|         |       +-----+-------+    |       +-------+-------+                             |          | A non-PvD aware host        |
|         |       |    glibc    |    |       | PvdHttpServer +----------------------------------------+ NEAT                        |
|         |       +--+-------+--+    |       +-------+-------+                             |          +-----------------------------+
|         |          |       |       |               |                                     |
|         |          |    +--+-------+---------------+-------+       +----------------+    |          +-----------------------------+
|         |          |    |               pvdd               +-------+   pvd|monitor  +---------------+ pvd additional info server  |
|         |          |    +-----------------+----------------+       +----------------+    |          | (capti^e portal, perf, etc) |
|         |          |                      |                                              |          +-----------------------------+
+------------------------------------------------------------------------------------------+
|         +          +                      +                                              |
|                                                                                          |
|                                          kernel                                          |
|                                                                                          |
+--------------------------------------------+---------------------------------------------+
                                             |
                                             |
                                             |                         +--------------+
                                             |RA with PvD+-------------+  wireshark   |
                                             |                         +--------------+
                                             |
                                    +--------+---------+
                                    |   radvd/odhcpd   |
                                    +------------------+
```




