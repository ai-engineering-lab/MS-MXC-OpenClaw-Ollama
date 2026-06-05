output "public_ip" {
  description = "Elastic IP of the OpenClaw Linux instance."
  value       = aws_eip.openclaw.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.openclaw.id
}

output "openclaw_gateway_url" {
  description = "OpenClaw Control UI URL once bootstrap completes."
  value       = "http://${aws_eip.openclaw.public_ip}:${var.openclaw_gateway_port}"
}

output "ssh_command" {
  description = "SSH to the instance (requires matching private key for ec2_key_name)."
  value       = "ssh -i ~/.ssh/${var.ec2_key_name}.pem ubuntu@${aws_eip.openclaw.public_ip}"
}

output "bootstrap_log_path" {
  description = "Bootstrap log path on the instance."
  value       = "/var/log/openclaw-bootstrap/bootstrap.log"
}

output "gateway_access_path" {
  description = "Gateway URL and token file on the instance."
  value       = "/opt/openclaw/gateway-access.txt"
}

output "pinned_dependencies" {
  description = "Pinned runtime dependency versions passed to bootstrap."
  value = {
    mxc_sdk           = var.install_mxc ? var.mxc_sdk_version : null
    mxc_backend       = var.install_mxc ? var.mxc_backend : null
    openclaw          = var.openclaw_version
    openclaw_npm_spec = var.openclaw_npm_package
    node              = var.node_version
    ollama            = var.ollama_version
    ollama_model      = var.install_ollama ? var.ollama_model : null
    platform          = "linux (MXC bubblewrap/lxc)"
  }
}

output "next_steps" {
  description = "Post-deploy steps for the Linux instance."
  value       = <<-EOT
    1. SSH to the instance and tail /var/log/openclaw-bootstrap/bootstrap.log
    2. Read gateway URL + token from /opt/openclaw/gateway-access.txt
    3. Open the Control UI at the gateway URL from your browser and paste the token
    4. When install_ollama is true, confirm model pull: tail -f /var/log/openclaw-bootstrap/ollama-pull.log
    5. Verify MXC: bash /opt/openclaw/scripts/verify-mxc-linux.sh (or scripts/verify-mxc-linux.sh from repo)
    6. MXC profiles on host: /opt/openclaw/config/mxc (bubblewrap backend)
  EOT
}

output "verify_commands" {
  description = "Commands to verify bootstrap on the instance."
  value       = <<-EOT
    sudo tail -f /var/log/openclaw-bootstrap/bootstrap.log
    sudo systemctl status ollama openclaw-gateway
    ollama list
    bash /opt/openclaw/scripts/verify-mxc-linux.sh
    curl -s http://127.0.0.1:${var.openclaw_gateway_port}/ | head
  EOT
}
