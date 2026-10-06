# Setup: Build and Operate Foundry Agents without Docker

[SETUP.md](./SETUP.md) documents the repository dev container as the recommended path, mainly for
classroom consistency. Nothing in the lab code actually requires Docker: the dev container is a
Python 3.14 image plus two optional sidecar services (Redis, an Azurite Blob emulator) and a few
CLI tools, all of which are independently installable. Hosted-agent deploys (`azd up`) use
`--dep-resolution remote_build`, so Foundry builds the container server-side from an uploaded ZIP —
no local Docker daemon is involved there either.

Use this path on a personal machine where Docker Desktop isn't available or wanted (for example, a
corporate laptop or an MSDN sandbox subscription).

## What you actually need

| Devcontainer piece | Native equivalent | Required? |
|---|---|---|
| Python 3.14 base image | Python 3.14 interpreter + venv | Yes |
| `azure-cli` feature | `az` CLI | Yes |
| `azd` feature | `azd` 1.34.2+ | Only for hosted-agent deploy steps (`azd up`) |
| `github-cli`, `powershell` features | `gh`, `pwsh` | Only if you use those specific steps |
| Redis container | Native `redis-server`, or skip | Only for generic shared-store configs / the Lab 4 infra template. Labs 1-3 and Stretch 6 don't use it |
| Azurite container | Real Azure Blob Storage, or skip | Only if you want local Blob testing. Point `MARKETPLACE_BLOB_STORAGE_URL` at a real storage account instead (for example, the one from `infra/`'s Terraform output) |

## 1. Install Python 3.14

Ubuntu/Debian's default `apt` repos don't carry 3.14 yet. The easiest cross-platform option is
[`uv`](https://docs.astral.sh/uv/):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install 3.14
```

Alternatives: the [deadsnakes PPA](https://github.com/deadsnakes) on Ubuntu, `pyenv install 3.14`,
or the official installer from [python.org](https://www.python.org/downloads/) on macOS/Windows.

## 2. Create a virtual environment and install dependencies

From the repository root (matches the root [README.md](../README.md) "Option B: Local Setup"):

```bash
cd /path/to/agentic-ai-immersion
uv venv --python 3.14 .venv   # or: python3.14 -m venv .venv
source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install --upgrade pip
pip install -r requirements.txt
```

## 3. Install the Azure CLI, azd, git, gh, and pwsh

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash   # Debian/Ubuntu; see learn.microsoft.com for other OSes

# azd (Azure Developer CLI)
curl -fsSL https://aka.ms/install-azd.sh | bash
azd version   # must be 1.34.2 or newer

# git
sudo apt-get update && sudo apt-get install -y git   # Debian/Ubuntu; macOS: brew install git or Xcode CLT

# GitHub CLI (gh)
(type -p wget >/dev/null || sudo apt-get install -y wget) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && wget -nv -O- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
     | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt-get update && sudo apt-get install -y gh   # Debian/Ubuntu; macOS: brew install gh

# PowerShell 7 (pwsh) — used only by the shared permission-setup script
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" \
  && sudo dpkg -i packages-microsoft-prod.deb \
  && sudo apt-get update && sudo apt-get install -y powershell   # Debian/Ubuntu; macOS: brew install --cask powershell
```

See [learn.microsoft.com](https://learn.microsoft.com/cli/azure/install-azure-cli), [learn.microsoft.com/azure/developer/azure-developer-cli/install-azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd),
[cli.github.com](https://cli.github.com), and [learn.microsoft.com/powershell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
for Windows, other Linux distros, and non-apt options.

Then sign in and configure Foundry tooling:

```bash
az login --use-device-code --tenant '<tenant-id>'
az account set --subscription '<subscription-id>'
azd config set auth.useAzCliAuth true
azd extension install azure.ai.agents
```

## 4. Decide what to do about Redis

If you only plan to run Labs 1-3 or Stretch 6, you can skip Redis entirely: leave
`MARKETPLACE_REDIS_URL` unset in `.env`. `tools/preflight.py` only pings Redis when the URL
resolves to a local host (`redis`, `localhost`, `127.0.0.1`), and the labs you're running don't
read that variable.

If you want `tools/preflight.py` to pass its Redis check (or you plan to use a generic
Redis-backed store or the Lab 4 infra template), install Redis natively instead of via Docker:

```bash
sudo apt-get install -y redis-server   # Debian/Ubuntu
# or: brew install redis               # macOS
sudo systemctl enable --now redis-server
```

Leave `MARKETPLACE_REDIS_URL=redis://localhost:6379/0` pointed at that native service.

## 5. Configure `.env`

Copy the example file at the repository root and fill it in:

```bash
cp -n .env.example .env
```

If you provisioned your Foundry project with this workshop's `infra/` Terraform root, populate
`.env` directly from its outputs instead of the Azure portal:

```bash
cd build-and-operate-foundry-agents/infra
terraform output -raw workshop_env >> ../../.env   # merge; do not overwrite the file
cd ../..
```

Then set the remaining values by hand:

- `MARKETPLACE_RESOURCE_SUFFIX` — a short value unique to you, such as `jd-4821`.
- `MARKETPLACE_BLOB_STORAGE_URL` — already set by `workshop_env` if you used the Terraform root;
  this gives Lab 2 real Azure Blob storage instead of needing Azurite.
- Leave `AZURE_OPENAI_API_KEY` and `AZURE_AI_SEARCH_API_KEY` blank — this workshop is Entra-only.

## 6. Verify

```bash
python build-and-operate-foundry-agents/tools/preflight.py
```

This checks the Python version, required commands, importable packages, your resource suffix, and
(only if your Redis URL is local) a Redis ping. Azure login, RBAC, and live service connectivity
still require the separate checks already documented in `infra/README.md` and `infra/post-deploy-validation.sh`.

## 7. Run a lab

Lab drivers are plain `.py` files with `# %%` cell markers; the matching `.ipynb` is a regenerated
artifact, not the source of truth. Run a lab directly:

```bash
python build-and-operate-foundry-agents/labs/lab1-hosted-agent-basics/lab1_hosted_basics.py
```

Or open the `.py` file in VS Code with the Python/Jupyter extensions and select your native `.venv`
interpreter — no container required — to run it cell by cell.

## Known deviations from the dev container

- `tools/preflight.py` hard-checks `sys.version_info[:2] == (3, 14)`; make sure the venv you
  activate is actually the 3.14 interpreter, not your system Python.
- The dev container mounts the repo with LF line endings enforced by `.gitattributes`; if you edit
  files on Windows outside WSL, make sure your editor doesn't reintroduce CRLF.
- Nothing here changes RBAC, networking, or cleanup guidance in `SETUP.md` — those sections still
  apply regardless of how you run the Python side locally.

## Troubleshooting: corporate DNS blocking Azure/Microsoft hostnames

On some corporate networks, the local DNS resolver fails to resolve specific Microsoft/Azure
hostnames (for example `login.microsoftonline.com`, `*.vault.azure.net`, `*.openai.azure.com`,
other per-resource `*.azure.com` names, or `azuresdkartifacts.z5.web.core.windows.net`, used by the
`azd` installer) even though the network path to Azure is otherwise open and unrelated domains
resolve fine. Symptoms: `curl: (6) Could not resolve host: ...`, or Python/az errors mentioning
`NameResolutionError` / `Failed to resolve`.

This is a DNS-only gap, not a firewall block, and the dev container doesn't avoid it either — it's
a property of the network, not of Docker. To confirm and work around it for one hostname:

```bash
HOST=<the-hostname-from-the-error>

# 1. Confirm local DNS fails but the host is real and reachable
getent hosts "$HOST" || echo "local DNS fails"
curl -s -H 'accept: application/dns-json' "https://1.1.1.1/dns-query?name=$HOST&type=A"

# 2. Pin it to the resolved IP (adjust the IP from step 1's output)
echo "<resolved-ip> $HOST" | sudo tee -a /etc/hosts

# 3. Confirm it resolves and is reachable now
getent hosts "$HOST"
curl -sI "https://$HOST/" | head -1
```

This is a session-only workaround: WSL regenerates `/etc/hosts` on restart (see the comment at the
top of that file), so you may need to reapply it. The durable fix is for your network/IT team to
correct DNS resolution for `*.microsoftonline.com`, `*.azure.com`, and related Microsoft domains.
