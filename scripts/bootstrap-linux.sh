#!/bin/bash
# OpenClaw + Ollama + MXC bootstrap for Ubuntu Linux (EC2 user_data or manual run).
# Linux MXC uses the bubblewrap backend by default (see microsoft/mxc).
set -euo pipefail

NODE_VERSION="${NODE_VERSION:?NODE_VERSION required}"
OPENCLAW_PACKAGE="${OPENCLAW_PACKAGE:?OPENCLAW_PACKAGE required}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:3b}"
OLLAMA_VERSION="${OLLAMA_VERSION:?OLLAMA_VERSION required}"
INSTALL_OLLAMA="${INSTALL_OLLAMA:-true}"
DISABLE_CONTROL_UI_DEVICE_AUTH="${DISABLE_CONTROL_UI_DEVICE_AUTH:-true}"
MXC_SDK_VERSION="${MXC_SDK_VERSION:-0.6.1}"
MXC_BACKEND="${MXC_BACKEND:-bubblewrap}"
INSTALL_MXC="${INSTALL_MXC:-true}"

BOOTSTRAP_ROOT="/var/log/openclaw-bootstrap"
OPENCLAW_ROOT="/opt/openclaw"
CONFIG_DIR="${OPENCLAW_ROOT}/config"
STATE_DIR="${CONFIG_DIR}/state"
WORKSPACE_DIR="${CONFIG_DIR}/workspace"
MXC_CONFIG_DIR="${CONFIG_DIR}/mxc"
LOG_FILE="${BOOTSTRAP_ROOT}/bootstrap.log"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
ENV_FILE="${CONFIG_DIR}/.env"
ACCESS_FILE="${OPENCLAW_ROOT}/gateway-access.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || echo "")"
REPO_CONFIG_MXC="${SCRIPT_DIR}/../config/mxc"

log() {
  local line="[$(date -Is)] $*"
  echo "$line" | tee -a "$LOG_FILE"
}

refresh_path() {
  export PATH="/usr/local/bin:${PATH}"
}

write_openclaw_env() {
  cat >/etc/profile.d/openclaw.sh <<EOF
export OPENCLAW_CONFIG_DIR="${CONFIG_DIR}"
export OPENCLAW_CONFIG_PATH="${CONFIG_FILE}"
export OPENCLAW_STATE_DIR="${STATE_DIR}"
export OPENCLAW_WORKSPACE_DIR="${WORKSPACE_DIR}"
export PATH="/usr/local/bin:\${PATH}"
EOF
  chmod 644 /etc/profile.d/openclaw.sh
  # shellcheck disable=SC1091
  source /etc/profile.d/openclaw.sh
}

generate_gateway_token() {
  if [[ -f "$ENV_FILE" ]]; then
    local existing
    existing="$(grep -E '^\s*OPENCLAW_GATEWAY_TOKEN=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
    if [[ -n "$existing" ]]; then
      echo "$existing"
      return
    fi
  fi
  openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
}

get_public_ip() {
  local ip=""
  for _ in $(seq 1 6); do
    ip="$(curl -fsS --connect-timeout 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
    sleep 5
  done
  echo "<instance-public-ip>"
}

install_node() {
  if command -v node >/dev/null 2>&1; then
    log "Node.js already installed: $(node --version)"
    return
  fi

  log "Installing Node.js v${NODE_VERSION}"
  local archive="/tmp/node-v${NODE_VERSION}-linux-x64.tar.xz"
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o "$archive"
  tar -xJf "$archive" -C /usr/local --strip-components=1
  rm -f "$archive"
  refresh_path
  log "Node version: $(node --version); npm: $(npm --version)"
}

install_openclaw() {
  log "Installing OpenClaw package: ${OPENCLAW_PACKAGE}"
  npm install -g "${OPENCLAW_PACKAGE}"
  refresh_path
  log "OpenClaw CLI: $(command -v openclaw)"
}

install_mxc_runtime() {
  log "Installing MXC Linux runtime for backend: ${MXC_BACKEND}"
  if [[ "${MXC_BACKEND}" == "lxc" ]]; then
    apt-get install -y lxc lxc-templates uidmap
  else
    apt-get install -y bubblewrap uidmap
  fi

  local userns
  userns="$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo unknown)"
  log "kernel.unprivileged_userns_clone=${userns}"
  if [[ "$userns" != "1" ]]; then
    log "WARNING: unprivileged user namespaces may be disabled; bubblewrap may fail"
  fi

  if [[ "${MXC_BACKEND}" == "bubblewrap" ]] && command -v bwrap >/dev/null 2>&1; then
    log "bubblewrap ready: $(command -v bwrap)"
  elif [[ "${MXC_BACKEND}" == "lxc" ]] && command -v lxc-create >/dev/null 2>&1; then
    log "lxc ready: $(command -v lxc-create)"
  else
    log "WARNING: MXC runtime binary not found on PATH after install"
  fi
}

