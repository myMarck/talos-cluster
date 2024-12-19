# Parse runtime parameters
param (
    [string]$clusterfile = "./cluster.json",
    [switch]$h,
    [switch]$help
)

Import-Module $PSScriptRoot\..\script_common\common.psm1 -Force

# Define the array of commands to validate
$commands = @( "talosctl" )

$folders = @{ 
    "current" = ".current"
  }

# Function to extract IPs from control plane nodes and workers
function Get-ClusterIPs {
    param (
        [PSCustomObject]$clusterData
    )

    $ips = @()

    # Extract IPs from control plane nodes
    foreach ($node in $clusterData.controlplane.nodes) {
        $ips += $node.ip.Split('/')[0]
    }

    # Extract IPs from workers
    foreach ($worker in $clusterData.worker.nodes) {
        $ips += $worker.ip.Split('/')[0]
    }

    return $ips
}

function Show-Help {
    Write-Host "Usage: reset_cluster.ps1 [-clusterfile <path>] [-help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -clusterfile    Path to the cluster.json file (default: ./cluster.json)"
    Write-Host "  -help -h        Show this help message"
    Exit
}

############ Actual script starts here ############
function Main {

    if ($h -or $help) {
        Show-Help
    }

    if (-not (Test-CommandsExist -Commands $commands)) { return }

    # Verify if path is a valid file path and points to an existing file
    if (-not (Test-Path -Path $clusterfile -PathType Leaf)) {
        Write-Host "Error: The specified path '${clusterfile}' is not a valid file path or the file does not exist."
        Show-Help
    }

    $files = @(
        "$($folders["current"])/talosconfig",
        "$($folders["current"])/kubeconfig",
        "$($folders["current"])/talos-secrets.yaml"
    )
    
    # Parse the cluster.json file
    try {
        $clusterData = Get-Content -Path $clusterfile | ConvertFrom-Json
    }
    catch {
        Write-Host "Error: Failed to parse JSON from '${clusterfile}'. Please ensure the file is a valid JSON."
        Exit 1
    }

    $ips = Get-ClusterIPs -clusterData $clusterData
    $ipsString = $ips -join ","

    # Execute talosctl reset command
    $command = "talosctl --nodes ${ipsString} reset --timeout 60s --reboot --graceful=false"
    Invoke-Expression $command
    Remove-Files -Files $files
}

# Execute the main function
Main
