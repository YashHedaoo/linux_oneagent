# Install Dynatrace OneAgent on On-Premises Linux Servers

> **Welcome!** This repo automates the installation of
> [Dynatrace OneAgent](https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent/installation-and-operation/linux/installation/install-oneagent-on-linux)
> on existing Linux servers that we cannot reach through any cloud-managed
> mechanism (no SSM, no GCE guest agent, etc.).
>
> If you are new here, **read sections 1–4 in order, then jump to whichever
> scenario in section 6 matches your work**.

---

## Table of Contents

1. [What this repo does (and does not do)](#1-what-this-repo-does-and-does-not-do)
2. [How it works](#2-how-it-works)
3. [Repository layout](#3-repository-layout)
4. [First-time setup](#4-first-time-setup)
5. [Configuration reference](#5-configuration-reference)
6. [Common scenarios](#6-common-scenarios)
7. [Security model](#7-security-model)
8. [Operations & troubleshooting](#8-operations--troubleshooting)
9. [FAQ](#9-faq)
10. [Glossary](#10-glossary)

---

## 1. What this repo does (and does not do)

**Does**
- Open an SSH connection to each on-prem Linux server you list
- Upload a small install script
- Run the script as root to download (or use a pre-staged) OneAgent installer,
  cryptographically verify its signature, and install it
- Clean up after itself — no installers left on the target

**Does NOT**
- Provision or decommission servers
- Configure firewalls / DNS / routing
- Manage the Dynatrace tenant itself (you create the PaaS token outside this repo)
- Work without SSH access from the runner to the targets

If you need a one-off install on a single box with no automation, see the
[Manual install recipe](#manual-single-host-install) at the bottom — you don't
need this repo for that.

---

## 2. How it works

```
                          ┌───────────────────────────┐
                          │  GitHub Actions workflow   │
                          │  (deploy.yml)              │
                          └─────────────┬─────────────┘
                                        │  terraform init/plan/apply
                                        ▼
                          ┌───────────────────────────┐
                          │   null_resource.oneagent  │
                          │   (one per target host)   │
                          └─────────────┬─────────────┘
                                        │  SSH (optionally via Bastion)
                                        ▼
        ┌─────────────────────────────────────────────────────┐
        │  scripts/install_oneagent.sh  (runs as root)       │
        │   1. Skip if OneAgent is already running            │
        │   2. Download installer OR use DT_LOCAL_INSTALLER  │
        │   3. Verify PKCS7 signature vs Dynatrace root cert │
        │   4. Run installer with DT_INSTALLER_FLAGS         │
        │   5. Clean up                                       │
        └─────────────────────────────────────────────────────┘
```

Key properties:

| Property | How |
|---|---|
| **Idempotent** | `install_oneagent.sh` checks `systemctl is-active oneagent` and an active process before doing anything |
| **Signed installer** | PKCS7 verification against Dynatrace's root CA cert (toggleable but on by default) |
| **Air-gapped ready** | Ship a local cert (`local_cert_path`) and/or pre-downloaded installer (`local_installer_path`) |
| **Bastion-aware** | Optional SSH jump host via `bastion_*` variables |
| **No secret leaks** | PaaS token never appears on any process command line — passed via shell env across the sudo boundary |
| **Production gate** | GitHub Actions `environment: production` blocks apply until reviewers approve |

---

## 3. Repository layout

| File | Purpose |
|---|---|
| `versions.tf` | Terraform + provider versions, **state backend examples** (pick one — local backend is fine for solo work) |
| `variables.tf` | All inputs — no required secrets are hardcoded |
| `main.tf` | One `null_resource` per host: SSH, pre-flight check, uploads script/artifacts, runs installer |
| `outputs.tf` | Prints the list of hosts and the tenant URL after apply |
| `scripts/install_oneagent.sh` | The actual installer (download → verify → install → cleanup) |
| `terraform.tfvars.example` | Template for local runs — copy to `terraform.tfvars` and edit |
| `.github/workflows/deploy.yml` | CI pipeline: PR → plan, push to main → apply with approval |

---

## 4. First-time setup

> **Time estimate: 20–30 minutes.** You will need a Dynatrace tenant URL, a
> PaaS token, and SSH access to at least one target server.

### 4.1 Install local tools
- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5
- An SSH client (built into macOS / Linux; use OpenSSH on Windows)

Verify:
```bash
terraform version
ssh -V
```

### 4.2 Get a Dynatrace PaaS token
1. Log into your Dynatrace tenant (e.g. `https://abc12345.live.dynatrace.com`)
2. Go to **Deploy Dynatrace → Start installation → Linux**
3. Copy the **PaaS token** (starts with `dt0c01.`)
4. Note your environment URL — copy it **without** a trailing `/api`

### 4.3 Verify SSH + sudo on at least one target
You need an SSH user who can `sudo -n true` (no password prompt). Confirm:
```bash
ssh ubuntu@srv-app-01 sudo -n true
echo "sudo OK"   # if you see this, you're good
```

If sudo prompts for a password, ask the server owner to add a NOPASSWD rule in
`/etc/sudoers.d/` (e.g. `ubuntu ALL=(ALL) NOPASSWD: ALL` for non-prod hosts).

### 4.4 Clone and configure
```bash
git clone <your-fork-url> tf_linux_oneagent
cd tf_linux_oneagent

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars       # fill in dt_environment_url, target_hosts, ssh_* etc.
```

### 4.5 Dry-run
```bash
terraform init
terraform plan
```

Read the plan output — you should see one `null_resource.oneagent["<host>"]`
per host in your `target_hosts` list. If you see zero resources, your
`target_hosts` is empty.

### 4.6 Apply
```bash
terraform apply
```

You should see, per host:
```
null_resource.oneagent["srv-app-01"]: Creating...
null_resource.oneagent["srv-app-01"]: Provisioning with remote-exec...
==> Pre-flight: verifying passwordless sudo on srv-app-01
==> Pre-flight OK
==> OneAgent already running — skipping install.   (or)   ==> Downloading OneAgent installer...
...
null_resource.oneagent["srv-app-01"]: Creation complete
```

### 4.7 Confirm in Dynatrace
Within ~2 minutes, the host should appear in **Dynatrace → Hosts**.

---

## 5. Configuration reference

All variables live in `variables.tf`. Summary:

### Required
| Variable | Description | Example |
|---|---|---|
| `dt_environment_url` | Dynatrace tenant URL | `https://abc12345.live.dynatrace.com` |
| `dt_paas_token` | PaaS token | `dt0c01.abc.xyz` |
| `target_hosts` | List of hosts (IP or FQDN) | `["srv-app-01", "192.168.1.10"]` |
| `ssh_private_key` | PEM contents of SSH key | `file("~/.ssh/id_ed25519")` |

### Optional — common
| Variable | Default | Description |
|---|---|---|
| `ssh_user` | `ubuntu` | SSH user (must have passwordless sudo) |
| `ssh_port` | `22` | SSH port |
| `arch` | `x86` | `x86` / `arm` / `ppcle` / `s390` |
| `installer_flags` | `--set-infra-only=false --set-app-log-content-access=true` | Passed to the installer |
| `verify_signature` | `true` | Verify PKCS7 signature before installing |
| `apply_parallelism` | `10` | Max concurrent installs |
| `ssh_timeout` | `5m` | Per-host SSH timeout |

### Optional — air-gapped / offline
| Variable | Default | Description |
|---|---|---|
| `local_cert_path` | `null` | Local copy of `dt-root.cert.pem`. Use when targets can't reach `ca.dynatrace.com`. |
| `local_installer_path` | `null` | Pre-downloaded `Dynatrace-OneAgent-Linux.sh`. Use when targets can't reach the Dynatrace tenant. |

### Optional — SSH bastion / jump host
| Variable | Default | Description |
|---|---|---|
| `bastion_host` | `null` | FQDN/IP of the jump host |
| `bastion_user` | `ssh_user` | SSH user on the bastion |
| `bastion_private_key` | `ssh_private_key` | Key for the bastion |
| `bastion_port` | `22` | Bastion SSH port |

### Installer flags you might want
```bash
# Tag hosts by environment
"--set-host-tag=env=production --set-host-tag=team=platform"

# Group hosts for dashboards
"--set-host-group=Production-Linux-Servers"

# Monitor specific processes
"--set-process-arg=--filter-process-name=tomcat"

# Use a proxy for outbound traffic
"--set-proxy=<proxy.host>:<port>"
```
See [all installer flags](https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent/installation-and-operation/linux/installation/install-oneagent-on-linux).

---

## 6. Common scenarios

### Scenario A — Trigger via GitHub Actions UI (manual)

1. **Actions** tab → **Deploy Dynatrace OneAgent** → **Run workflow**
2. Fill in:
   - **target_hosts**: `srv-app-01.internal` or `["192.168.10.50","192.168.10.51"]`
   - **runner**: `self-hosted` (if your runner is inside the same network as
     the targets) or `ubuntu-latest` (if you use a Bastion host)
   - **installer_flags**: leave default unless you have a reason to change it
   - **apply_parallelism**: leave at `10` for most cases
3. Click **Run workflow**
4. Wait for the **production** approval (if configured in your repo)

### Scenario B — Trigger on push to `main`

Set the `TARGET_HOSTS` secret in GitHub (JSON array string). Any push to `main`
that changes `.tf` or `scripts/**` will plan, then apply with the approval gate.

### Scenario C — Local apply (no CI)

```bash
terraform apply
```

Useful for: testing on a single dev host, debugging, air-gapped environments
without internet access from the runner.

### Scenario D — Air-gapped network

If your targets cannot reach `ca.dynatrace.com` AND cannot reach your Dynatrace
tenant URL:

1. From an internet-connected machine, download:
   ```bash
   curl -fsSL -o dt-root.cert.pem https://ca.dynatrace.com/dt-root.cert.pem
   curl -fsSL -o Dynatrace-OneAgent-Linux.sh \
     "https://<DT_URL>/api/v1/deployment/installer/agent/unix/default/latest?Api-Token=<TOKEN>"
   ```
2. SCP them to your Terraform runner machine:
   ```bash
   scp dt-root.cert.pem Dynatrace-OneAgent-Linux.sh you@runner:~/tf_linux_oneagent/certs/
   ```
3. In `terraform.tfvars`:
   ```hcl
   local_cert_path        = "./certs/dt-root.cert.pem"
   local_installer_path   = "./certs/Dynatrace-OneAgent-Linux.sh"
   verify_signature       = true
   ```

### Manual (single-host) install

If you just need OneAgent on one box without any automation:
```bash
ssh user@host
sudo bash -c "$(curl -fsSL \
  'https://<DT_URL>/api/v1/deployment/installer/agent/unix/default/latest?Api-Token=<TOKEN>')"
```
This repo is overkill for that — use the one-liner instead.

---

## 7. Security model

| Concern | How we handle it |
|---|---|
| **PaaS token at rest** | Stored in GitHub Secrets (encrypted) or `terraform.tfvars` (gitignored). Never in repo. |
| **PaaS token in transit to target** | Exported in the SSH user's shell env, passed into `sudo` via `--preserve-env=<list>` — never on any process command line. |
| **PaaS token on target disk** | Never written to disk on the target — env vars live only in the ephemeral shell. |
| **SSH private key** | Marked `sensitive = true` in Terraform (not printed in plan output). Prefer `file("~/.ssh/...")` over a heredoc in tfvars. |
| **Installer integrity** | PKCS7 signature verified against `ca.dynatrace.com/dt-root.cert.pem` (or your local copy). |
| **Production approval** | GitHub Actions `environment: production` blocks `apply` until an approved reviewer clicks through. Configure in **Settings → Environments → production → Required reviewers**. |
| **Audit trail** | Every apply creates a GitHub Actions run log; state changes are diffable in the PR. |
| **State file** | Pick a real backend in `versions.tf` (S3 / Azure Blob / GCS / Terraform Cloud). The default `local` backend is fine for solo dev only. |

### Sudo hardening (recommended)

In `/etc/sudoers.d/dynatrace-deploy` on each target:
```sudoers
Defaults:ubuntu env_keep += "DT_ENV_URL DT_PAAS_TOKEN DT_ARCH DT_INSTALLER_FLAGS DT_VERIFY_SIGNATURE DT_CERT_PATH DT_LOCAL_INSTALLER"
ubuntu ALL=(root) NOPASSWD: /bin/bash /tmp/install_oneagent.sh
```
This restricts the SSH user to running **only** the install script as root,
which dramatically reduces blast radius if the SSH key is ever compromised.

---

## 8. Operations & troubleshooting

### Uninstall OneAgent from a host
```bash
ssh user@host
sudo /opt/dynatrace/oneagent/agent/uninstall.sh
```
> We don't yet have a Terraform flow for uninstall. PRs welcome.

### "Pre-flight: verifying passwordless sudo ... failed"
The SSH user can't `sudo` without a password. Fix the sudoers file on the target:
```bash
echo "ubuntu ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ubuntu-nopasswd
```
Then re-apply.

### "Failed to download installer from <DT_URL>"
- Check the target can reach the tenant URL: `curl -fsSL <DT_URL>`
- Check the PaaS token is valid and not expired in the Dynatrace UI
- If the target is air-gapped, set `local_installer_path`

### "Installer signature verification FAILED"
- The tenant URL is wrong, the cert is stale, or the installer was tampered with. Do NOT proceed.
- If air-gapped, ensure `local_cert_path` points to the cert you downloaded
  from the **same tenant** you're installing for

### "OneAgent service is active — skipping install."
Expected behaviour — the resource is idempotent. To force a reinstall,
update a `triggers` value in `main.tf` (e.g. bump a comment in the script so
its SHA changes).

### Host shows up but never sends data
1. On the target: `systemctl status oneagent` — is it running?
2. On the target: `journalctl -u oneagent --since "10 min ago"` — any errors?
3. From an external host: `curl https://<DT_URL>/api/v1/entities?entitySelector=type(HOST)` —
   is the host registered?
4. Check outbound connectivity on port 443 to your tenant URL.

### I changed `target_hosts` but Terraform says "no changes"
You added a host that wasn't in `target_hosts` before? It should show
`null_resource.oneagent["new-host"]: Creating...`. If not, double-check the
syntax — Terraform is sensitive to trailing commas in lists.

### "Error: Saved plan is stale"
State was modified by someone else. Re-run `terraform plan` to refresh.

### Re-running a failed apply
`terraform apply` is safe to re-run. Failed hosts will be retried; successful
hosts will be skipped (idempotency).

---

## 9. FAQ

**Q: Does this work on Windows targets?**
A: No — Dynatrace provides a separate Windows installer. This repo only handles
Linux.

**Q: Can I use this for Kubernetes nodes?**
A: Not recommended. Use the [Dynatrace Operator + DynaKube](https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent/installation-and-operation/kubernetes)
approach for clusters.

**Q: Why not just `apt install dynatrace-oneagent`?**
A: You'd still need to register the agent with the tenant. This repo handles
both download AND registration in one shot.

**Q: Can I run this from a laptop sitting on a different network?**
A: Only if the laptop can reach both the tenant URL (for downloading the
installer) and the targets (or via Bastion). Otherwise use the GitHub Actions
runner or a self-hosted runner inside the target network.

**Q: Why `null_resource` instead of an actual provider?**
A: There's no first-class Terraform provider for "install software on an
arbitrary SSH-reachable Linux host". `null_resource` + provisioners is the
idiomatic Terraform pattern for this.

**Q: Can I get a Slack notification when an apply fails?**
A: Add a Slack notification step to `.github/workflows/deploy.yml`. There are
many community actions for this (e.g. `slackapi/slack-github-action`).

**Q: Where do I see what `apply_parallelism` should be?**
A: Default 10 is conservative. Watch your Dynatrace tenant rate limits
(host ingest rate) — bump down if you see 429s.

---

## 10. Glossary

- **OneAgent** — Dynatrace's per-host agent. Collects host, process, and
  application telemetry.
- **Full-stack** — OneAgent monitors infrastructure AND application code
  (requires `--set-infra-only=false`, the default).
- **Infrastructure-only** — OneAgent only monitors the host metrics, no
  code-level tracing (`--set-infra-only=true`).
- **PaaS token** — Dynatrace API token with `PaaS integration` scope. Used to
  download the installer. Rotated in **Access management → Tokens**.
- **Environment URL** — Your tenant's web URL. For SaaS it's
  `<ID>.live.dynatrace.com`; for Managed it's your cluster's URL.
- **ActiveGate** — Dynatrace's on-prem relay that hosts OneAgent installer
  downloads when the cluster is fully air-gapped. Set `dt_environment_url`
  to the ActiveGate URL instead of the SaaS URL.
- **Bastion / Jump host** — An SSH proxy used to reach hosts on a private
  network from a runner outside that network.
- **Idempotent** — Re-running the operation is safe and produces no change if
  the desired state is already in place.
- **PKCS7 signature** — Cryptographic signature format Dynatrace uses on
  their installer. Verification ensures the bytes you downloaded are exactly
  the bytes Dynatrace published.
- **`null_resource`** — A Terraform resource that does nothing on its own but
  lets you attach provisioners (file / remote-exec / local-exec). The standard
  idiom for "Terraform does X" where X has no native provider.