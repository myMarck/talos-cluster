Import-Module $PSScriptRoot\..\script_common\common.psm1 -Force

# The namespace that ArgoCD will be installed in
$argocd_namespace = "argocd"

$argocd_version = "2.12.6"

# Define the array of commands to validate
$commands = @( "kubectl" )

function Test-ArgoCDInstalled {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Namespace,
        [string]$Wait_timeout = "1s"
    )
    $command = "kubectl wait --namespace $Namespace --for=condition=available --timeout=$Wait_timeout deployment/argocd-server"
    $result = Invoke-Expression $command
    if ($result -eq "deployment.apps/argocd-server condition met") {
        return $true
    } else {
        return $false
    }
}

# Main execution function
function Main {
    if (-not (Test-CommandsExist -Commands $commands)) { return }
    New-Namespace -Namespace $argocd_namespace
    if (Test-ArgoCDInstalled -Namespace $argocd_namespace -Wait_timeout "3s") {
        Write-Host "ArgoCD is already installed in the $argocd_namespace namespace."
    } else {
        #TODO: This should be updated to use the official ArgoCD Helm chart
        $command = "kubectl apply -n $argocd_namespace -f https://raw.githubusercontent.com/argoproj/argo-cd/v${argocd_version}/manifests/install.yaml"
        Invoke-Expression $command
    }
    if (Test-ArgoCDInstalled -Namespace $argocd_namespace -Wait_timeout "600s") {
        $command = "kubectl apply -n $argocd_namespace -f $PSScriptRoot/bootstrap-argocd.yaml"
        Invoke-Expression $command
        $command = "kubectl apply -n $argocd_namespace -f $PSScriptRoot/bootstrap-k8s.yaml"
        Invoke-Expression $command
    } else {
        Write-Host "ArgoCD failed to change to state available within 600s."
    }
}

# Execute the main function
Main