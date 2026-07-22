# Install Dynatrace OneAgent on On-Premises Linux Servers

This repository installs [Dynatrace OneAgent](https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent)
on Linux servers inside your own data center ("on-premises") using Bash scripts over SSH
and GitHub Actions. OneAgent is Dynatrace's small program that runs on each
server and reports host, process, and application data back to your Dynatrace
tenant.

**Who this is for:** platform engineers who need to push OneAgent to a fleet
of on-prem Linux boxes that you cannot reach through any cloud-native tool
(no AWS SSM, no GCE guest agent, etc.) — only SSH.

---

## Table of Contents

1. [Which path should I follow?](#1-which-path-should-i-follow)
2. [The 30-minute quick start](#2-the-30-minute-quick-start)
3. [How it works](#3-how-it-works)
4. [Files in this repository](#4-files-in-this-repository)
5. [Configuration reference](#5-configuration-reference)
6. [Scenarios](#6-scenarios)
7. [Security model](#7-security-model)
8. [Operations and troubleshooting](#8-operations-and-troubleshooting)
9. [FAQ](#9-faq)

---

## 1. Which path should I follow?

Pick the row that matches your situation, then jump to that section.

| Your situation | Go to |
|---|---|
| I just want it running on a few boxes. No automation, no CI. | [Quick start](#2-the-30-minute-quick-start) |
| I want to trigger installs from the GitHub web UI. | [Scenario A](#scenario-a--run-it-from-github-actions) |
| I want installs to happen automatically when code changes. | [Scenario B](#scenario-b--auto-run-on-push-to-main) |
| I want to run deployment locally from my laptop. | [Scenario C](#scenario-c--run-locally) |
| My target servers cannot reach the internet. | [Scenario D](#scenario-d--air-gapped-network-no-internet-from-targets) |
| I only need to install on ONE box, once. | [Manual one-liner](#manual-one-liner-single-host) at the bottom of §6 |
| I'm new and want to understand the moving parts first. | [How it works](#3-how-it-works) |

---

## 2. The 30-minute quick start

> Goal: install OneAgent on your first on-prem Linux server using this repo,
> in 30 minutes or less. After this works, scale up.

### Step 1 — Grab a Dynatrace PaaS token (3 min)

A "PaaS token" is a Dynatrace API token that lets you download the OneAgent
installer.

1. Open your Dynatrace tenant (the URL looks like
   `https://abc12345.live.dynatrace.com`).
2. In the left menu: **Deploy Dynatrace** → **Start installation** → **Linux**.
3. You'll see a PaaS token. It starts with `dt0c01.`. Copy it.
4. Also note your **environment URL** (the web address of your tenant).
   Copy it **without** a trailing `/api`.

Keep these two values handy — you'll paste them in Step 3.

### Step 2 — Confirm you can SSH to your target (3 min)

Pick one Linux server you want to test on. You need an SSH user that can run
`sudo` without typing a password (this is called "passwordless sudo").

```bash
ssh ubuntu@your-server-ip
sudo -n true
echo "sudo OK"      # if you see this, you're good
```

If `sudo` asks for a password, add this file on the target server
(`/etc/sudoers.d/ubuntu-nopasswd`):

```
ubuntu ALL=(ALL) NOPASSWD: ALL
```

### Step 3 — Run deployment script locally (5 min)

Export the environment variables and run `./scripts/deploy.sh`:

```bash
export DT_ENV_URL="https://abc12345.live.dynatrace.com"
export DT_PAAS_TOKEN="dt0c01.ST..."
export SSH_USER="ubuntu"

./scripts/deploy.sh your-server-ip
```

If everything worked, you'll see:
```
==> Starting deployment on target host: your-server-ip
==> [your-server-ip] Verifying SSH connection and passwordless sudo...
==> [your-server-ip] Pre-flight check passed.
==> [your-server-ip] Uploading installer script to /tmp/install_oneagent.sh...
==> [your-server-ip] Running installer script as root...
==> [your-server-ip] OneAgent deployment succeeded!
==> All deployments completed successfully!
```

---

## 3. How it works

```
┌─────────────────────────────────────────────────────────────┐
│ Orchestrator (GitHub Runner or Local Laptop)                 │
│                                                             │
│  ./scripts/deploy.sh                                        │
└──────────────┬──────────────────────────────────────────────┘
               │ SSH / SCP
               ▼
┌─────────────────────────────────────────────────────────────┐
│ Target Linux Host (On-Prem Server)                           │
│                                                             │
│  1. Receives /tmp/install_oneagent.sh                       │
│  2. Executes with sudo --preserve-env                        │
│  3. Downloads OneAgent from Dynatrace tenant                │
│  4. Verifies PKCS7 signature (optional)                     │
│  5. Runs installer & cleans up                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Files in this repository

| File | Purpose |
|---|---|
| `scripts/deploy.sh` | Orchestrates SSH connections to target Linux hosts, transfers `install_oneagent.sh`, and runs it with root privileges via `sudo`. |
| `scripts/install_oneagent.sh` | The installer script executed on each host. Downloads OneAgent, verifies signature, runs installation, and exits safely if already installed. |
| `.github/workflows/deploy.yml` | The GitHub Actions workflow for automated deployments. |

---

## 5. Configuration reference

### GitHub Secrets Reference

#### 🔴 Required Secrets

| Secret | Description |
|---|---|
| `DT_PAAS_TOKEN` | Dynatrace PaaS API token used to download the OneAgent installer. |
| `ARTIFACTORY_URL` | JFrog Artifactory URL pointing to the plain-text file containing `DT_ENV_URL`. |
| `TARGET_HOSTS` | Space/comma-separated list of target server IPs/hostnames (required for automated triggers). |

#### 🟡 Optional Secrets (with default values)

| Secret | Default Value | Description |
|---|---|---|
| `ARTIFACTORY_TOKEN` | *None* | Bearer token for JFrog Artifactory (only if repository requires auth). |
| `SSH_PRIVATE_KEY` | *None* | SSH private key to authenticate to target Linux servers. |
| `SSH_USER` | `ubuntu` | SSH username on target servers. |
| `BASTION_HOST` | *None* | Bastion/jump host IP or domain for private network access. |
| `BASTION_USER` | `ubuntu` (or `SSH_USER`) | SSH username on the bastion host. |

### Fetching `DT_ENV_URL` from JFrog Artifactory

Instead of storing `DT_ENV_URL` in GitHub Secrets or local environment variables, you can store a plain-text file in JFrog Artifactory containing the URL.

If `DT_ENV_URL` is not provided, `deploy.sh` dynamically fetches it from Artifactory:

```bash
export ARTIFACTORY_URL="https://artifactory.example.com/artifactory/generic-local/dynatrace/dt_env_url.txt"
export ARTIFACTORY_TOKEN="your-jfrog-access-token"
export DT_PAAS_TOKEN="dt0c01.ST..."

./scripts/deploy.sh your-server-ip
```

---

## 6. Scenarios

### Scenario A — Run it from GitHub Actions (Manual trigger)

Go to **Actions** tab → **Deploy Dynatrace OneAgent** → **Run workflow**. Fill in target hosts and click **Run workflow**.

### Scenario B — Auto-run on push to main

Any commit merged into `main` targeting `scripts/**` or `.github/workflows/deploy.yml` will trigger deployment to hosts listed in `TARGET_HOSTS` secret.

### Scenario C — Run locally

```bash
export DT_ENV_URL="https://abc12345.live.dynatrace.com"
export DT_PAAS_TOKEN="dt0c01.ST..."
export TARGET_HOSTS="192.168.1.10 192.168.1.11"

./scripts/deploy.sh
```

---

## 7. Security model

- **Secrets Handling**: PaaS tokens are passed as environment variables and preserved across `sudo` via `--preserve-env`. Tokens never appear in command-line arguments (`ps aux` / `/proc`).
- **Signature Verification**: Downloads Dynatrace root cert and verifies PKCS7 cryptographic signature of installer binary prior to execution.
- **Idempotence**: Detects running OneAgent processes/services and skips reinstall if active.

---

## 8. Operations and troubleshooting

- **Check Service**: `systemctl status oneagent`
- **Check Logs**: `journalctl -u oneagent` or `/var/log/dynatrace/oneagent/`

---

## 9. FAQ

**Q: Why was Terraform removed?**  
A: Terraform was previously used only as an SSH runner (`null_resource`), which created unnecessary state lock management without provisioning real infrastructure. A pure Bash script runner (`deploy.sh`) provides lightweight, fast, and dependency-free SSH execution.