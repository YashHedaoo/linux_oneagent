output "installed_hosts" {
  description = "Hosts that OneAgent was installed on in this run."
  value       = keys(null_resource.oneagent)
}

output "dynatrace_environment_url" {
  description = "Dynatrace tenant the agents report to."
  value       = var.dt_environment_url
}
