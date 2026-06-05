# AWS Linux (OpenClaw + Ollama)

Terraform module that provisions **one Ubuntu 24.04 EC2 instance** with **OpenClaw** and **Ollama**. This is the **Linux platform** path — **MXC is not available** (Windows 11 only).

For the full **MXC + OpenClaw** stack, use [`../`](../) (Azure Windows 11).

## Architecture

```
Browser → OpenClaw Gateway → Agent → Ollama (llama3.2:3b)  ← local inference
                               └→ (no MXC on Linux)
```

| Layer | Role |
| ----- | ---- |
| **OpenClaw** | Agent runtime and gateway Control UI |
| **Ollama + llama3.2:3b** | Local LLM inference |
| **Ubuntu 24.04 LTS** | EC2 host OS |
| **AWS EC2** | Terraform-provisioned compute |

Ollama listens on **127.0.0.1:11434 only** — not exposed in the security group.

## Prerequisites

- Terraform **>= 1.5**
- AWS credentials (`aws configure` or environment variables)
- EC2 **key pair** in the target region
- **SSH private key** at `~/.ssh/<ec2_key_name>.pem` (default path used in outputs)

## Quick start

```bash
cd terraform/aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set ec2_key_name and restrict CIDRs

terraform init
terraform plan
terraform apply
```

After apply:

```bash
terraform output openclaw_gateway_url
terraform output -raw next_steps
```

Allow **20–40 minutes** on first boot (Node/npm install, Ollama model pull, gateway start).

## Access

1. SSH: `terraform output -raw ssh_command`
2. On instance: `cat /opt/openclaw/gateway-access.txt`
3. Open Control UI in browser (port **18789**), paste gateway token

## Defaults

| Setting | Default |
| ------- | ------- |
| OS | Ubuntu 24.04 LTS (Noble) |
| Instance | `t3.xlarge` |
| Root volume | 100 GB gp3, encrypted |
| Region | `ca-central-1` |
| SSH user | `ubuntu` |
| Gateway port | `18789` |
| Ollama model | `llama3.2:3b` |

## Destroy

```bash
terraform destroy
```

## Security notes

- Restrict `allowed_ssh_cidr` and `allowed_gateway_cidr` to your IP
- Do not commit `terraform.tfvars` or `terraform.tfstate`
- Linux deployment has **no MXC sandboxing** — lab/sandbox use only
