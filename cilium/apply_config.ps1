Import-Module $PSScriptRoot\..\script_common\common.psm1 -Force

# The version of Cilium to install
# https://github.com/cilium/cilium/releases
$cilium_chart_version = "1.17.0"

# Define the array of commands to validate
$commands = @( "helm", "cilium" )

function Install-Cilium {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    Write-Host "Installing Cilium..."
    $command = "helm install " + `
        "cilium cilium/cilium " + `
        "--version $Version " + `
        "--namespace kube-system " + `
        "--set ipam.mode=kubernetes " + `
        "--set=securityContext.capabilities.ciliumAgent=" + `
        "`"{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN," + `
        "SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}`" " + `
        "--set=securityContext.capabilities.cleanCiliumState=" + `
        "`"{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}`" " + `
        "--set=cgroup.autoMount.enabled=false " + `
        "--set=cgroup.hostRoot=/sys/fs/cgroup " + `
        "--set=kubeProxyReplacement=false " + `
#        "--set=k8sServiceHost=localhost " + `
#        "--set=k8sServicePort=7445 " + `
        "--set=cni.exclusive=false " + `
        "--set=socketLB.hostNamespaceOnly=true " + `
        "--wait" 
    Invoke-Expression $command | Out-Null
}

function Test-Cilium {
    $maxAttempts = 30
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            $command = "cilium status --wait --wait-duration=5s"
            Invoke-Expression $command | Out-Null

            # Check the exit code of the command
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Cilium is working."
                return
            } else {
                Write-Host "Checking if Cilium is done. $attempt of $maxAttempts."
            }            
        } catch {
            Write-Error "An error occurred: $_"
        }
    }
}

function Main {
    if (-not (Test-CommandsExist -Commands $commands)) { return }
    Install-Repo -RepoName "cilium" -RepoURL "https://helm.cilium.io/"
    if (Test-ResourceExist -Namespace "kube-system" -ResourceType "daemonset" -ResourceName "cilium") {
        Write-Host "Cilium is already installed"
    }
    else { 
        Install-Cilium -Version $cilium_chart_version
    }
    Test-Cilium
}

# Execute the main function
Main