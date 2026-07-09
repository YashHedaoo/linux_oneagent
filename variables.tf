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
  description = "SSH user for the target hosts. Must be able to run sudo without an interactive password."
  type        = string
  default     = "ubuntu"
}

variable "ssh_private_key" {
  description = "PEM-encoded SSH private key contents used to authenticate to the target hosts."
  type        = string
  sensitive   = true
}

variable "ssh_port" {
  description = "SSH port on the target hosts."
  type        = number
  default     = 22
}

variable "arch" {
  description = "Target CPU architecture for the installer: x86, arm, ppcle, or s390."
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
  description = "Verify the installer's signature against Dynatrace's root cert before running it."
  type        = bool
  default     = true
}
