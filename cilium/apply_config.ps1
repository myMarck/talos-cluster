Import-Module $PSScriptRoot\..\script_common\common.psm1 -Force

# The version of Cilium to install
$cilium_chart_version = "1.16.3"

# Define the array of commands to validate
$commands = @( "helm" )

function Install-Cilium {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $command = "helm install " + `
        "cilium cilium/cilium " + `
        "--version $Version " + `
        "--namespace kube-system " + `
        "--set ipam.mode=kubernetes " + `
        "--set=kubeProxyReplacement=true " + `
        "--set=securityContext.capabilities.ciliumAgent=" + `
        "`"{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN," + `
        "SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}`" " + `
        "--set=securityContext.capabilities.cleanCiliumState=" + `
        "`"{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}`" " + `
        "--set=cgroup.autoMount.enabled=false " + `
        "--set=cgroup.hostRoot=/sys/fs/cgroup " + `
        "--set=k8sServiceHost=localhost " + `
        "--set=k8sServicePort=7445"
    Invoke-Expression $command
}

function Main {
    if (-not (Test-CommandsExist -Commands $commands)) { return }
    Install-Repo -RepoName "cilium" -RepoURL "https://helm.cilium.io/"
    Install-Cilium -Version $cilium_chart_version
}

# Execute the main function
Main