$command = "kubectl create namespace argocd"
Invoke-Expression $command

$command = "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.3/manifests/install.yaml"
Invoke-Expression $command
