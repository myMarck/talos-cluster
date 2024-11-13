Import-Module $PSScriptRoot\..\script_common\common.psm1 -Force

# The namespace that ArgoCD will be installed in
$argocd_namespace = "argocd"

# The version of ArgoCD to install
$argocd_chart_version = "7.7.2"

# Define the array of commands to validate
$commands = @( "kubectl", "helm", "argocd", "openssl" )

function Install-ArgoCD {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    Write-Host "Installing ArgoCD..."
    $command = "helm install argocd argo/argo-cd -n $Namespace --create-namespace --version $Version --wait"
    Invoke-Expression $command
}
function Get-ArgoCDAdminPassword {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Namespace
    )
    $command = "kubectl get secret argocd-initial-admin-secret -n $Namespace -o jsonpath=`"{.data.password}`" 2>&1"
    $passwordBase64 = Invoke-Expression $command
    if ($LASTEXITCODE -eq 0) {
        # Decode the base64-encoded password
        $passwordBytes = [System.Convert]::FromBase64String($passwordBase64)
        $password = [System.Text.Encoding]::UTF8.GetString($passwordBytes)
        return $password
    }

    # This is default password if installed via old helm charts
    $command = "kubectl get pods -n $Namespace -l app.kubernetes.io/name=argocd-server -o name"
    $result = Invoke-Expression $command
    # Output format: pod/argocd-server-xxxxxxxxx-xxxxx
    return $result.Trim().Split('/')[1]
}

function Connect-ArgoCD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$AdminPassword
    )
    try {
        $loginResult = argocd login port-forward `
            --port-forward-namespace $Namespace `
            --port-forward `
            --username admin `
            --password $AdminPassword `
            --insecure  2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to log in to ArgoCD. Error: $loginResult"
            return
        }
        Write-Host "Logged in to ArgoCD successfully."
    }
    catch {
        Write-Error "Exception occurred while logging in to ArgoCD: $_"
        return
    }
}

function Disconnect-ArgoCD {
    try {
        $logoutResult = argocd logout port-forward `
            --port-forward-namespace argocd `
            --port-forward `
            2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to log out of ArgoCD. Error: $logoutResult"
            return
        }
        Write-Host "Logged out of ArgoCD successfully."
    }
    catch {
        Write-Error "Exception occurred while logging out of ArgoCD: $_"
        return
    }
}
function New-Project {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectFile
    )
    try {
        $repoResult = argocd proj create `
            --file $ProjectFile `
            --port-forward-namespace argocd `
            --port-forward `
            2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create Project. Error: $repoResult"
            return
        }
        Write-Host "Added ArgoCD Project from: $ProjectFile."
    }
    catch {
        Write-Error "Exception occurred while logging in to ArgoCD: $_"
        return
    }
}
function New-Application {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ApplicationFile
    )
    try {
        $appResult = argocd app create `
            --file $ApplicationFile `
            --port-forward-namespace argocd `
            --port-forward `
            2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create Application. Error: $appResult"
            return
        }
        Write-Host "Added ArgoCD Application from: $ApplicationFile."
    }
    catch {
        Write-Error "Exception occurred while logging in to ArgoCD: $_"
        return
    }
}

function New-SealedSecret {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [Parameter(Mandatory = $true)]
        [string]$SecretName,
        [string]$PrivateKey = "sealed-secret.key",
        [string]$Certificate = "sealed-secret.crt"
    )

    if (-not (Test-Path -Path $PrivateKey -PathType Leaf)) {
        try {
            $command = "openssl req -x509 -days 365 -nodes -newkey rsa:4096 -keyout ${PrivateKey} -out ${Certificate} -subj `"/CN=sealed-secret/O=sealed-secret`""
            Invoke-Expression $command
        }
        catch {
            Write-Error "Failed to create sealed secret"
            Exit 1
        }
    }
    if ( Test-SecretExist -Namespace $Namespace -SecretName $SecretName ) {
        Write-Host "Secret $SecretName already exists in namespace $Namespace"
        return
    }
    $command = "kubectl -n $Namespace create secret tls $SecretName --cert=${Certificate} --key=${PrivateKey}"
    Invoke-Expression $command
    $command = "kubectl -n $Namespace label secret $SecretName sealedsecrets.bitnami.com/sealed-secrets-key=active"
    Invoke-Expression $command
}

# Main execution function
function Main {
    if (-not (Test-CommandsExist -Commands $commands)) { return }
    Install-Repo -RepoName "argo" -RepoURL "https://argoproj.github.io/argo-helm"
    if (-not (Test-ResourceExist -Namespace $argocd_namespace -ResourceType "deployment" -ResourceName "argocd-server")) {
        Install-ArgoCD -Namespace $argocd_namespace -Version $argocd_chart_version
    }
    $password = Get-ArgoCDAdminPassword -Namespace $argocd_namespace
    Write-Host "ArgoCD is installed and available in the $argocd_namespace namespace with password $password"
    New-SealedSecret -Namespace $argocd_namespace -SecretName "sealed-secret"
    Connect-ArgoCD -Namespace $argocd_namespace -AdminPassword $password
    if (Test-ResourceExist -Namespace $argocd_namespace -ResourceType "appproject" -ResourceName "bootstrap") {
        Write-Host "ArgoCD Project 'bootstrap' already exists."
    } else {
        New-Project -ProjectFile "$PSScriptRoot/bootstrap-app-project.yaml"
    }
    if (Test-ResourceExist -Namespace $argocd_namespace -ResourceType "application" -ResourceName "bootstrap") {
        Write-Host "ArgoCD Application 'bootstrap' already exists."
    } else {
        New-Application -ApplicationFile "$PSScriptRoot/bootstrap-application.yaml"
    }
    Disconnect-ArgoCD
}

# Execute the main function
Main
