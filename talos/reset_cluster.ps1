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

    $staticWorkerIPs = $clusterData.worker.nodes | ForEach-Object { $_.ip.Split('/')[0] }
    $staticControlPlaneIPs = $clusterData.controlplane.nodes | ForEach-Object { $_.ip.Split('/')[0] }

    $workerIPs = $staticWorkerIPs -join ","
    $controlPlaneIPs = $staticControlPlaneIPs -join ","

    # Execute talosctl reset command
    $command = "talosctl --nodes ${workerIPs} reset --timeout 60s --reboot --graceful=false --debug --system-labels-to-wipe /dev/sdb-1 --user-disks-to-wipe /dev/sdc,/dev/sdd"
    Invoke-Expression $command

    $command = "talosctl --nodes ${controlPlaneIPs} reset --timeout 60s --reboot --graceful=false --debug"
    Invoke-Expression $command

    Remove-Files -Files $files
}

# Execute the main function
Main
