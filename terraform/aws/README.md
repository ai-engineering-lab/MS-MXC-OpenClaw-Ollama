# AWS Linux (OpenClaw + Ollama + MXC)

Terraform module that provisions **one Ubuntu 24.04 EC2 instance** with **OpenClaw**, **Ollama**, and **Microsoft Execution Containers (MXC)** on Linux.

> **Code-only for now** — this module is ready in-repo; run `terraform apply` when you are ready to deploy to AWS.

For the Windows **processcontainer** MXC stack, use [`../`](../) (Azure Windows 11).

## Architecture

```
Browser → OpenClaw Gateway → Agent → Ollama (llama3.2:1b)  ← local inference
                               └→ MXC bubblewrap            ← tool/code sandbox (Linux)
```

| Layer | Role |
| ----- | ---- |
| **OpenClaw** | Agent runtime and gateway Control UI |
| **Ollama + llama3.2:1b** | Local LLM inference (tool-capable) |
| **MXC (bubblewrap)** | Policy-driven Linux sandbox via `@microsoft/mxc-sdk` (built from [ms-mxc](https://github.com/ai-engineering-lab/ms-mxc)) |
| **Ubuntu 24.04 LTS** | EC2 host OS |
| **AWS EC2** | Terraform-provisioned compute |

Ollama listens on **127.0.0.1:11434 only** — not exposed in the security group.

## MXC on Linux

[Microsoft MXC](https://github.com/microsoft/mxc) supports Linux with the **bubblewrap** backend (default) or **lxc**. Bootstrap installs:

- `bubblewrap` + `uidmap`
- MXC built from [ai-engineering-lab/ms-mxc](https://github.com/ai-engineering-lab/ms-mxc) (Rust + TypeScript SDK → global `@microsoft/mxc-sdk`)
- Sample profiles in `/opt/openclaw/config/mxc/` (from [`config/mxc/`](../../config/mxc/))

Verify after bootstrap:

```bash
./scripts/verify-mxc-linux.sh
# or on the instance:
bash /opt/openclaw/scripts/verify-mxc-linux.sh
```

> Alpha preview — do not treat MXC profiles as production security boundaries.

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

Allow **20–40 minutes** on first boot (Node/npm install, MXC smoke test, Ollama model pull, gateway start).

## Access

1. SSH: `terraform output -raw ssh_command`
2. On instance: `cat /opt/openclaw/gateway-access.txt`
3. Open Control UI in browser (port **18789**), paste gateway token

## Defaults

| Setting | Default |
| ------- | ------- |
| OS | Ubuntu 24.04 LTS (Noble) |
| Instance | `c6i.2xlarge` |
| Root volume | 100 GB gp3, encrypted |
| Region | `ca-central-1` |
| SSH user | `ubuntu` |
| Gateway port | `18789` |
| Ollama model | `llama3.2:1b` |
| MXC backend | `bubblewrap` |
| MXC source | [ai-engineering-lab/ms-mxc](https://github.com/ai-engineering-lab/ms-mxc) |
| MXC SDK | `@microsoft/mxc-sdk` (built at bootstrap) |

## Destroy

```bash
terraform destroy
```

## Security notes

- Restrict `allowed_ssh_cidr` and `allowed_gateway_cidr` to your IP
- Do not commit `terraform.tfvars` or `terraform.tfstate`
- MXC is alpha preview; pin SDK versions and follow [microsoft/mxc](https://github.com/microsoft/mxc) guidance
