# Multi-PvD Development Environment

This repository provides a series of abstraction/automation to facilate the envrionement setting for multi-PvD related projects.

Following steps will create an ubuntu VM with pvd kernel patch.
Instructions are as well given on how to install on that VM other pvd related tools, especially pvdd, radvd, iproute2 and wireshark. 

Table of Contents
=================

* [Multi\-PvD Development Environment](#multi-pvd-development-environment)
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
    * [Capture RA with PvD option with Wireshark](#capture-ra-with-pvd-option-with-wireshark)

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
KERNEL_LOCAL_VERSION="thierry-pvd"
```
### VM settings
As mentioned earlier, we are going to creat a VM on which the experiments are carried out. The specs of the VM can as well be customized according to your needs and constraints in [linux-env.sh](./vms/linux-env.sh). Here below the default values.
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
<!TODO: should the installation of PvD-aware glibc happen here as well?>

While the VM is installing, let's download the kernel source code:
```shell
./vms/linux-env.sh kernel download
```

Once finished, let's patch the kernel source:
```shell
./vms/linux-env.sh kernel patch
```

Then, let's compile the kernel and build .deb packages needed for kernel installation.
```shell
./vms/linux-env.sh kernel bltpkg
```
This will take quite a while. Once finished, generated linux-.*.deb shall sit in $your_project_directory/src/linux-env/

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
Once we have prepared a VM with PvD kernel patch, we can then explore how the endhost behaves in a multi-prefix IPv6 network.
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
In order to emulate the provisioning of multiple IPv6 prefixes from multiple router interfaces to an endhost within in a single VM, we can create two network namespaces.
One for the endhost and the other for the router, under the root network namespace of the VM.
The two namespaces, _endhost_ and _router_, are connected to each other via a bridge called __brpvd__ attached to the root network namespace.
The endhost and the router namespace connects to the bridge through pairs of veth interfaces.
The diagram right below illustrates the above configuration.
```
+------------------------------------------------------------------------+
|host machine                                                            |
|                                                                        |
|  +------------------------------------------------------------------+  |
|  |Ubuntu VM with PvD kernel patch                                   |  |
|  |                                                                  |  |
|  |  +------------------------------------------------------------+  |  |
|  |  |ROOT network namespace                                      |  |  |
|  |  |                                                            |  |  |
|  |  |  +------------+       +-------------+       +------------+ |  |  |
|  |  |  |endhost     |       |brpvd        |       |      router| |  |  |
|  |  |  |namespace   |       |(bridge)     |       |   namespace| |  |  |
|  |  |  |            |       |             |       |            | |  |  |
|  |  |  |         eh0+-------+brif0(veth)  |       |            | |  |  |
|  |  |  |            |       |             |       |            | |  |  |
|  |  |  |iproute2    |       |  (veth)brif1+-------+rt0         | |  |  |
|  |  |  |            |       |             |       |       radvd| |  |  |
|  |  |  |            |       |  (veth)brif2+-------+rt1         | |  |  |
|  |  |  |            |       |             |       |            | |  |  |
|  |  |  |            |       |  (veth)brif3+-------+rt2         | |  |  |
|  |  |  +------------+       +-------------+       +------------+ |  |  |
|  |  |                                                            |  |  |
|  |  +------------------------------------------------------------+  |  |
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
<!TODO: cleanup, more specifically dev delete blocked due to unable to acquire rtlink_mutex after sending RA. Note that without the PvD kernel patch, net dev can be soomthly removed after sending RA. Relative kernel bug: https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1711407>

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
Once RAs are sent, it is time to inspect whether the endhost is correctly provisioned in this multiple-prefix environment.
We provide as well some shorthands to inspect the endhost network configurations.

The following command shows the IPv6 addresses configred in endhost network namespace.
```shell
./vms/play-pvd.sh show endhost addr
```
With the RAs defined in [2pvd_1normal.conf](./ra_config/2pvd_1normal.conf), you would proabably see outputs like this:
```shell
7: eh0@if6: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2001:1::3017:eaff:fe85:7114/64 scope global mngtmpaddr dynamic 
       valid_lft 2036sec preferred_lft 1012sec pvd test-1.fr 
    inet6 2001:2::3017:eaff:fe85:7114/64 scope global mngtmpaddr dynamic 
       valid_lft 2036sec preferred_lft 1012sec pvd test-2.fr 
    inet6 2001:3::3017:eaff:fe85:7114/64 scope global mngtmpaddr dynamic 
       valid_lft 2036sec preferred_lft 1012sec 
    inet6 fe80::3017:eaff:fe85:7114/64 scope link 
       valid_lft forever preferred_lft forever 
```
We can see that the automatically configured interface addresses are now annotated with the pvd name that RA message (in which the PIO is found) associates to.

For endhosts that enable router preference, they will prefer certain router interface for traffic destined to configured prefixes. For example in [2pvd_1normal.conf](./ra_config/2pvd_1normal.conf), traffic toward 2001:1000::/40 should prefer the router interface sending out RA containing PvD test-1.fr. This preference for router interface is demonstrated in endhost routing table:
```shell
$ ./vms/play-pvd.sh show endhost route
2001:1::/64 dev eh0 proto kernel metric 256 expires 2027sec pref medium pvd test-1.fr 
2001:2::/64 dev eh0 proto kernel metric 256 expires 2027sec pref medium pvd test-2.fr 
2001:3::/64 dev eh0 proto kernel metric 256 expires 2027sec pref medium 
2001:3:3000::/40 via fe80::7477:dff:fe41:a6d2 dev eh0 proto ra metric 1024 pref high 
2001:1000::/40 via fe80::e47a:20ff:feb9:77a4 dev eh0 proto ra metric 1024 pref high pvd test-1.fr 
2001:2000::/48 via fe80::78f4:2fff:feec:d8a dev eh0 proto ra metric 1024 pref high pvd test-2.fr 
fe80::/64 dev eh0 proto kernel metric 256 pref medium 
default via fe80::7477:dff:fe41:a6d2 dev eh0 proto ra metric 1024 expires 1499sec hoplimit 64 pref medium 
default via fe80::78f4:2fff:feec:d8a dev eh0 proto ra metric 1024 expires 1499sec hoplimit 64 pref medium pvd test-2.fr 
default via fe80::e47a:20ff:feb9:77a4 dev eh0 proto ra metric 1024 expires 1499sec hoplimit 64 pref medium pvd test-1.fr 
```
We can see again that these route preferences are as well annotated with their corresponding PvD name.

### Capture RA with PvD option with Wireshark
<!TODO>

### pvdd and glibc
<!TODO>


