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

## 3. Install the Azure CLI and azd

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash   # Debian/Ubuntu; see learn.microsoft.com for other OSes
curl -fsSL https://aka.ms/install-azd.sh | bash
azd version   # must be 1.34.2 or newer
az login --use-device-code --tenant '<tenant-id>'
az account set --subscription '<subscription-id>'
azd config set auth.useAzCliAuth true
azd extension install azure.ai.agents
```

`git`, `gh`, and `pwsh` are common pre-installed tools on most dev machines; install them from
their own official sources if missing.

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
