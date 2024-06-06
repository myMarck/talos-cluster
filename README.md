# Talos cluster installation and configuration
This repository contains PowerShell scripts to install and configure a Talos cluster.
## Prerequisites

Before running the script, either use devcontainer or ensure that the following tools are installed and configured on your machine:
    Powershell: https://github.com/PowerShell/PowerShell 
    talosctl: The Talos control tool. You can install it from the official Talos documentation here.
    kubectl: The Kubernetes command-line tool. You can install it from the official Kubernetes documentation here.
    create cluster.json
    
## Order
  ./talos/generate_config.ps1
  ./talos/apply_config -controlPlaneIps 192.168.1.217 -workerIps  192.168.1.173,192.168.1.195,192.168.1.242