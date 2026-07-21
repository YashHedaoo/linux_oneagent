# Install Dynatrace OneAgent on On-Premises Linux Servers

This repository installs [Dynatrace OneAgent](https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent)
on Linux servers inside your own data center ("on-premises") using Terraform
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
| I want to run Terraform from my laptop. | [Scenario C](#scenario-c--run-terraform-locally) |
| My target servers cannot reach the internet. | [Scenario D](#scenario-d--air-gapped-network-no-internet-from-targets) |
| I only need to install on ONE box, once. | [Manual one-liner](#manual-one-liner-single-host) at the bottom of §6 |
| I'm new and want to understand the moving parts first. | [How it works](#3-how-it-works) |

---

## 2. The 30-minute quick start

> Goal: install OneAgent on your first on-prem Linux server using this repo,
> in 30 minutes or less. After this works, scale up.

### Step 1 — Install Terraform on your machine (2 min)

You need Terraform version 1.5 or newer.

```bash
# macOS
brew install terraform

# Linux (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install -y terraform

# Or grab the binary directly: https://developer.hashicorp.com/terraform/install
```

Verify it works:
```bash
terraform version
# Expected: Terraform v1.5.x or higher
```

### Step 2 — Grab a Dynatrace PaaS token (3 min)

A "PaaS token" is a Dynatrace API token that lets you download the OneAgent
installer.

1. Open your Dynatrace tenant (the URL looks like
   `https://abc12345.live.dynatrace.com`).
2. In the left menu: **Deploy Dynatrace** → **Start installation** → **Linux**.
3. You'll see a PaaS token. It starts with `dt0c01.`. Copy it.
4. Also note your **environment URL** (the web address of your tenant).
   Copy it **without** a trailing `/api`.

Keep these two values handy — you'll paste them in Step 4.

### Step 3 — Confirm you can SSH to your target (3 min)

Pick one Linux server you want to test on. You need an SSH user that can run
`sudo` without typing a password (this is called "passwordless sudo").

```bash
ssh ubuntu@your-server-ip
sudo -n true
echo "sudo OK"      # if you see this, you're good
```

If `sudo` asks for a password, ask the server owner to add this file
(`/etc/sudoers.d/ubuntu-nopasswd`):

```
ubuntu ALL=(ALL) NOPASSWD: ALL
```

Then log out and log back in.

### Step 4 — Clone and configure (5 min)

```bash
git clone <repo-url> tf_linux_oneagent
cd tf_linux_oneagent

cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` in your editor and fill in at minimum:

```hcl
dt_environment_url = "https://abc12345.live.dynatrace.com"   # your tenant
dt_paas_token      = "dt0c01.YOUR_TOKEN_HERE"               # from Step 2
target_hosts       = ["your-server-ip"]                     # from Step 3
ssh_private_key    = file("~/.ssh/id_ed25519")              # path to your SSH key
```

Save the file. **Never commit `terraform.tfvars` to git** — it should be in
your `.gitignore` (it already is in this repo).

### Step 5 — Preview the install (2 min)

```bash
terraform init        # downloads the Terraform providers
terraform plan        # shows what would happen, without changing anything
```

You should see output like:

```
Plan: 1 to add, 0 to change, 0 to destroy.
```

That "1 to add" is the install operation for your one test server. If you see
"0 to add", your `target_hosts` list is empty.

### Step 6 — Install for real (5 min)

```bash
terraform apply
```

Type `yes` when prompted. You'll see (roughly):

```
null_resource.oneagent["your-server-ip"]: Creating...
null_resource.oneagent["your-server-ip"]: Provisioning with remote-exec...
==> Pre-flight: verifying passwordless sudo on your-server-ip
==> Pre-flight OK
==> Downloading OneAgent installer (arch=x86)...
==> Verifying installer signature...
==> Signature OK.
==> Running installer with flags: ...
==> OneAgent installation complete.

null_resource.oneagent["your-server-ip"]: Creation complete after 2m13s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

### Step 7 — Confirm it worked (1 min)

Within 1–2 minutes, your server should appear in the Dynatrace UI under
**Hosts**.

You can also check on the server itself:

```bash
ssh ubuntu@your-server-ip systemctl status oneagent
# Expected: Active: active (running)
```

**Done.** Now go to [Scenario A or B](#6-scenarios) to set up the GitHub
Actions pipeline so your whole team can use this.

---

## 3. How it works

Here's the flow when you trigger an install:

```
                       ┌──────────────────────────────┐
                       │  GitHub Actions workflow     │
                       │  (you click Run, or a push   │
                       │   to main triggers it)       │
                       └──────────────┬───────────────┘
                                      │ runs Terraform
                                      ▼
                       ┌──────────────────────────────┐
                       │  One "null_resource" per     │
                       │  target host in main.tf      │
                       └──────────────┬───────────────┘
                                      │ opens an SSH connection
                                      │ (optionally via a bastion)
                                      ▼
        ┌─────────────────────────────────────────────────────────┐
        │  scripts/install_oneagent.sh  — runs as root on target │
        │   1. Check if OneAgent is already running. If yes, stop.│
        │   2. Download the installer (or use a pre-staged one). │
        │   3. Verify the installer's PKCS7 cryptographic         │
        │      signature against Dynatrace's root CA cert.        │
        │   4. Run the installer with your flags.                │
        │   5. Delete the installer and any temp files.          │
        └─────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                       Your server shows up in Dynatrace
```

### Key guarantees

| Property | How it's enforced |
|---|---|
| **Safe to re-run** (idempotent) | The script checks if the `oneagent` service is already running before doing anything. Already-installed hosts are skipped. |
| **Installer is authentic** | The installer is verified with a PKCS7 cryptographic signature against Dynatrace's root certificate. If verification fails, the install aborts. |
| **Works without internet from targets** | You can pre-stage the certificate and/or installer and ship them to the target. |
| **Works through a jump host** | Set the `bastion_*` variables and Terraform will hop through your jump host. |
| **PaaS token never leaks** | The token is exported in the SSH session's environment and handed to `sudo` via `--preserve-env=<list>`. It never appears on any process command line (so `ps` can't see it). |
| **Production is gated** | A GitHub `environment: production` approval step blocks `terraform apply` until a reviewer approves. |

---

## 4. Files in this repository

| File | What it does |
|---|---|
| `versions.tf` | Declares the Terraform version we require and the `null` provider. Also has ready-to-use examples for state backends (S3, Azure Blob, GCS, Terraform Cloud) — pick one before going to production. |
| `variables.tf` | All the inputs you can set. Required ones, defaults, and validation rules. |
| `main.tf` | The actual work: one `null_resource` per host that opens SSH, runs pre-flight checks, uploads the script, and runs the installer. |
| `outputs.tf` | Prints the list of hosts and the tenant URL after `terraform apply`. |
| `scripts/install_oneagent.sh` | The shell script that runs on each target server to install OneAgent. You generally won't edit this. |
| `terraform.tfvars.example` | A template file. Copy to `terraform.tfvars` for local runs. |
| `.github/workflows/deploy.yml` | The GitHub Actions pipeline. Defines when Terraform runs and how secrets are passed in. |

---

## 5. Configuration reference

All variables live in `variables.tf`. Here are the ones you actually need to
think about.

### Required — you must set these

| Variable | What it is | Example |
|---|---|---|
| `dt_environment_url` | Your Dynatrace tenant URL | `https://abc12345.live.dynatrace.com` |
| `dt_paas_token` | Dynatrace PaaS API token (see Step 2) | `dt0c01.abc.xyz` |
| `target_hosts` | List of servers you want to install on | `["srv-app-01", "192.168.1.10"]` |
| `ssh_private_key` | The PEM private key for SSH. Use `file("...")` so the key isn't pasted inline. | `file("~/.ssh/id_ed25519")` |

> **All other variables have sensible defaults** (e.g. SSH user is `ubuntu`,
> installer runs full-stack with log access enabled). You only need to set
> them if your environment is non-standard — see `variables.tf` for the full
> list, and [common flags](#common-installer-flags) below for the most useful
> customizations.

### Common installer flags

These get appended to the install command. Combine as needed:

```bash
# Tag every host with environment and team metadata
"--set-host-tag=env=production --set-host-tag=team=platform"

# Group hosts so they show up together in dashboards
"--set-host-group=Production-Linux-Servers"

# Only monitor specific processes (faster, less data)
"--set-process-arg=--filter-process-name=tomcat"

# Send traffic through a corporate proxy
"--set-proxy=proxy.corp.example.com:8080"
```

The full list of installer flags is in
[Dynatrace's docs](https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent/installation-and-operation/linux/installation/install-oneagent-on-linux).

---

## 6. Scenarios

### Scenario A — Run it from GitHub Actions

This is the most common setup: a team pushes to `main` (or clicks "Run
workflow"), and GitHub Actions installs OneAgent on every host in the list.

**When to use:** you have a team, you want audit logs, and you want
production changes to require approval.

#### A.1 — Decide your runner type

GitHub Actions runs your workflow on a "runner" — a virtual machine that
executes your code. You have two options:

| Runner type | Where it runs | When to pick it |
|---|---|---|
| `self-hosted` | A machine **you control**, inside your network | Your targets are on-prem and a self-hosted runner can SSH to them directly. **Pick this for most on-prem setups.** |
| `ubuntu-latest` | GitHub's cloud | Your targets are reachable over the internet (rare for true on-prem), OR you have a bastion / jump host that the cloud runner can reach. |

For a typical on-prem setup, deploy a self-hosted runner on a VM inside the
same network as your target servers. See
[GitHub's docs on self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners).

#### A.2 — Configure secrets in GitHub

Go to your repo → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**. Add each of these:

| Secret name | What to put | Required? |
|---|---|---|
| `DT_ENVIRONMENT_URL` | Your tenant URL, e.g. `https://abc12345.live.dynatrace.com` | ✅ |
| `DT_PAAS_TOKEN` | PaaS token from Step 2 of the quick start | ✅ |
| `SSH_PRIVATE_KEY` | Full PEM contents of the SSH private key (including the `-----BEGIN/END-----` lines) | ✅ |
| `TARGET_HOSTS` | JSON array string: `["srv-app-01","192.168.10.50"]` | ✅ (or pass via UI) |
| `SSH_USER` | SSH user on targets. Only set if your user is NOT `ubuntu`. | Optional (defaults to `ubuntu`) |
| `BASTION_HOST` | FQDN/IP of jump host | Only if using a bastion |
| `BASTION_USER` | SSH user on bastion | Only if using a bastion (defaults to `SSH_USER`) |
| `BASTION_PRIVATE_KEY` | PEM key for bastion | Only if using a bastion (defaults to `SSH_PRIVATE_KEY`) |

#### A.3 — Set up the production approval gate (one-time)

For safety, require a human to approve `terraform apply` before it runs.

1. GitHub → **Settings** → **Environments** → **New environment** → name it `production`.
2. Check **Required reviewers** and add yourself and/or your team.
3. Save.

Now every push to `main` will pause at "Waiting for approval" before applying.

#### A.4 — Trigger an install

**Option 1 — Manual run via the UI:**
1. Go to the **Actions** tab.
2. Click **Deploy Dynatrace OneAgent** in the left sidebar.
3. Click **Run workflow** (top right).
4. Fill in the inputs:
   - **target_hosts**: a hostname, or a JSON array of hostnames
   - **runner**: `self-hosted` (most common for on-prem)
   - **installer_flags**: leave default unless you need custom flags
   - **apply_parallelism**: leave at `10`
5. Click **Run workflow**.
6. If you set up the approval gate, wait for a reviewer to approve.

**Option 2 — Automatic on push to `main`:**
- Set the `TARGET_HOSTS` secret (see A.2). Any push to `main` that changes
  `.tf` files or `scripts/**` will trigger a plan, then apply with approval.

### Scenario B — Auto-run on push to `main`

Already covered above (Option 2 in A.4). In short:

1. Set `TARGET_HOSTS` as a repo secret.
2. Set the other required secrets.
3. Push to `main`.
4. The workflow plans, then waits for approval, then applies.

**Tip:** open a PR first to see the plan in the PR comments before merging.

### Scenario C — Run Terraform locally

Useful for: testing on a single dev host, debugging, or environments where
GitHub Actions isn't available.

```bash
terraform apply
```

That's it. Terraform reads `terraform.tfvars` and runs the same logic.

### Scenario D — Air-gapped network (no internet from targets)

Use this when your target servers cannot reach either `ca.dynatrace.com`
(Dynatrace's certificate host) OR your Dynatrace tenant URL.

**Step 1** — On any internet-connected machine, download the cert and the
installer:

```bash
curl -fsSL -o dt-root.cert.pem https://ca.dynatrace.com/dt-root.cert.pem

curl -fsSL -o Dynatrace-OneAgent-Linux.sh \
  "https://<DT_URL>/api/v1/deployment/installer/agent/unix/default/latest?Api-Token=<TOKEN>"
```

**Step 2** — Copy them to the machine that will run Terraform:

```bash
scp dt-root.cert.pem Dynatrace-OneAgent-Linux.sh you@runner:~/tf_linux_oneagent/certs/
```

**Step 3** — In `terraform.tfvars`, point Terraform at them:

```hcl
local_cert_path      = "./certs/dt-root.cert.pem"
local_installer_path = "./certs/Dynatrace-OneAgent-Linux.sh"
verify_signature     = true
```

`terraform apply` will now ship these files to each target instead of
downloading them.

### Manual one-liner (single host)

If you only need OneAgent on **one** box and you don't want any of this
automation, skip the whole repo and run this on the target itself:

```bash
ssh user@host
sudo bash -c "$(curl -fsSL \
  'https://<DT_URL>/api/v1/deployment/installer/agent/unix/default/latest?Api-Token=<TOKEN>')"
```

This is the simplest possible install. Use it when:
- You have exactly one host.
- You'll never need to do this again.
- You don't need audit logs or approval workflows.

If any of those don't apply, come back and use this repo.

---

## 7. Security model

| Concern | How we handle it |
|---|---|
| **PaaS token at rest** (sitting in storage) | Stored in GitHub Secrets (encrypted at rest by GitHub) or in `terraform.tfvars` (gitignored). Never in the repo source. |
| **PaaS token in transit to target** | Exported in the SSH user's shell environment, then handed to `sudo` via `--preserve-env=<list>`. It never appears on any process command line, so even another user on the same box can't see it via `ps`. |
| **PaaS token on target disk** | Never written to disk on the target. The env vars live only in the ephemeral SSH session. |
| **SSH private key** | Marked `sensitive = true` in Terraform — Terraform will refuse to print it in plan/apply output. Prefer `file("~/.ssh/...")` in tfvars over a pasted heredoc. |
| **Installer integrity** | The installer is verified with a PKCS7 cryptographic signature against Dynatrace's root CA cert. If verification fails, the install aborts with no changes made. |
| **Production approval** | GitHub Actions `environment: production` blocks `terraform apply` until a configured reviewer approves in the GitHub UI. |
| **Audit trail** | Every apply creates a GitHub Actions run log you can re-read later. State changes show up as PR diffs. |
| **State file** | By default, Terraform stores state locally — fine for solo dev. For team use, configure a real backend (S3 / Azure Blob / GCS / Terraform Cloud) — examples are in `versions.tf`. |

### Recommended: harden sudo on every target

Out of the box, this repo needs the SSH user to be able to run `sudo bash ...`
without a password. You can lock this down much further by restricting sudo to
**only** run the install script:

Create `/etc/sudoers.d/dynatrace-deploy` on each target with:

```
Defaults:ubuntu env_keep += "DT_ENV_URL DT_PAAS_TOKEN DT_ARCH DT_INSTALLER_FLAGS DT_VERIFY_SIGNATURE DT_CERT_PATH DT_LOCAL_INSTALLER"
ubuntu ALL=(root) NOPASSWD: /bin/bash /tmp/install_oneagent.sh
```

Now if the SSH key is ever compromised, the attacker can only run the
installer — not arbitrary commands as root.

---

## 8. Operations and troubleshooting

### Uninstall OneAgent from a host

```bash
ssh user@host
sudo /opt/dynatrace/oneagent/agent/uninstall.sh
```

> This repo doesn't yet have a Terraform-managed uninstall flow. PRs welcome.

### "Pre-flight: verifying passwordless sudo ... failed"

The SSH user can't run `sudo` without a password.

**Fix:** add a NOPASSWD rule for your user:

```bash
echo "ubuntu ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ubuntu-nopasswd
```

Then re-run `terraform apply`.

### "Failed to download installer from <DT_URL>"

Walk through these in order:

1. **Can the target reach the URL?** From the target:
   ```bash
   curl -fsSL https://<DT_URL>
   ```
   If this fails, the target can't reach Dynatrace — see [Scenario D](#scenario-d--air-gapped-network-no-internet-from-targets).

2. **Is the PaaS token valid?** Log into your Dynatrace tenant → **Access
   management** → **Tokens**. Check the token is active and not expired.

3. **Does the token have the right scope?** The token needs the `PaaS
   integration` scope to download installers.

### "Installer signature verification FAILED"

This is a serious error — do not proceed.

Possible causes:
- The tenant URL is wrong.
- The certificate is stale or wrong.
- The installer was tampered with (unlikely but possible).

**Fix:**
1. If you set `local_cert_path`, make sure the cert you downloaded matches your tenant.
2. If you're in an air-gapped env, re-download both the cert and the installer
   from the same tenant and re-stage them.
3. If the error persists, contact your Dynatrace admin.

### "OneAgent service is active — skipping install."

**This is normal.** It means OneAgent is already running on this host and
the script is correctly avoiding a re-install.

To force a reinstall, edit `main.tf` and bump the `script_sha` trigger (any
change to the install script will do).

### Host shows up in Dynatrace but never sends data

Walk through these in order:

1. **Is the agent running on the host?**
   ```bash
   ssh user@host systemctl status oneagent
   # Expected: Active: active (running)
   ```

2. **Are there errors in the logs?**
   ```bash
   ssh user@host journalctl -u oneagent --since "10 min ago"
   ```

3. **Can the host reach the tenant URL on port 443?**
   ```bash
   ssh user@host curl -fsSL https://<DT_URL>
   ```

4. **Is the host registered?**
   From any machine with API access:
   ```bash
   curl -fsSL -H "Authorization: Api-Token <TOKEN>" \
     "https://<DT_URL>/api/v1/entities?entitySelector=type(HOST)"
   ```

### I added a host to `target_hosts` but Terraform says "no changes"

Checklist:
- Did you save `terraform.tfvars`?
- Is the host on a new line with proper quoting? E.g.
  `target_hosts = ["srv-a", "srv-b"]`, not `target_hosts = ["srv-a",]`.
- Did you run `terraform apply` (not just `plan`)?
- Run `terraform plan` first — it should show the new host as
  `null_resource.oneagent["new-host"]: Creating...`.

### "Error: Saved plan is stale"

Someone else ran Terraform (or the state file was modified externally)
between your `plan` and `apply`. **Just re-run `terraform plan`** and try again.

### Re-running a failed `apply`

Always safe. Terraform re-creates only the resources that failed.
Already-successful hosts are skipped (the install script's idempotency
check).

### I need to add a new host

```bash
# Edit terraform.tfvars
$EDITOR terraform.tfvars    # add the new host to target_hosts

terraform plan              # preview the change
terraform apply             # do it
```

If you're using GitHub Actions, push the change to a branch, open a PR (you'll
see the plan in the PR comments), merge, and approve the production gate.

### I need to remove a host

Remove the host from `target_hosts` and run `terraform apply`. The
`null_resource` for that host is destroyed, but OneAgent itself is **not**
uninstalled from the host — you'll need to
[uninstall it manually](#uninstall-oneagent-from-a-host) if you want it gone.

---

## 9. FAQ

**Q: Does this work on Windows servers?**
A: No — Dynatrace has a separate Windows installer and a different install
mechanism. This repo only handles Linux.

**Q: Can I use this for Kubernetes nodes?**
A: Not recommended. For Kubernetes, use the
[Dynatrace Operator + DynaKube](https://docs.dynatrace.com/docs/ingest-from/dynatrace-oneagent/installation-and-operation/kubernetes)
approach. It's purpose-built for cluster-aware monitoring.

**Q: Why not just `apt install dynatrace-oneagent` (or `yum install oneagent`)?**
A: Because installing the package is only half the job — the agent also
needs to know which tenant to report to. Our script handles both the
download AND the registration in one shot.

**Q: Why are we using `null_resource` and not a real Terraform provider?**
A: There is no Terraform provider for "install software on an arbitrary
SSH-reachable Linux host". `null_resource` + provisioners is the standard
idiom for this kind of task in Terraform.

**Q: Can I run this from my laptop when I'm at home?**
A: Only if your laptop can reach both your Dynatrace tenant (to download
the installer) and your target servers (or a bastion). For most on-prem
setups, the safest path is to use a self-hosted runner inside the network.

**Q: Where do I see what `apply_parallelism` should be?**
A: The default (10) is conservative and works for most teams. If you have
hundreds of hosts, you can bump it up. If your Dynatrace tenant has strict
rate limits and you see 429 errors, lower it. The right value depends on
your tenant's ingest limits — ask your Dynatrace admin if unsure.

**Q: Can I get a Slack/Teams notification when an apply fails?**
A: Yes — add a notification step (like `slackapi/slack-github-action`) to
`.github/workflows/deploy.yml`. Not configured out of the box because each
team has different chat tools.

**Q: The hosts in my `target_hosts` list have different CPU architectures
(some x86, some ARM). Can I run them in one apply?**
A: Not currently. The `arch` variable is global to one apply. Either run
two applies (one per architecture), or refactor `main.tf` to take a map of
`host → arch`. Noted as a future improvement.

**Q: Who do I ask if I'm stuck?**
A: Open an issue in this repo or ping the `#platform` channel on Slack.
Include the error message, the host you're trying to install on, and the
output of `terraform plan`.