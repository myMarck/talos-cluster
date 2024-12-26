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

$folders = @{ 
    "generated"    = ".generated"
    "manifest"     = ".generated/manifests"
    "controlplane" = ".generated/controlplane"
    "worker"       = ".generated/worker"
    "current"      = ".current"
}

function Deploy-Config {
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
        $command = -join @("talosctl apply-config "
            "--insecure "
            "--nodes ${nodeIp} "
            "--config-patch `"@${patchFile}`" "
            "--file ${baseFile}")
        Invoke-Expression $command
    }    
}

function Join-TalosConfig {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TalosConfigFile,
        [Parameter(Mandatory = $true)]
        [String[]]$IPs,
        [Parameter(Mandatory = $true)]
        [String]$Type
    )
    $endpointArguments = $IPs -join " "
    $command = -join @("talosctl config ${type} "
        "--talosconfig ${TalosConfigFile} "
        "$endpointArguments")
    Invoke-Expression $command
}

function Test-ClusterReadyForBootstrap {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TalosConfigFile,
        [Parameter(Mandatory = $true)]
        [string]$BootstrapIP
    )

    $maxAttempts = 30
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        $attempt++
        Write-Host "Checking if cluster is ready for bootstrap. $attempt of $maxAttempts"

        try {
            $command = "talosctl"
            $arguments = @(
                "--talosconfig", $TalosConfigFile,
                "-n", $BootstrapIP,
                "service", "etcd"
            )

            # Execute the command and capture output and errors
            & $command $arguments 2>&1

            # Check the exit code of the command
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Cluster is ready for bootstrap."
                return $true
            }
        }
        catch {
            Write-Error "An error occurred: $_"
        }

        # Sleep for 2 second before the next attempt
        Start-Sleep -Seconds 2
    }

    Write-Error "Reached maximum attempts ($maxAttempts) without success."
    return $false
}

function Test-ClusterIsDone {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TalosConfigFile,
        [Parameter(Mandatory = $true)]
        [string]$BootstrapIP
    )

    $maxAttempts = 30
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        $attempt++

        try {
            # $loginResult = talosctl `
            # --talosconfig $TalosConfigFile `
            # -n $BootstrapIP `
            # health --wait-timeout 3s 2>&1
            $command = "talosctl --talosconfig $TalosConfigFile -n $BootstrapIP health --wait-timeout 3s 2>&1"
            $loginResult = Invoke-Expression $command

            # Check the exit code of the command
            if ($LASTEXITCODE -eq 0) {
                return $true
            }
            else {
                #this is needed when CNI is disabled
                if ($loginResult | Select-String -Pattern 'waiting for apid to be ready: OK' -CaseSensitive -SimpleMatch) {
                    Write-Host "Cluster is ready for CNI installation."    
                    return $true
                }
                Write-Host "Checking if cluster is done. $attempt of $maxAttempts."
            }
        }
        catch {
            Write-Error "An error occurred: $_"
        }

        # Sleep for 10 second before the next attempt
        Start-Sleep -Seconds 10
    }

    Write-Error "Reached maximum attempts ($maxAttempts) without success."
    return $false
}


function Initialize-Cluster {
    param (
        [String]$TalosConfigFile,
        [string]$BootstrapIP
    )
    Write-Host "Trying to bootstrap server with IP: ${BootstrapIP} ..."
    $command = -join @("talosctl bootstrap "
        "--talosconfig ${TalosConfigFile} "
        "-n ${BootstrapIP}")
    Invoke-Expression $command 
}

function Sync-ConfigFiles {
    param (
        [String]$TalosConfigFile,
        [String]$TalosSecretsFile,
        [String]$CurrentFolder,
        [string]$BootstrapIP
    )
    Copy-Item $TalosConfigFile -Destination ${CurrentFolder}
    Copy-Item $TalosSecretsFile -Destination ${CurrentFolder}
    $command = "talosctl -n ${BootstrapIP} kubeconfig -f"
    Invoke-Expression $command
    Write-Host "talosctl and kubectl configured."
}

function Show-Help {
    Write-Host "Usage: apply_config.ps1 [-clusterfile <path>] [--help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -clusterfile        Path to the cluster.json file (default: ./cluster.json)"
    Write-Host "  -controlPlaneIps    Comma-separated list of control plane node IPs"
    Write-Host "  -workerIps          Comma-separated list of worker node IPs"
    Write-Host "  -help -h            Show this help message"
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

    New-Folders -Folders $folders
    $bootstrapIP = $clusterData.controlplane.nodes[0].ip.Split('/')[0]
    $staticControlPlaneIPs = $clusterData.controlplane.nodes | ForEach-Object { $_.ip.Split('/')[0] }
    $controlPlaneIPs = $clusterData.controlplane.nodes | ForEach-Object { $_.reset_ip.Split('/')[0] }
    $staticWorkerIPs = $clusterData.worker.nodes | ForEach-Object { $_.ip.Split('/')[0] }
    $workerIPs = $clusterData.worker.nodes | ForEach-Object { $_.reset_ip.Split('/')[0] }
    $secretFilePath = "$($folders["generated"])/talos-secrets.yaml"
    $talosConfigFile = "$($folders["manifest"])/talosconfig"
    $controlPlaneFile = "$($folders["manifest"])/controlplane.yaml"
    $workerFile = "$($folders["manifest"])/worker.yaml"

    Deploy-Config -nodeIps $controlPlaneIps -patchFolder $folders["controlplane"] -baseFile $controlPlaneFile
    Deploy-Config -nodeIps $workerIps -patchFolder $folders["worker"] -baseFile $workerFile

    Join-TalosConfig -TalosConfigFile $talosConfigFile -IPs $staticControlPlaneIPs -Type "endpoint"
    Join-TalosConfig -TalosConfigFile $talosConfigFile -IPs $staticWorkerIPs -Type "node"

    if (Test-ClusterReadyForBootstrap -TalosConfigFile $talosConfigFile -BootstrapIP $bootstrapIP) {
        Initialize-Cluster -TalosConfigFile $talosConfigFile -BootstrapIP $bootstrapIP
    }

    if (Test-ClusterIsDone -TalosConfigFile $talosConfigFile -BootstrapIP $bootstrapIP) {
        Sync-ConfigFiles -TalosConfigFile $talosConfigFile -TalosSecretsFile $secretFilePath -CurrentFolder $folders["current"] -BootstrapIP $bootstrapIP
        Write-Host "Bootstrap successful."    
    }
}

# Execute the main function
Main
