# Overview

GitOps driven homelab using ArgoCD

Forked from: https://github.com/acelinkio/argocd-homelab

# Prerequisites

- 1Password
- Cloudflare managed domain
- At least 1 private static ip
- Kubernetes cluster
- helm
- kubectl

# Project Structure

```
.
├── .github/                   # Github workflow & integration settings
│   └── renovate.json5         # RenovateBot configuration
├── .vscode/                   # Visual Studio Code editor configurations
│   ├── extensions.json        # Extension recomendations
│   └── settings.json          # Editor configuration
├── bootstrap/                 # Initialization related resources
│   ├── argocd-config.yaml     # ArgoCD Custom Resources for deployment
│   └── argocd-values.yaml     # Values file used for Helm Release
├── manifest/                  # Directory ArgoCD ApplicationSet watches
│   └── <namespace>.yaml       # App of Apps manifests for used for each namespace
├── .gitignore                 # Ignored files list
└── README.md                  # This file
```

# 1Password Layout

```
homelab                        # vault used for containing secrets
├── stringreplacesecret        # secret used for basic string replacement by ArgoCD Vault Plugin
└── <namespace>                # secret dedicated for each namespace
```

# Getting Started

## Fork this repository (Recomended)

- Update `bootstrap/argocd-config.yaml` to point to your forked respository.

## 1Password Credentials

- Create vault named `homelab`
- Follow https://developer.1password.com/docs/connect/get-started/#step-1-set-up-a-secrets-automation-workflow _1Password.com_ tab for generating `1password-credentials.json` and save into bootstrap directory.
- Follow https://developer.1password.com/docs/connect/get-started/#step-1-set-up-a-secrets-automation-workflow _1Password CLI_ tab for generating a 1password connect token and save as `1password-token.secret` in bootstrap directory.

## Various Credentials

### external-dns
- In the homelab vault, create a password type secret named `external-dns`
- Save the url to the external Pi-hole server into a key named `pihole-url`.
- Save the password to the external Pi-hole server into a key named `pihole-password`.

### cert-manager
- In the homelab vault, create a password type secret named `cert-manager`
- Follow https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/#api-tokens for generating a token and save into key named `cf-api-token`
- Use https://app.zerossl.com/developer to generate EAB credentials.
  - Save the 'EAB KID' to a key named `eab-kid`.
  - Save the 'EAB HMAC Key' to a key named `eab-hmac-key`.

## String Replacement
- In the homelab vault, create a password type secret named `stringreplacesecret`
- Save your domain mydomain.com into a key named `domain`. 
- Save your static ip address range for MetalLB 192.168.1.x-192.168.1.x into a key named `metallbpooladdress`. 

# Setup

```
# Prepare secrets
kubectl create namespace 1passwordconnect
kubectl create secret generic 1passwordconnect --from-literal 1password-credentials.json=$(cat bootstrap/1password-credentials.json | base64 -w 0 ) -n 1passwordconnect

kubectl create namespace external-secrets
kubectl create secret generic 1passwordconnect --from-file=token=bootstrap/1password-token.secret -n external-secrets

kubectl create namespace argocd
kubectl create secret generic stringreplacesecret -n argocd --from-literal domain=<VALUE-FROM-VAULT> --from-literal metallbpooladdress=<VALUE-FROM-VAULT>

# Install ArgoCD
helm template --repo https://argoproj.github.io/argo-helm --version 5.43.3 --namespace argocd argocd argo-cd --values bootstrap/argocd-values.yaml | kubectl apply -f -

# Configure ArgoCD
kubectl apply -f bootstrap/argocd-config.yaml
```

# FAQ

- What is are these objects enclosed in <>?

  That is the format for using ArgoCD Vault Plugin. https://argocd-vault-plugin.readthedocs.io/en/stable/howitworks/#inline-path-placeholders Example: `<path:vaults/homelab/items/stringreplacesecret#domain>`

- Why use argo-vault-plugin and external-secrets?

  Argo-Vault-Plugin provides a quick way to do do basic string replacements. This is useful when prototyping and as many resources cannot quickly consume values from kubernetes secrets or configmaps.
