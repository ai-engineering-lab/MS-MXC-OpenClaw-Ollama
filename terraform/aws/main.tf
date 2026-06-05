provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "MS-MXC-OpenClaw-Ollama"
      Platform    = "linux"
      Application = "OpenClaw"
      ManagedBy   = "terraform"
      Owner       = var.owner_tag
    }
  }
}

locals {
  bootstrap_env = <<-ENV
export NODE_VERSION="${var.node_version}"
export OPENCLAW_PACKAGE="${var.openclaw_npm_package}"
export GATEWAY_PORT="${var.openclaw_gateway_port}"
export OLLAMA_MODEL="${var.ollama_model}"
export OLLAMA_VERSION="${var.ollama_version}"
export INSTALL_OLLAMA="${lower(tostring(var.install_ollama))}"
export DISABLE_CONTROL_UI_DEVICE_AUTH="${lower(tostring(var.openclaw_control_ui_disable_device_auth))}"
export MXC_GIT_REPO="${var.mxc_git_repo}"
export MXC_GIT_REF="${var.mxc_git_ref}"
export MXC_BACKEND="${var.mxc_backend}"
export INSTALL_MXC="${lower(tostring(var.install_mxc))}"
ENV

  user_data_plain = join("\n", [
    "#!/bin/bash",
    "set -euo pipefail",
    "exec > >(tee -a /var/log/openclaw-ec2-user-data.log) 2>&1",
    local.bootstrap_env,
    file("${path.module}/../../scripts/bootstrap-linux.sh"),
  ])
}

data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "${var.aws_region}a"
  default_for_az    = true
}

resource "aws_security_group" "openclaw" {
  name_prefix = "${var.name_prefix}-"
  description = "OpenClaw Linux EC2 (SSH + gateway public; Ollama localhost only)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
  }

  ingress {
    description = "OpenClaw gateway Control UI"
    from_port   = var.openclaw_gateway_port
    to_port     = var.openclaw_gateway_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_gateway_cidr
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids = [aws_security_group.openclaw.id]
  key_name               = var.ec2_key_name
  user_data                   = base64gzip(local.user_data_plain)
  user_data_replace_on_change = false

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.name_prefix}-root"
    }
  }

  tags = {
    Name = var.name_prefix
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "openclaw" {
  instance = aws_instance.openclaw.id
  domain   = "vpc"

  tags = {
    Name = "${var.name_prefix}-eip"
  }

  depends_on = [aws_instance.openclaw]
}

resource "aws_cloudwatch_log_group" "openclaw" {
  name              = "/aws/ec2/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.name_prefix}-logs"
  }
}
