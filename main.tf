# Installs Dynatrace OneAgent on each already-existing Linux host over SSH.
#
# Terraform does not "install" software itself — this null_resource opens an SSH
# connection to each host, uploads the install script, and runs it as root. The
# script downloads the OneAgent installer from your Dynatrace tenant (using the
# PaaS token) and runs it. See scripts/install_oneagent.sh.

resource "null_resource" "oneagent" {
  for_each = toset(var.target_hosts)

  # Re-run the provisioners when any of these change (new host, changed flags,
  # or an edited install script).
  triggers = {
    host             = each.value
    installer_flags  = var.installer_flags
    arch             = var.arch
    verify_signature = tostring(var.verify_signature)
    script_sha       = filesha256("${path.module}/scripts/install_oneagent.sh")
  }

  connection {
    type        = "ssh"
    host        = each.value
    user        = var.ssh_user
    private_key = var.ssh_private_key
    port        = var.ssh_port
    timeout     = "5m"
  }

  # Push the install script to the host.
  provisioner "file" {
    source      = "${path.module}/scripts/install_oneagent.sh"
    destination = "/tmp/install_oneagent.sh"
  }

  # Run it as root. Secrets are passed as environment variables on the sudo
  # command line (sudo permits VAR=value assignments for the command env) so
  # they are not written into the script file on disk.
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install_oneagent.sh",
      join(" ", [
        "sudo",
        "DT_ENV_URL='${var.dt_environment_url}'",
        "DT_PAAS_TOKEN='${var.dt_paas_token}'",
        "DT_ARCH='${var.arch}'",
        "DT_INSTALLER_FLAGS='${var.installer_flags}'",
        "DT_VERIFY_SIGNATURE='${var.verify_signature}'",
        "bash /tmp/install_oneagent.sh",
      ]),
      "rm -f /tmp/install_oneagent.sh",
    ]
  }
}
