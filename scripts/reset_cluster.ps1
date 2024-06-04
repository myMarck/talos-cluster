# Parse runtime parameters
param (
    [string]$clusterfile = "./cluster.json",
    [switch]$h,
    [switch]$help
)

# Function to validate an array of commands
function ValidateCommands {
    param (
        [string[]]$commands
    )

    foreach ($command in $commands) {
        $commandPath = $command

        # Check if the command exists in the specified path
        if (-not (Test-Path $commandPath)) {
            # Check if the command exists in the script root
            $commandPath = Join-Path $PSScriptRoot $command
            if (-not (Test-Path $commandPath)) {
                # Check if the command exists in the system's PATH
                if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
                    Write-Error "${command} command not found."
                    return $false
                }
            }
        }
    }
    return $true
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
    foreach ($worker in $clusterData.workers.nodes) {
        $ips += $worker.ip.Split('/')[0]
    }

    return $ips
}

# Function to delete files if they exist
function Remove-ConfigFiles {
    param (
        [array]$filePaths
    )

    foreach ($filePath in $filePaths) {
        if (Test-Path -Path $filePath) {
            try {
                Remove-Item -Path $filePath -Force
                Write-Host "Deleted file: $filePath"
            } catch {
                Write-Host "Failed to delete file: $filePath"
            }
        } else {
            Write-Host "File does not exist: $filePath"
        }
    }
}

function Show-Help {
    Write-Host "Usage: reset_cluster.ps1 [-clusterfile <path>] [-help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -clusterfile       Path to the cluster.json file (default: ./cluster.json)"
    Write-Host "  -help -h           Show this help message"
    Exit
}

############ Actual script starts here ############

if ($h -or $help) {
    Show-Help
}

# Verify if path is a valid file path and points to an existing file
if (-not (Test-Path -Path $clusterfile -PathType Leaf)) {
    Write-Host "Error: The specified path '${clusterfile}' is not a valid file path or the file does not exist."
    Show-Help
}

# Parse the cluster.json file
try {
    $clusterData = Get-Content -Path $clusterfile | ConvertFrom-Json
}
catch {
    Write-Host "Error: Failed to parse JSON from '${clusterfile}'. Please ensure the file is a valid JSON."
    Exit 1
}

# Define the array of commands to validate
$commands = @( "talosctl" )

# Validate the commands
if (-not (ValidateCommands $commands)) {
    return
}

$configFilePaths = @(
    $(Join-Path $HOME ".talos\config"),
    $(Join-Path $HOME ".kube\config")
)
$ips = Get-ClusterIPs -clusterData $clusterData
$ipsString = $ips -join ","

# Execute talosctl reset command
$command = "talosctl --talosconfig $($configFilePaths[0]) --nodes $ipsString reset --timeout 60s --reboot --graceful=false"
Write-Host $command
Invoke-Expression $command

Remove-ConfigFiles -filePaths $configFilePaths