install_mxc_sdk() {
  log "Installing @microsoft/mxc-sdk@${MXC_SDK_VERSION}"
  if npm install -g "@microsoft/mxc-sdk@${MXC_SDK_VERSION}"; then
    refresh_path
    log "MXC SDK installed at $(npm root -g)/@microsoft/mxc-sdk"
  else
    log "WARNING: npm install -g @microsoft/mxc-sdk@${MXC_SDK_VERSION} failed"
    return 1
  fi
}

resolve_lxc_exec() {
  local sdk_root
  sdk_root="$(npm root -g)/@microsoft/mxc-sdk"
  find "$sdk_root" -name lxc-exec -type f 2>/dev/null | head -1
}

install_mxc_configs() {
  log "Installing MXC sandbox profiles to ${MXC_CONFIG_DIR}"
  install -d -m 0750 -o ubuntu -g ubuntu "$MXC_CONFIG_DIR"

  if [[ -d "$REPO_CONFIG_MXC" ]]; then
    cp -a "$REPO_CONFIG_MXC/." "$MXC_CONFIG_DIR/"
    log "Copied MXC profiles from repository: $REPO_CONFIG_MXC"
    return
  fi

  cat >"${MXC_CONFIG_DIR}/linux-bubblewrap-lab.json" <<'EOF'
{
  "version": "0.6.0-alpha",
  "platform": "linux",
  "containment": "bubblewrap",
  "process": {
    "commandLine": "echo 'OpenClaw tool sandbox smoke test'",
    "cwd": "/tmp",
    "timeout": 30000
  },
  "filesystem": {
    "readwritePaths": ["/tmp/openclaw-sandbox"],
    "readonlyPaths": ["/usr", "/bin", "/lib", "/lib64"],
    "deniedPaths": ["/etc/shadow", "/root"]
  },
  "network": {
    "defaultPolicy": "block"
  }
}
EOF

  cat >"${MXC_CONFIG_DIR}/linux-openclaw-tools.json" <<'EOF'
{
  "version": "0.6.0-alpha",
  "platform": "linux",
  "containment": "bubblewrap",
  "process": {
    "commandLine": "PLACEHOLDER_COMMAND",
    "cwd": "/tmp/openclaw-sandbox",
    "timeout": 120000
  },
  "filesystem": {
    "readwritePaths": ["/tmp/openclaw-sandbox", "/opt/openclaw/config/workspace"],
    "readonlyPaths": ["/usr", "/bin", "/lib", "/lib64", "/opt/openclaw/config/mxc"],
    "deniedPaths": ["/etc/shadow", "/root", "/home/ubuntu/.ssh"]
  },
  "network": {
    "defaultPolicy": "block"
  }
}
EOF
  log "Wrote embedded MXC profiles (repo config/mxc not available on host)"
}

verify_mxc() {
  local lxc_exec smoke_config
  lxc_exec="$(resolve_lxc_exec || true)"
  if [[ -z "$lxc_exec" ]]; then
    log "WARNING: MXC verify skipped — lxc-exec not found"
    return 1
  fi

  smoke_config="${MXC_CONFIG_DIR}/linux-bubblewrap-lab.json"
  if [[ ! -f "$smoke_config" ]]; then
    log "WARNING: MXC verify skipped — missing $smoke_config"
    return 1
  fi

  install -d -m 1777 /tmp/openclaw-sandbox
  log "Running MXC bubblewrap smoke test via $lxc_exec"
  if "$lxc_exec" "$smoke_config" >>"$LOG_FILE" 2>&1; then
    log "MXC smoke test passed"
    return 0
  fi
  log "WARNING: MXC smoke test failed — see bootstrap log"
  return 1
}

install_mxc() {
  if [[ "${INSTALL_MXC}" != "true" ]]; then
    log "Skipping MXC install (INSTALL_MXC=${INSTALL_MXC})"
    return
  fi

  install_mxc_runtime
  install_mxc_sdk || true
  install_mxc_configs
  verify_mxc || true
}

