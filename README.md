# Multi-PvD Development Environment

This repository provides a series abstraction/automation to facilate the envrionement setting for mPvD related projects.

Following steps will create an ubuntu VM with pvd kernel patch.
Instructions are as well given on how to install on that VM other pvd related tools, especially pvdd and radvd. 

## Warmup/Revision:
If you know the answers to following questions, please do skip this section ;)

<details><summary>1. What is a PvD?</summary><p>
A provision domain is a 'consistent set of networking configuration information'. For example, source address prefix, DNS server and default gateway that can work together. See more in <a href="https://tools.ietf.org/html/rfc7556">RFC7556</a>.
</p></details>

<details><summary>2. Why there could be multiple PvDs?</summary><p>
A very concrete need for multiple PvD comes from multi-homing without provider idenpendent (PI) address. A host in such client network might receive address allocation from multiple upstreams, along with other configuration settings, just like DNS servers. 
It especially tends to happen with IPv6, for the sake of address aggregation and NAT-free networking. Some further technical discussion can be found in <a href="https://tools.ietf.org/html/draft-ietf-rtgwg-enterprise-pa-multihoming-02">draft-ietf-rtgwg-enterprise-pa-multihoming-02</a>.
</p></details>

<details><summary>3. It seems that all the configuration items within a PvD should be considered and employed interaglly by a host or application instances on a host. How to do that?</summary>
<p>First 
<a href="https://tools.ietf.org/html/draft-ietf-intarea-provisioning-domains-00">draft-ietf-intarea-provisioning-domains</a> specifies a way to configure host with multiple PvDs by introducing a new IPv6 Router Advertisment (RA) option.</p>
<p>We as well modified <a href="https://github.com/IPv6-mPvD/radvd.git">radvd</a> and <a href="https://github.com/IPv6-mPvD/odhcpd">odhcpd</a> so that they can be configured to announce RA containing PvD option.</p>
<p><a href="https://github.com/IPv6-mPvD/wireshark">Wireshark</a> is now as well made capable of parsing RA with PvD option. Debugging made esay.</p>
<p>Host side, we deliver a <a href="https://github.com/IPv6-mPvD/pvd-linux-kernel-patch">linux kernel patch</a> to make it aware of the PvD option in RA. Besides, an essential tool <a href="https://github.com/IPv6-mPvD/pvdd">pvdd</a> that organically groups configuration items of a single PvD together from various sources say RA and DHCP, is as well provided.</p>
<p>For application developpers, a PvD-aware flavor of glibc now provides interfaces with which you can easily access to PvD datas tructure and bind your applications to a set of them easily. TODO: todo add glibc repository.</p>
<p>TODO: one-liner for other projects as well.</p>
</details>

## Walk-through
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
You may see the installation progress via vnc with password pvd (The address 
is displayed by the script).
The whole thing can take a while.
Don't sit there waiting, let's start preparing a PvD-aware kernel.

### PvD-aware kernel patch
TODO: should the installation of PvD-aware glibc happen here as well?

While the VM is installing, let's download the kernel source code:
```shell
./vms/linux-env.sh kernel download
```

Once finished, let's patch the kernel source:
```shell
./vms/linux-env.sh kernel patch
```

Then, let's compile the kernel and build .deb packages needed for installation.
```shell
./vms/linux-env.sh kernel bltpkg
```
This will take quite a while. Once finished, generated linux-.*.deb sit in $your_project_directory/src/linux-env/

Now you have to wait till the VM is ready and turn it off, as we are going to install PvD-aware kernel pakages on it.
```shell
./vms/linux-env.sh kernel install
```

Once done, restart the VM, update the grub config by
```shell
sudo update-grub
```
and then restart the VM again you will be able to select the PvD-aware kernel in the grub menu.

## VM manipulation
In order to stop and start the VM, or connect using ssh, use:
```shell
./vms/linux-env.sh vm start
./vms/linux-env.sh vm ssh
./vms/linux-env.sh vm stop
```

The VNC link to see the VM desktop is always provided to you when you start the VM.

## Install pvdd
TODO

## Install Glibc
TODO

## Install radvd
TODO

## Other PvD related projects
TODO



