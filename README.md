# Talos cluster installation and configuration
This repository contains PowerShell scripts to bootstrap a Talos cluster.

## Prerequisites
Before running the script, either use devcontainer or ensure that the following tools are installed and configured on your machine:
    Powershell: https://github.com/PowerShell/PowerShell 
    talosctl: The Talos control tool. You can install it from the official Talos documentation here.
    kubectl: The Kubernetes command-line tool. You can install it from the official Kubernetes documentation here.
    argocd cli: Argo CD CLI. You can install it from here.
In the root folder create cluster.json in the following format
```
{
    "clustername": "my-cluster",
    "controlplane": {
        "vip": "192.168.0.100",
        "nodes": [
            {
                "name": "cp01.example.dk",
                "ip": "192.168.0.101/24",
                "reset_ip": "192.168.0.5"
            }
        ]
    },
    "worker": {
        "nodes": [
            {
                "name": "worker01.example.dk",
                "ip": "192.168.0.102/24",
                "reset_ip": "192.168.0.6"
            }
        ]
    }
}
```


## Order
```
  ./talos/generate_config.ps1
  ./talos/apply_config.ps1
  ./cilium/apply_config.ps1
  ./bootstrap/apply_config.ps1
```
## Reset
```
./talos/reset_cluster.ps1
```
## Upgrade talos node
talosctl -n < IP >  upgrade --preserve --image factory.talos.dev/installer/f34d250cab73557dc2e70c19713734fe4c79997ff8f13fdea3f8a830ebae2b99:v< VERSION > --force

## Missing
  * Integration with Proxmox
  * Make talos scripts idempotent.