install_ollama() {
  log "Installing Ollama v${OLLAMA_VERSION}"
  apt-get install -y zstd

  local archive="/tmp/ollama-linux-amd64.tar.zst"
  curl -fsSL "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst" -o "$archive"
  tar --zstd -xf "$archive" -C /usr/local
  rm -f "$archive"
  chmod +x /usr/local/bin/ollama

  install -d -m 0755 /etc/systemd/system
  cat >/etc/systemd/system/ollama.service <<'EOF'
[Unit]
Description=Ollama local LLM server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=5
Environment=OLLAMA_HOST=127.0.0.1:11434

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ollama
  systemctl start ollama

  log "Waiting for Ollama API..."
  local deadline=$((SECONDS + 300))
  until curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; do
    if (( SECONDS > deadline )); then
      log "ERROR: Ollama API did not become ready"
      exit 1
    fi
    sleep 5
  done
  log "Ollama serve is ready; scheduling background model pull"

  cat >/usr/local/bin/openclaw-pull-ollama-model.sh <<PULL
#!/bin/bash
set -euo pipefail
LOG="${BOOTSTRAP_ROOT}/ollama-pull.log"
echo "\$(date -Is) Starting Ollama pull for ${OLLAMA_MODEL}" >> "\$LOG"
/usr/local/bin/ollama pull "${OLLAMA_MODEL}" >> "\$LOG" 2>&1
echo "\$(date -Is) Ollama pull finished: ${OLLAMA_MODEL}" >> "\$LOG"
PULL
  chmod +x /usr/local/bin/openclaw-pull-ollama-model.sh

  cat >/etc/systemd/system/ollama-pull.service <<EOF
[Unit]
Description=Pull Ollama model ${OLLAMA_MODEL}
After=ollama.service
Requires=ollama.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/openclaw-pull-ollama-model.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ollama-pull
  systemctl start ollama-pull &
}

write_openclaw_config() {
  local gateway_token="$1"
  local public_ip="$2"

  install -d -m 0750 -o ubuntu -g ubuntu "$CONFIG_DIR" "$STATE_DIR" "$WORKSPACE_DIR"

  local origins
  origins="$(jq -n \
    --arg port "$GATEWAY_PORT" \
    --arg public_ip "$public_ip" \
    '[
      "http://localhost:\($port)",
      "http://127.0.0.1:\($port)"
    ] + (if $public_ip != "<instance-public-ip>" then ["http://\($public_ip):\($port)"] else [] end)'
  )"

  if [[ "$public_ip" != "<instance-public-ip>" ]]; then
    log "Control UI allowedOrigins includes public IP: http://${public_ip}:${GATEWAY_PORT}"
  else
    log "WARNING: Public IP unavailable; update allowedOrigins after instance has an Elastic IP"
  fi

  local disable_device_auth="false"
  if [[ "${DISABLE_CONTROL_UI_DEVICE_AUTH}" == "true" ]]; then
    disable_device_auth="true"
    log "Control UI device auth disabled for plain HTTP lab access (security downgrade)"
  fi

  if [[ "${INSTALL_OLLAMA}" == "true" ]]; then
    jq -n \
      --argjson port "$GATEWAY_PORT" \
      --arg workspace "$WORKSPACE_DIR" \
      --arg model "$OLLAMA_MODEL" \
      --argjson origins "$origins" \
      --argjson disable_device_auth "$disable_device_auth" \
      '{
        gateway: {
          mode: "local",
          port: $port,
          bind: "lan",
          auth: { mode: "token" },
          reload: { mode: "hybrid" },
          controlUi: {
            allowedOrigins: $origins,
            allowInsecureAuth: true,
            dangerouslyDisableDeviceAuth: $disable_device_auth
          }
        },
        agents: {
          defaults: {
            workspace: $workspace,
            model: { primary: ("ollama/" + $model) }
          }
        },
        models: {
          providers: {
            ollama: {
              baseUrl: "http://127.0.0.1:11434",
              apiKey: "ollama-local",
              api: "ollama",
              timeoutSeconds: 300,
              models: [
                {
                  id: $model,
                  name: $model,
                  params: { keep_alive: "15m" }
                }
              ]
            }
          }
        }
      }' >"$CONFIG_FILE"
  else
    jq -n \
      --argjson port "$GATEWAY_PORT" \
      --arg workspace "$WORKSPACE_DIR" \
      --argjson origins "$origins" \
      --argjson disable_device_auth "$disable_device_auth" \
      '{
        gateway: {
          mode: "local",
          port: $port,
          bind: "lan",
          auth: { mode: "token" },
          reload: { mode: "hybrid" },
          controlUi: {
            allowedOrigins: $origins,
            allowInsecureAuth: true,
            dangerouslyDisableDeviceAuth: $disable_device_auth
          }
        },
        agents: {
          defaults: {
            workspace: $workspace
          }
        }
      }' >"$CONFIG_FILE"
  fi

  chown -R ubuntu:ubuntu "$OPENCLAW_ROOT"

  cat >"$ENV_FILE" <<EOF
