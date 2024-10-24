# Talos cluster installation and configuration
This repository contains PowerShell scripts to bootstrap a Talos cluster.
## Prerequisites

Before running the script, either use devcontainer or ensure that the following tools are installed and configured on your machine:
    Powershell: https://github.com/PowerShell/PowerShell 
    talosctl: The Talos control tool. You can install it from the official Talos documentation here.
    kubectl: The Kubernetes command-line tool. You can install it from the official Kubernetes documentation here.
    create cluster.json

    if devcontainer is not used the following env should be set manually
    export TALOSCONFIG="/workspaces/talos-cluster/.generated/manifests/talosconfig"
    export KUBECONFIG="/workspaces/talos-cluster/.generated/manifests/kubeconfig"

## Order
  ./talos/generate_config.ps1
  ./talos/apply_config -controlPlaneIps <dhcp_ip> -workerIps  <dhcp_ip>,<dhcp_ip>,<dhcp_ip>
  ./bootstrap/apply_config.ps1

## Reset
  ./talos/reset_cluster.ps1
