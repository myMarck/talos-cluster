# Parse runtime parameters
param (
    [string]$clusterfile = "./cluster.json",
    [switch]$h,
    [switch]$help
)

# Load the powershell-yaml module
Import-Module powershell-yaml

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

# Function to loop over an array of control plane nodes
function GenerateControlPlanePatches {
    param (
        [string]$outputPath,
        [array]$controlPlaneNodes,
        [string]$vip
    )

    foreach ($node in $controlPlaneNodes) {
        $g_cp_node_file = "${outputPath}\controlplane-$($node.name).yaml"
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

function GenerateWorkerNodePatches {
    param (
        [string]$outputPath,
        [array]$workerNodes
    )
    foreach ($node in $workerNodes) {
        $g_cp_node_file = "${outputPath}\worker-$($node.name).yaml"
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

function GenerateTempFolders {
    param (
        [array]$folders
    )
    foreach ($folder in $folders) {
        if (-not (Test-Path -Path $folder)) {
            try {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
            }
            catch {
                Write-Error "Failed to create folder: ${folder}"
                Exit 1
            }
        }
    }
}

function GenerateTalosSecret {
    param (
        [string]$secretFilePath
    )
    if (-not (Test-Path -Path $secretFilePath -PathType Leaf)) {
        try {
            $command = "talosctl gen secrets -o ${secretFilePath}"
            Invoke-Expression $command
        }
        catch {
            Write-Error "Failed to create secret: ${folder}"
            Exit 1
        }
    }
}

function GenerateTalosConfig {
    param (
        [string]$outputPath,
        [string]$secretFilePath,
        [string]$clusterName,
        [string]$clusterEndpoint
    )
    $command = "talosctl gen config ${clusterName} ${clusterEndpoint} --force --output ${outputPath} --with-secrets ${secretFilePath} --config-patch @talos/patches/all.yaml --config-patch-control-plane @talos/patches/controlplane.yaml --config-patch-worker @talos/patches/worker.yaml"
    Invoke-Expression $command
}

# Print help message if script called with --help
function Show-Help {
    Write-Host "Usage: generate_config.ps1 [-clusterfile <path>] [--help]"
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

# All things are validated and good to go
$generatedFolderPaths = @( 
    ".generated/manifests",
    ".generated/controlplane",
    ".generated/worker"
    )

$secretFilePath = "secrets.yaml"
$controlPlaneNodes = $clusterData.controlplane.nodes
$controlPlaneVip = $clusterData.controlplane.vip
$workerNodes = $clusterData.worker.nodes
$clusterName = $clusterData.clustername
$clusterEndpoint = "https://${controlPlaneVip}:6443"

GenerateTempFolders -folders $generatedFolderPaths
GenerateControlPlanePatches -outputPath $generatedFolderPaths[1] -controlPlaneNodes $controlPlaneNodes -vip $controlPlaneVip
GenerateWorkerNodePatches -outputPath $generatedFolderPaths[2] -workerNodes $workerNodes
GenerateTalosSecret -secretFilePath $secretFilePath
GenerateTalosConfig -outputPath $generatedFolderPaths[0] -secretFilePath $secretFilePath -clusterName $clusterName -clusterEndpoint $clusterEndpoint
