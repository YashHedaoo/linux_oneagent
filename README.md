# Install Dynatrace OneAgent on Linux (Terraform + GitHub Actions)

Installs the [Dynatrace OneAgent](https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent/installation-and-operation/linux/installation/install-oneagent-on-linux)
on **existing** Linux hosts over SSH, driven by Terraform and CI'd with GitHub Actions.

## How it works

```
GitHub push/PR ─▶ GitHub Actions (deploy.yml)
                     │  injects secrets as TF_VAR_* env vars
                     ▼
                terraform init → validate → plan → apply
                     │
                     ▼
        null_resource.oneagent  (one per host, over SSH)
             1. file provisioner  → uploads scripts/install_oneagent.sh
             2. remote-exec       → runs it as root with the DT_* env vars
                     │
                     ▼
        Host: curl installer (PaaS token) → verify signature → run installer
                     │
                     ▼
        OneAgent registers with your Dynatrace tenant and starts sending data
```

Terraform doesn't install software itself — it orchestrates an SSH session and
runs the official installer on each host. The installer is downloaded **on the
host** from your tenant's deployment API using a PaaS token.

## Files

| File | Purpose |
|------|---------|
| `versions.tf` | Terraform + provider versions, optional remote backend |
| `variables.tf` | Inputs (tenant URL, tokens, hosts, SSH, installer flags) |
| `main.tf` | `null_resource` that SSHes to each host and installs |
| `outputs.tf` | Installed hosts + tenant URL |
| `scripts/install_oneagent.sh` | Download + verify + run the installer (idempotent) |
| `.github/workflows/deploy.yml` | CI pipeline |
| `terraform.tfvars.example` | Template for local runs |

## Prerequisites

1. **Dynatrace tenant URL** — e.g. `https://abc12345.live.dynatrace.com`.
2. **PaaS token** — Dynatrace → *Access Tokens / Platform tokens* → generate a PaaS token (used to download the installer).
3. **SSH access** — a private key whose user can `sudo` **without a password prompt** on the target hosts.
4. **Network path** — whatever runs Terraform (your laptop or the GitHub runner) must be able to reach the hosts on the SSH port. GitHub-hosted runners are on the public internet; for private hosts use a self-hosted runner or a bastion/VPN.

## Run it locally

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit it
terraform init
terraform plan
terraform apply
```

## Run it in GitHub Actions

Add these repository secrets (**Settings → Secrets and variables → Actions**):

| Secret | Example |
|--------|---------|
| `DT_ENVIRONMENT_URL` | `https://abc12345.live.dynatrace.com` |
| `DT_PAAS_TOKEN` | `dt0c01.XXXX.YYYY` |
| `SSH_USER` | `ubuntu` |
| `SSH_PRIVATE_KEY` | full PEM contents of the private key |
| `TARGET_HOSTS` | `["10.0.0.10","10.0.0.11"]` (JSON array string) |

Push to `main` (or run the workflow manually) → it plans on PRs and applies on `main`.

## Notes

- **State contains secrets.** Terraform state records variable values. Use a remote
  backend with encryption (uncomment the `backend` block in `versions.tf`) rather
  than committing state.
- **Idempotent.** The script skips hosts that already have OneAgent installed, and
  the `null_resource` triggers only re-run when the host, flags, arch, or script change.
- **Installer flags.** Tune `installer_flags` (e.g. `--set-host-group=...`,
  `--set-infra-only=true`) per the Dynatrace docs.
- **Verify success** in Dynatrace under *Deployment status* / *Hosts*.
```
