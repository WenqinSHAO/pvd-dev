#Multi PvD Development Environment

This repository provides an environment to help developers working on multi-PvD
related projects.

##HowTo

Start by bootstraping the environment.
```shell
./scripts/bootstrap.sh
```


### Linux Development

This environment includes some automation tool to create a VM running Ubuntu
as well as compile Ubuntu Kernel from the host, and install the compiled kernel
in the VM.

This is done by using the ./vms/linux-env.sh script.

First install the required dependencies.
```shell
./vms/linux-env.sh install dep
```

Then, create the VM (This takes a while).
You may see the installation progress using vnc (The address is displayed by the
script).
```shell
./vms/linux-env.sh vm create
```

While the VM is installing, download and compile Ubuntu-flavored linux kernel.
This also takes a while.
```shell
./vms/linux-env.sh kernel compile
```

In order to stop and start the VM, or connect using ssh, use:
```shell
./vms/linux-env.sh vm start
./vms/linux-env.sh vm ssh
./vms/linux-env.sh vm stop
```

The VNC link to see the VM desktop is always provided to you when you start the 
VM.


