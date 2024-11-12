# Parse runtime parameters
param (
    [string]$clusterfile = "./cluster.json",
    [parameter(mandatory = $true)][String[]]$controlPlaneIps,
    [parameter(mandatory = $true)][String[]]$workerIps,
    [switch]$h,
    [switch]$help
)

# Load the powershell-yaml module
Import-Module powershell-yaml
Import-Module $PSScriptRoot\..\script_common\common.psm1 -Force

# Define the array of commands to validate
$commands = @( "talosctl" )

$generatedFolderPaths = @( 
    ".generated/manifests",
    ".generated/controlplane",
    ".generated/worker"
)

function ApplyConfig {
    param (
        [String[]]$nodeIps,
        [String]$patchFolder,
        [String]$baseFile
    )
    $counter = 0
    Get-ChildItem $patchFolder -Filter *.yaml | 
    Foreach-Object {
        $patchFile = $_.FullName
        $nodeIp = $nodeIps[$counter++]
        $command = "talosctl apply-config --insecure --nodes ${nodeIp} --config-patch `"@${patchFile}`" --file ${baseFile}"
        Invoke-Expression $command 
    }    
}

function UpdateTalosConfig {
    param (
        [String]$talosConfigPath,
        [String[]]$IPs,
        [String]$type
    )
    $endpointArguments = $IPs -join " "
    $command = "talosctl --talosconfig ${talosConfigPath} config ${type} $endpointArguments"
    Invoke-Expression $command 
}

function BootstrapCluster {
    param (
        [string]$bootstrapIP
    )
    Write-Host "Waiting 75 secs for the nodes to come back online before trying to bootstrap cluster..."
    Start-Sleep -Seconds 75
    
    #Attempt to bootstrap until successful
    do {
        Start-Sleep -Seconds 3
        Write-Host "Trying to bootstrap server with IP: ${bootstrapIP} ..."
        $command = "talosctl bootstrap --nodes ${bootstrapIP}"
        Invoke-Expression $command 
    } while ($LASTEXITCODE -ne 0)
    
    Write-Host "Bootstrap successful."    

    $command = "talosctl -n ${bootstrapIP} kubeconfig"
    Invoke-Expression $command
    Write-Host "kubectl configured."            
}

function Show-Help {
    Write-Host "Usage: apply_config.ps1 [-clusterfile <path>] [--help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -clusterfile       Path to the cluster.json file (default: ./cluster.json)"
    Write-Host "  -controlPlaneIps   Comma-separated list of control plane node IPs"
    Write-Host "  -workerIps         Comma-separated list of worker node IPs"
    Write-Host "  -help -h           Show this help message"
    Exit
}

# Main execution function
function Main {
    if ($h -or $help) {
        Show-Help
    }

    if (-not (Test-CommandsExist -Commands $commands)) { return }
    
    # Parse the cluster.json file
    try {
        $clusterData = Get-Content -Path $clusterfile | ConvertFrom-Json
    }
    catch {
        Write-Host "Error: Failed to parse JSON from '${clusterfile}'. Please ensure the file is a valid JSON."
        Exit 1
    }

    $bootstrapIP = $clusterData.controlplane.nodes[0].ip.Split('/')[0]
    $staticControlPlaneIPs = $clusterData.controlplane.nodes | ForEach-Object { $_.ip.Split('/')[0] }
    $staticWorkerIPs = $clusterData.worker.nodes | ForEach-Object { $_.ip.Split('/')[0] }
    $talosConfigPath = "$($generatedFolderPaths[0])/talosconfig"
    $controlPlaneFile = "$($generatedFolderPaths[0])/controlplane.yaml"
    $workerFile = "$($generatedFolderPaths[0])/worker.yaml"

    ApplyConfig -nodeIps $controlPlaneIps -patchFolder $generatedFolderPaths[1] -baseFile $controlPlaneFile
    ApplyConfig -nodeIps $workerIps -patchFolder $generatedFolderPaths[2] -baseFile $workerFile

    UpdateTalosConfig -talosConfigPath $talosConfigPath -IPs $staticControlPlaneIPs -type "endpoint"
    UpdateTalosConfig -talosConfigPath $talosConfigPath -IPs $staticWorkerIPs -type "nodes"

    BootstrapCluster -bootstrapIP $bootstrapIP
}

# Execute the main function
Main
