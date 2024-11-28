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

function Remove-Folders {
    param (
        [array]$Folders
    )
    foreach ($folder in $Folders) {
        if (Test-Path -Path $folder) {
            try {
                Remove-Item -Path $folder -Force -Recurse | Out-Null
            }
            catch {
                Write-Error "Failed to delete folder: ${folder}"
                Exit 1
            }
        }
    }
}
function New-Folders {
    param (
        [array]$Folders
    )
    foreach ($folder in $Folders) {
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

function Test-ResourceExist {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,
        [Parameter(Mandatory = $true)]
        [string]$ResourceName
    )

    try {
        # Execute kubectl command to check for the resource
        $result = kubectl get $ResourceType $ResourceName -n $Namespace --ignore-not-found -o jsonpath="{.metadata.name}" 2>&1

        # Check for errors
        if ($LASTEXITCODE -ne 0) {
            Write-Error "An error occurred while checking for $ResourceType '$ResourceName' in namespace '$Namespace'. Error: $result"
            return $false
        }

        # Determine if the resource exists
        if ($result -eq $ResourceName) {
            return $true
        } else {
            return $false
        }
    } catch {
        Write-Error "Exception occurred: $_"
        return $false
    }
}

function Test-SecretExist {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$SecretName
    )

    try {
        # Execute kubectl command to check for the secret
        $secret = kubectl get secret $SecretName -n $Namespace --ignore-not-found -o jsonpath="{.metadata.name}" 2>&1

        # Check for errors
        if ($LASTEXITCODE -ne 0) {
            Write-Error "An error occurred while checking for secret '$SecretName' in namespace '$Namespace'. Error: $secret"
            return $false
        }

        # Determine if the secret exists
        if ($secret -eq $SecretName) {
            return $true
        } else {
            return $false
        }
    } catch {
        Write-Error "Exception occurred: $_"
        return $false
    }
}

function Install-Repo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        [Parameter(Mandatory = $true)]
        [string]$RepoURL
    )
    $command = "helm repo add $RepoName $RepoURL"
    Invoke-Expression $command | out-null
    $command = "helm repo update"
    Invoke-Expression $command | out-null
}