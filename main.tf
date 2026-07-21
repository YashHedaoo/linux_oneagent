# Installs Dynatrace OneAgent on each already-existing Linux host over SSH.
#
# Terraform does not "install" software itself — this null_resource opens an SSH
# connection to each host, uploads the install script, and runs it as root. The
# script downloads (or uses a local) OneAgent installer from your Dynatrace
# tenant (using the PaaS token) and runs it. See scripts/install_oneagent.sh.

locals {
  # Map of variable name -> env var name expected by the install script.
  # Secrets are exported in the SSH user's shell and passed through sudo with
  # `--preserve-env=<list>` so they never appear on the sudo command line.
  install_env_keys = [
    "DT_ENV_URL",
    "DT_PAAS_TOKEN",
    "DT_ARCH",
    "DT_INSTALLER_FLAGS",
    "DT_VERIFY_SIGNATURE",
    "DT_CERT_PATH",
    "DT_LOCAL_INSTALLER",
  ]

  # Env values that get exported in the SSH user's shell and then carried
  # across the sudo boundary. Built once, referenced by the provisioner.
  ssh_env_exports = join("\n", [
    "export DT_ENV_URL=${jsonencode(var.dt_environment_url)}",
    "export DT_PAAS_TOKEN=${jsonencode(var.dt_paas_token)}",
    "export DT_ARCH=${jsonencode(var.arch)}",
    "export DT_INSTALLER_FLAGS=${jsonencode(var.installer_flags)}",
    "export DT_VERIFY_SIGNATURE=${jsonencode(tostring(var.verify_signature))}",
    "export DT_CERT_PATH=${jsonencode(var.local_cert_path != null ? "/tmp/dt-root.cert.pem" : "")}",
    "export DT_LOCAL_INSTALLER=${jsonencode(var.local_installer_path != null ? "/tmp/Dynatrace-OneAgent-Linux.sh" : "")}",
  ])

  # Comma-separated list for `sudo --preserve-env=...` (no spaces).
  sudo_preserve_args = join(",", local.install_env_keys)
}

resource "null_resource" "oneagent" {
  for_each = toset(var.target_hosts)

  # Re-run the provisioners when any of these change (new host, changed flags,
  # an edited install script, or a rotated cert/installer).
  triggers = {
    host             = each.value
    installer_flags  = var.installer_flags
    arch             = var.arch
    verify_signature = tostring(var.verify_signature)
    script_sha       = filesha256("${path.module}/scripts/install_oneagent.sh")
    cert_sha         = var.local_cert_path != null ? filesha256(var.local_cert_path) : ""
    installer_sha    = var.local_installer_path != null ? filesha256(var.local_installer_path) : ""
  }

  connection {
    type        = "ssh"
    host        = each.value
    user        = var.ssh_user
    private_key = var.ssh_private_key
    port        = var.ssh_port
    timeout     = var.ssh_timeout

    bastion_host        = var.bastion_host
    bastion_user        = var.bastion_user != null ? var.bastion_user : var.ssh_user
    bastion_private_key = var.bastion_private_key != null ? var.bastion_private_key : var.ssh_private_key
    bastion_port        = var.bastion_port
  }

  # ---- Pre-flight -------------------------------------------------------
  # Fail fast with a clear error if the SSH user can't sudo non-interactively.
  provisioner "remote-exec" {
    inline = [
      "echo '==> Pre-flight: verifying passwordless sudo on ${each.value}'",
      "sudo -n -v && echo '==> Pre-flight OK'",
    ]
  }

  # ---- Push install script ----------------------------------------------
  provisioner "file" {
    source      = "${path.module}/scripts/install_oneagent.sh"
    destination = "/tmp/install_oneagent.sh"
  }

  # ---- Optional: push local cert (air-gapped signature verify) -----------
  provisioner "file" {
    source      = var.local_cert_path != null ? var.local_cert_path : "${path.module}/scripts/install_oneagent.sh"
    destination = "/tmp/dt-root.cert.pem"
  }

  # ---- Optional: push local installer (fully air-gapped) ----------------
  provisioner "file" {
    source      = var.local_installer_path != null ? var.local_installer_path : "${path.module}/scripts/install_oneagent.sh"
    destination = "/tmp/Dynatrace-OneAgent-Linux.sh"
  }

  # ---- Run installer as root --------------------------------------------
  # Secrets are exported in the SSH user's shell (visible only to that user
  # and root on the target) and re-exported into sudo via --preserve-env,
  # so the PaaS token never appears on any process command line.
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /tmp/install_oneagent.sh",
      local.ssh_env_exports,
      "sudo --preserve-env=${local.sudo_preserve_args} bash /tmp/install_oneagent.sh",
      "unset ${join(" ", local.install_env_keys)}",
      "rm -f /tmp/install_oneagent.sh /tmp/dt-root.cert.pem /tmp/Dynatrace-OneAgent-Linux.sh",
    ]
  }
}