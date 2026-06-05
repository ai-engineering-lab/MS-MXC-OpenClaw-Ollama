# MXC sandbox profiles (Linux)

Sample [Microsoft Execution Containers (MXC)](https://github.com/microsoft/mxc) policy configs for **Ubuntu Linux** using the **bubblewrap** backend (default on Linux).

| File | Purpose |
| ---- | ------- |
| `linux-bubblewrap-lab.json` | Minimal smoke-test sandbox (network blocked) |
| `linux-openclaw-tools.json` | Template for OpenClaw agent tool execution (replace `PLACEHOLDER_COMMAND`) |

## Prerequisites on the host

- `bubblewrap` (`bwrap`) installed
- `@microsoft/mxc-sdk` npm package (bundles `lxc-exec` on Linux)
- User namespaces enabled (`/proc/sys/kernel/unprivileged_userns_clone` = `1`)

## Smoke test

After bootstrap or manual SDK install:

```bash
./scripts/verify-mxc-linux.sh
```

Or directly:

```bash
ARCH=x64   # or arm64 on Graviton instances
LXC_EXEC="$(npm root -g)/@microsoft/mxc-sdk/bin/${ARCH}/lxc-exec"
"$LXC_EXEC" config/mxc/linux-bubblewrap-lab.json
```

## OpenClaw integration

OpenClaw runs the gateway on the host; MXC sandboxes **tool/code execution** invoked by the agent. Wire your OpenClaw tool runner to call `@microsoft/mxc-sdk` (`spawnSandboxFromConfig`) with a policy derived from these profiles. See [MXC SDK README](https://github.com/microsoft/mxc/tree/main/sdk) and [bubblewrap backend docs](https://github.com/microsoft/mxc/blob/main/docs/bwrap-support/bubblewrap-backend.md).

> Alpha preview — do not treat these profiles as production security boundaries.
