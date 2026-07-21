variable "dt_environment_url" {
  description = "Dynatrace environment (tenant) URL, e.g. https://abc12345.live.dynatrace.com or a Managed/ActiveGate URL. No trailing /api."
  type        = string
}

variable "dt_paas_token" {
  description = "Dynatrace PaaS token used to download the OneAgent installer."
  type        = string
  sensitive   = true
}

variable "target_hosts" {
  description = "List of existing Linux hosts (IP or DNS) to install OneAgent on."
  type        = list(string)
}

variable "ssh_user" {
  description = "SSH user for the target hosts. Must have passwordless sudo rights."
  type        = string
  default     = "ubuntu"
}

variable "ssh_private_key" {
  description = "PEM-encoded SSH private key contents used to authenticate to the target hosts. Prefer file() in tfvars so the key never lives in tfvars plaintext."
  type        = string
  sensitive   = true
}

variable "ssh_port" {
  description = "SSH port on the target hosts."
  type        = number
  default     = 22
}

variable "arch" {
  description = "Target CPU architecture for the installer: x86, arm, ppcle, or s390. Defaults to x86_64-compatible. Use a separate run (or per-host list in scripts/) for mixed fleets."
  type        = string
  default     = "x86"

  validation {
    condition     = contains(["x86", "arm", "ppcle", "s390"], var.arch)
    error_message = "arch must be one of: x86, arm, ppcle, s390."
  }
}

variable "installer_flags" {
  description = "Flags passed to the OneAgent installer script."
  type        = string
  default     = "--set-infra-only=false --set-app-log-content-access=true"
}

variable "verify_signature" {
  description = "Verify the installer's PKCS7 signature against the Dynatrace root cert before running it. Strongly recommended for production."
  type        = bool
  default     = true
}

# --- Air-gapped / offline support (optional) ------------------------------

variable "local_cert_path" {
  description = "Path to a local copy of the Dynatrace root cert (dt-root.cert.pem). Use this when targets cannot reach ca.dynatrace.com. Set verify_signature=true to actually use it."
  type        = string
  default     = null
}

variable "local_installer_path" {
  description = "Path to a pre-downloaded OneAgent installer (Dynatrace-OneAgent-Linux.sh). Use this for fully air-gapped networks where the install URL is not reachable. If unset, the script downloads from DT_ENV_URL."
  type        = string
  default     = null
}

# --- SSH connectivity tuning ---------------------------------------------

variable "ssh_timeout" {
  description = "Per-host SSH timeout for the install operation."
  type        = string
  default     = "5m"
}

variable "apply_parallelism" {
  description = "Max hosts to install on concurrently. Tune down if your Dynatrace tenant or network is constrained; tune up for faster rollouts."
  type        = number
  default     = 10
}

# --- On-Premises Bastion / Jump Host Variables (Optional) ----------------

variable "bastion_host" {
  description = "Optional IP address or hostname of an SSH Bastion / Jump host used to access private on-prem servers."
  type        = string
  default     = null
}

variable "bastion_user" {
  description = "Optional SSH username for the Bastion host. Defaults to ssh_user if not specified."
  type        = string
  default     = null
}

variable "bastion_private_key" {
  description = "Optional PEM-encoded SSH private key for the Bastion host. Defaults to ssh_private_key if not specified."
  type        = string
  sensitive   = true
  default     = null
}

variable "bastion_port" {
  description = "Optional SSH port for the Bastion host."
  type        = number
  default     = 22
}