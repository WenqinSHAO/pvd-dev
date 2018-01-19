# Multi-PvD Development Environment

This repository provides a series of abstraction/automation to facilate the envrionement setting for multi-PvD related projects.

Following steps will create an ubuntu VM with pvd kernel patch.
Instructions are as well given on how to install on that VM other pvd related tools, especially pvdd and radvd. 

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
├── ra_config /* where config for radvd is stored */
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
├── ra_config /* where config for radvd is stored */
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
The organization of the repo can be customized according to you preference by setting variables in [linux-env.sh](./vms/linux-env.sh), which we will briefly explain below.

## Settings
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
2. test/develop applications on top of PvD-aware hosts.

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
This will take quite a while. Once finished, generated linux-.*.deb sit in $your_project_directory/src/linux-env/

Now you have to wait till the VM is ready and TURN IT OFF, as we are going to install PvD-aware kernel pakages on it.
```shell
./vms/linux-env.sh kernel install
```

Once done, restart the VM, update the VM grub config by (in the VM shell not the host shell)
```shell
sudo update-grub
```
and then restart the VM again you will be able to select the PvD-aware kernel in the grub menu.

### VM manipulation
Apart from the above designed course, we offer as well commands to facilitate some common tasks concerning the VM.
```shell
./vms/linux-env.sh vm start /* turn on the VM */
./vms/linux-env.sh vm ssh /* ssh to the VM */
./vms/linux-env.sh vm stop /* turn off the VM */
./vms/linux-env.sh vm isoboot path/to/an.iso /* boot the VM from optical driver containing the specified iso file */
./vms/linux-env.sh vm status /* prints the vnc link to the VM if it is on, otherwise nothing */
```
The boot-from-optical-driver command is pretty handy, when you screw up the grub config, and want to repair it through a boot-repair iso.

## Play with mulitple PvDs
Once we have prepared a VM with PvD kernel patch, we can then explore how the endhost behaves in a multi-prefix IPv6 network.
Please git clone this project repository as well on the VM (no longer on the host machine).
We are going to rely on [./vms/play-pvd.sh](./vms/play-pvd.sh) for the following steps.

### Repository organization and settings
After the operations in this section that happens inside the VM, we'd expect to see a repo organization as follows:
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

Very similar to the previous section, the repo settings can be altered to your preference in [./vms/play-pvd.sh](./vms/play-pvd.sh).

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
The namespaces are connected to each other via a bridge called brpvd attached to the root network namespace.
The endhost and the router namespace connects to the bridge through pairs of veth interfaces.
An illustration of the above setting can be found right below.
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

### Install radvd
radvd is a tool that announces RA. It is now made capable of parsing configurations with PvD option.
The tool can be installed with:
```shell
./vms/play-pvd.sh install radvd
```
### Install iproute2
We as well modified the iproute2 so that it shows the PvD scope for addresses and routes learnt from RA.
It can be installed with:
```shell
./vms/play-pvd.sh install iproute
```
The already avaible iproute2 installation won't be impacted.
The generated runable ip command binary can only be found in ./iproute/ip/

### Send RAs
Once the tools are installed, we can send RAs in router namespace according to a specific configuration.
Some example configurations are avaible in [./ra_config/](./ra_config/).
For example, [2pvd_1normal.conf](./ra_config/2pvd_1normal.conf) defined 3 RA messages for 3 the interfaces in router namespace.
Two RAs have two different PvD names and prefixes and one RA is without PvD option.
These configuered RA can be sent with following command:
```shell
./vms/play-pvd.sh send ra ./ra_config/2pvd_1normal.conf
```

### Inspect network settings
We provide as well a shorthand to inspect the endhost network configurations.
```shell
./vms/play-pvd.sh show endhost addr
```
With the RAs defined in [2pvd_1normal.conf](./ra_config/2pvd_1normal.conf), you would proabably see outpus like this:
```shell
7: eh0@if6: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2001:1::50b5:61ff:fe5c:b183/64 scope global mngtmpaddr dynamic 
       valid_lft 2033sec preferred_lft 1009sec pvd test-1.fr
    inet6 2001:2::50b5:61ff:fe5c:b183/64 scope global mngtmpaddr dynamic 
       valid_lft 2033sec preferred_lft 1009sec pvd test-2.fr
    inet6 2001:3::50b5:61ff:fe5c:b183/64 scope global mngtmpaddr dynamic 
       valid_lft 2033sec preferred_lft 1009sec 
    inet6 fe80::50b5:61ff:fe5c:b183/64 scope link 

```

### Capture RA with PvD option with Wireshark
<!TODO>



