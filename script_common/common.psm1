<#
.SYNOPSIS
Validates the existence of specified commands in the system's PATH or in the script root.

.DESCRIPTION
The `Test-CommandExistence` function checks if the specified commands exist either in the system's PATH or in the script root directory. It returns `$true` if all commands are found, otherwise it returns `$false` and logs an error for each missing command.

.PARAMETER Commands
An array of command names to validate.

.EXAMPLE
PS> Test-CommandExistence -Commands @("git", "kubectl", "docker")
Checks if the commands "git", "kubectl", and "docker" exist in the system's PATH or in the script root directory.

.RETURNS
Boolean indicating whether all specified commands exist.

.NOTES
This function is useful for ensuring that required dependencies are available before executing further scripts or commands.
#>
function Test-CommandsExist {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Commands
    )

    foreach ($command in $Commands) {
        $commandPath = $command

        # Check if the command exists in the specified path
        if (-not (Test-Path -Path $commandPath)) {
            # Check if the command exists in the script root
            $commandPath = Join-Path -Path $PSScriptRoot -ChildPath $command
            if (-not (Test-Path -Path $commandPath)) {
                # Check if the command exists in the system's PATH
                if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
                    Write-Error -Message "${command} command not found."
                    return $false
                }
            }
        }
    }
    return $true
}

<#
.SYNOPSIS
Creates a Kubernetes namespace if it does not already exist.

.DESCRIPTION
The `Create-Namespace` function checks if a specified Kubernetes namespace exists. If the namespace does not exist, it creates the namespace. This function uses `kubectl` commands to interact with the Kubernetes cluster.

.PARAMETER Namespace
The name of the Kubernetes namespace to check and create if it does not exist.

.EXAMPLE
PS> New-Namespace -Namespace "my-namespace"
Checks if the "my-namespace" exists in the Kubernetes cluster. If it does not exist, the function creates it.

.NOTES
This function requires `kubectl` to be installed and configured to interact with your Kubernetes cluster.
#>
function New-Namespace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace
    )

    if (-not (Test-NamespaceExist -Namespace $Namespace)) {
        $command = "kubectl create namespace $Namespace 2>&1"
        Invoke-Expression $command
    }
}

  function Test-NamespaceExist {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Namespace
    )

    $command = "kubectl get namespace $Namespace -o jsonpath=`"{.metadata.name}`""
    $namespaceExists = Invoke-Expression $command
    return $namespaceExists

}