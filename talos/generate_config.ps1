# Parse runtime parameters
param (
    [string]$clusterfile = "./cluster.json",
    [switch]$h,
    [switch]$help
)

# Load the powershell-yaml module
Import-Module powershell-yaml
Import-Module $PSScriptRoot\..\script_common\common.psm1 -Force

# Define the array of commands to validate
$commands = @( "talosctl" )

# Function to loop over an array of control plane nodes
function New-ControlPlanePatches {
    param (
        [string]$outputPath,
        [array]$controlPlaneNodes,
        [string]$vip
    )
    Write-Host "Generate ControlPlane patches."
    foreach ($node in $controlPlaneNodes) {
        $g_cp_node_file = "${outputPath}/controlplane-$($node.name).yaml"
        @(
            @{
                op    = "add"
                path  = "/machine/network/interfaces/0/addresses"
                value = @( $node.ip )
            },
            @{
                op    = "add"
                path  = "/machine/network/interfaces/0/vip"
                value = @{ "ip" = $vip }
            },
            @{
                op    = "add"
                path  = "/machine/network/hostname"
                value = $node.name
            }
        ) | ConvertTo-Yaml | Out-File -FilePath $g_cp_node_file -Force
    }
}

function New-WorkerNodePatches {
    param (
        [string]$outputPath,
        [array]$workerNodes
    )
    Write-Host "Generate WorkerNode patches."
    foreach ($node in $workerNodes) {
        $g_cp_node_file = "${outputPath}/worker-$($node.name).yaml"
        @(
            @{
                op    = "add"
                path  = "/machine/network/interfaces/0/addresses"
                value = @( $node.ip )
            },
            @{
                op    = "add"
                path  = "/machine/network/hostname"
                value = $node.name
            }
        ) | ConvertTo-Yaml | Out-File -FilePath $g_cp_node_file -Force
    }
}

function New-TalosSecret {
    param (
        [string]$secretFilePath
    )
    if (Test-Path -Path $secretFilePath -PathType Leaf) {
        Write-Host "Talos secrets already exists."
    } else {
        try {
            Write-Host "Generetae Talos secrets."
            $command = "talosctl gen secrets -o ${secretFilePath}"
            Invoke-Expression $command
        }
        catch {
            Write-Error "Failed to create secret"
            Exit 1
        }
    }
}

function New-TalosConfig {
    param (
        [string]$outputPath,
        [string]$secretFilePath,
        [string]$clusterName,
        [string]$clusterEndpoint
    )
    Write-Host "Generate Talos configurations."
    $command = -join @("talosctl gen config ${clusterName} ${clusterEndpoint} "
       "--force --output ${outputPath} "
       "--with-secrets ${secretFilePath} "
       "--config-patch @talos/patches/all.yaml "
       "--config-patch-control-plane @talos/patches/controlplane.yaml "
       "--config-patch-worker @talos/patches/worker.yaml")
    Invoke-Expression $command 2>&1 
}

# Print help message if script called with --help
function Show-Help {
    Write-Host "Usage: generate_config.ps1 [-clusterfile <path>] [--help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -clusterfile    Path to the cluster.json file (default: ./cluster.json)"
    Write-Host "  -help -h        Show this help message"
    Exit
}

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

    # Parse the cluster.json file
    try {
        $clusterData = Get-Content -Path $clusterfile | ConvertFrom-Json
    }
    catch {
        Write-Host "Error: Failed to parse JSON from '${clusterfile}'. Please ensure the file is a valid JSON."
        Exit 1
    }

    # All things are validated and good to go
    $generatedFolderPaths = @( 
        ".generated/manifests",
        ".generated/controlplane",
        ".generated/worker"
    )

    $secretFilePath = ".generated/talos-secrets.yaml"
    $controlPlaneNodes = $clusterData.controlplane.nodes
    $controlPlaneVip = $clusterData.controlplane.vip
    $workerNodes = $clusterData.worker.nodes
    $clusterName = $clusterData.clustername
    $clusterEndpoint = "https://${controlPlaneVip}:6443"

    New-Folders -folders $generatedFolderPaths
    New-ControlPlanePatches -outputPath $generatedFolderPaths[1] -controlPlaneNodes $controlPlaneNodes -vip $controlPlaneVip
    New-WorkerNodePatches -outputPath $generatedFolderPaths[2] -workerNodes $workerNodes
    New-TalosSecret -secretFilePath $secretFilePath
    New-TalosConfig -outputPath $generatedFolderPaths[0] -secretFilePath $secretFilePath -clusterName $clusterName -clusterEndpoint $clusterEndpoint
}

# Execute the main function
Main