OPENCLAW_GATEWAY_TOKEN=${gateway_token}
OPENCLAW_GATEWAY_PORT=${GATEWAY_PORT}
EOF
  if [[ "${INSTALL_OLLAMA}" == "true" ]]; then
    echo "OLLAMA_API_KEY=ollama-local" >>"$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
  chown ubuntu:ubuntu "$ENV_FILE"

  local model_line="Model: configure cloud provider in ${ENV_FILE}"
  if [[ "${INSTALL_OLLAMA}" == "true" ]]; then
    model_line="Ollama model: ollama/${OLLAMA_MODEL} (local, http://127.0.0.1:11434)"
  fi

  cat >"$ACCESS_FILE" <<EOF
OpenClaw gateway access
=======================

Control UI:  http://${public_ip}:${GATEWAY_PORT}
WebSocket:   ws://${public_ip}:${GATEWAY_PORT}

Gateway token (paste in Control UI Connect):
${gateway_token}

${model_line}

Config dir:  ${CONFIG_DIR}
Env file:    ${ENV_FILE}

1. Open the Control UI URL above from your browser and paste the token
2. If using Ollama, wait for model pull: tail -f ${BOOTSTRAP_ROOT}/ollama-pull.log
3. Restart gateway: sudo systemctl restart openclaw-gateway
4. Verify MXC: sudo bash /opt/openclaw/scripts/verify-mxc-linux.sh (if installed)
5. MXC profiles: ${MXC_CONFIG_DIR} (bubblewrap backend on Linux)
6. Wire OpenClaw tool execution to @microsoft/mxc-sdk per config/mxc README

Note: Ollama listens on localhost only (port 11434 is not exposed publicly).
MXC is alpha preview; do not treat profiles as production security boundaries.
EOF
  chmod 600 "$ACCESS_FILE"
  chown ubuntu:ubuntu "$ACCESS_FILE"
}

install_openclaw_gateway_service() {
  cat >/etc/systemd/system/openclaw-gateway.service <<EOF
[Unit]
Description=OpenClaw gateway
After=network-online.target ollama.service
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
EnvironmentFile=${ENV_FILE}
Environment=OPENCLAW_CONFIG_DIR=${CONFIG_DIR}
Environment=OPENCLAW_CONFIG_PATH=${CONFIG_FILE}
Environment=OPENCLAW_STATE_DIR=${STATE_DIR}
Environment=OPENCLAW_WORKSPACE_DIR=${WORKSPACE_DIR}
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/openclaw gateway --bind lan --port ${GATEWAY_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable openclaw-gateway
  systemctl restart openclaw-gateway
}

main() {
  install -d -m 0755 "$BOOTSTRAP_ROOT" "$OPENCLAW_ROOT"
  touch "$LOG_FILE"

  log "Starting OpenClaw + Ollama + MXC Linux bootstrap"
  log "Pinned versions: Node v${NODE_VERSION}, MXC SDK ${MXC_SDK_VERSION}, OpenClaw ${OPENCLAW_PACKAGE}, Ollama v${OLLAMA_VERSION}, backend ${MXC_BACKEND}"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl jq openssl

  install_node
  install_mxc
  install_openclaw
  write_openclaw_env

  install -d -m 0755 "${OPENCLAW_ROOT}/scripts"
  if [[ -f "${SCRIPT_DIR}/verify-mxc-linux.sh" ]]; then
    install -m 0755 "${SCRIPT_DIR}/verify-mxc-linux.sh" "${OPENCLAW_ROOT}/scripts/verify-mxc-linux.sh"
    log "Installed verify-mxc-linux.sh to ${OPENCLAW_ROOT}/scripts/"
  fi

  if [[ "${INSTALL_OLLAMA}" == "true" ]]; then
    install_ollama
  fi

  local gateway_token public_ip
  gateway_token="$(generate_gateway_token)"
  public_ip="$(get_public_ip)"
  if [[ "$public_ip" == "<instance-public-ip>" ]]; then
    sleep 10
    public_ip="$(get_public_ip)"
  fi

  write_openclaw_config "$gateway_token" "$public_ip"
  install_openclaw_gateway_service

  log "Bootstrap finished. Gateway access: ${ACCESS_FILE}"
}

main "$@"
