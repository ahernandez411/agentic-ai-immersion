# 🚀 Hosted Agents

[← Back to main README](../README.md)

Two **Microsoft Foundry Hosted Agents** that demonstrate the two hosting **protocols** on a
single, generic FSI scenario — **employee benefits**. You supply the agent code, a model, and
(optionally) tools and skills; Foundry runs and scales the container.

| Agent | Protocol | What it shows |
|-------|----------|---------------|
| [`benefits-review-invocations/`](benefits-review-invocations) | **Invocations** | A single structured request → structured response (fire-and-forget). |
| [`benefits-advisor-responses/`](benefits-advisor-responses) | **Responses** | Multi-turn, streaming, model-directed tools — **Foundry Toolbox** + **Foundry Skills**. |

> These are deliberately minimal teaching examples. The same agent-build pattern
> (`FoundryChatClient` → `Agent` → host server) is used for both — only the **host server**
> (and therefore the protocol) differs.

## Invocations vs Responses — when to use which

| Dimension | Invocations (Review) | Responses (Advisor) |
|-----------|----------------------|---------------------|
| Interaction | Single structured request → response | Multi-turn natural conversation |
| Tool use | None (deterministic) | Model-directed (decides when to search/compute) |
| Streaming | No (batch result) | Token-by-token (OpenAI-compatible) |
| State | Stateless | Session history managed by the platform |
| Best for | Batch, API-to-API, deterministic pipelines | Interactive advisory, research, exploration |
| Host server | `InvocationsHostServer(agent)` | `ResponsesHostServer(agent)` |

## Prerequisites

- An existing **Microsoft Foundry project** in a supported Azure region with `gpt-5.4-mini`
   (or another compatible chat model) deployed.
- **Azure CLI 2.80+** and the current **Azure Developer CLI (`azd`)**, signed in to the tenant and
   subscription that own the project.
- The deploying identity needs **Foundry Project Manager** at project scope. For invocation only,
   use **Foundry Agent Consumer**; developers can use **Foundry User**.
- **Python 3.13+** locally. These checked-in manifests and remote builds are validated with the
   Foundry `python_3_14` hosted runtime.
- A repo-root `.env` containing `AI_FOUNDRY_PROJECT_ENDPOINT` and
   `AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-5.4-mini`. No API key is required; the code uses
   `DefaultAzureCredential`.

## Run locally

Each agent has a `test_local.py` that builds the agent and runs one turn against your project.
They read the workshop root `.env` (or the agent-local `.env`).

```bash
# from the repo root, with the workshop venv active
python hosted-agents/benefits-review-invocations/test_local.py
python hosted-agents/benefits-advisor-responses/test_local.py
```

To run the full host server locally, install the agent's `requirements.txt` and run `python main.py`
(listens on port 8088).

### Advisor extras: Toolbox + Skills

The advisor can use a **Foundry Toolbox** (web_search + code_interpreter) and **Foundry Skills**:

1. **Skills** are bundled as `skills/<name>/SKILL.md` and embedded into the agent's instructions
   at startup (progressive disclosure). Set `SKILL_NAMES` to choose which to embed (default: both).
2. **Toolbox**: create a Foundry Toolbox named in `TOOLBOX_NAME` containing `web_search` and
   `code_interpreter`, then set `TOOLBOX_NAME`.

If `TOOLBOX_NAME` / `SKILL_NAMES` are unset, the advisor still runs, but it won't demonstrate the
two capabilities that distinguish this sample. For the complete Azure deployment, use
`TOOLBOX_NAME=agent-tools` and
`SKILL_NAMES=cost-analysis-methodology,regulatory-guidance`.

## Deploy to Microsoft Foundry (Azure)

These are **source-code hosted agents**. Foundry uploads a ZIP, restores the pinned Python
dependencies remotely, provisions an isolated runtime, creates an agent identity, and exposes the
declared protocol endpoint. This path does **not** require Azure Container Registry or a local Docker
build. The included `Dockerfile` is only for the alternative container-based deployment path.

### 1. Authenticate and select the existing project

Run these commands from the repository root. The project resource ID is the Azure resource ID—not
the HTTPS project endpoint.

```powershell
az login
$SubscriptionId = "<subscription-id>"
$ResourceGroup = "<resource-group>"
$FoundryAccount = "<foundry-account>"
$ProjectName = "<project-name>"

az account set --subscription $SubscriptionId
azd config set auth.useAzCliAuth true
azd extension install azure.ai.agents

$ProjectResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryAccount/projects/$ProjectName"
```

### 2. Provision the advisor's Toolbox and managed Skills

Run this before deploying `benefits-advisor-responses`. The first command creates `agent-tools`
with `web_search` and `code_interpreter` and promotes its new version to default. The second
registers the bundled Skills as reusable Foundry resources.

```powershell
$env:TOOLBOX_NAME = "agent-tools"
python AgentOps/src/tools/toolbox_config.py
python hosted-agents/benefits-advisor-responses/provision_skills.py
```

The advisor ZIP also includes `skills/*/SKILL.md`, so its runtime instructions remain available even
if managed-Skill lookup is unavailable during startup.

### 3. Deploy each agent from source

From each agent directory, initialize source-code deployment once, then run `azd up`. If that
directory already has an initialized `azd` environment, skip `azd ai agent init` and run only
`azd up`.

```powershell
Push-Location hosted-agents/benefits-review-invocations
azd ai agent init --no-prompt --project-id $ProjectResourceId --agent-name benefits-review-invocations --model-deployment gpt-5.4-mini --protocol invocations --deploy-mode code --runtime python_3_14 --entry-point main.py --dep-resolution remote_build
azd up
Pop-Location

Push-Location hosted-agents/benefits-advisor-responses
azd ai agent init --no-prompt --project-id $ProjectResourceId --agent-name benefits-advisor-responses --model-deployment gpt-5.4-mini --protocol responses --deploy-mode code --runtime python_3_14 --entry-point main.py --dep-resolution remote_build
azd up
Pop-Location
```

The expected deployed resources are:

| Agent | Runtime | Protocol | Required environment |
|-------|---------|----------|----------------------|
| `benefits-review-invocations` | `python_3_14` | Invocations 1.0.0 | `AZURE_AI_MODEL_DEPLOYMENT_NAME` |
| `benefits-advisor-responses` | `python_3_14` | Responses 1.0.0 | model, `TOOLBOX_NAME=agent-tools`, `SKILL_NAMES` |

`azd up` packages the source, computes its SHA-256, uploads it, configures RBAC, and waits for the
new version. Do not invoke the version until its status is **`active`**. If it becomes **`failed`**,
inspect the version's `error.code` and `error.message`; provisioning failures occur before container
logs are available.

### Programmatic/CD deployment

For automation, use `azure-ai-projects>=2.2.0` or the REST multipart API. The remote-build ZIP must
be flat—no top-level wrapper directory:

```text
benefits-review.zip                 benefits-advisor.zip
├── main.py                         ├── main.py
└── requirements.txt                ├── requirements.txt
                                    └── skills/<name>/SKILL.md
```

Send `metadata` (`application/json`) and `code` (`application/zip`) multipart parts plus
`x-ms-code-zip-sha256`. Create with `POST /agents`; publish a code/config update with
`POST /agents/{agent-name}`. Foundry creates a new version only when the definition or ZIP hash
changes. Poll `GET /agents/{agent-name}/versions/{version}?api-version=v1` until `active`.

Official walkthrough: [Deploy a hosted agent from source code](https://learn.microsoft.com/azure/foundry/agents/how-to/deploy-hosted-agent-code).
For an automated **CI/CD pipeline** (build → promote → smoke test → rollback), see
[`AgentOps/`](../AgentOps). Do not run `azd down` against a shared existing Foundry project unless
you intentionally want to remove resources managed by that `azd` environment.

## 🔗 Dependency sync (avoid version drift)

There are two pinning layers. Keep the hosted runtime's minimal pins aligned with the root lock:

| File | Scope | Pinning |
|------|-------|---------|
| `../requirements.in` → `../requirements.txt` | Notebooks + development | Full lock; source of truth |
| `benefits-*/requirements.txt` | Hosted remote build | Minimal explicit Framework, Projects, Identity, MCP, and hosting pins |

**Do not replace the explicit packages with `agent-framework[foundry]`.** At the validated versions,
that meta-package expands to `agent-framework-core[all]` and unrelated extras whose constraints can
make a Python 3.14 remote build fail with `ResolutionImpossible`. Update root `requirements.in`,
re-lock, mirror the explicit runtime pins, run the local smoke tests, and then deploy a new version.

## ✅ Test after deployment

Confirm the agents are live, then invoke them with sample questions.

First confirm that the latest version of each agent is `active` in the Foundry portal or through the
Agents API. Then use the protocol-specific PowerShell tests in the per-agent guides:

- [Review / Invocations deployment test](benefits-review-invocations/README.md#test-the-azure-deployment)
- [Advisor / Responses deployment test](benefits-advisor-responses/README.md#test-the-azure-deployment)

**Benefits Review** (Invocations) — paste a full program, get a structured review:

| Sample payload | Expected |
|----------------|----------|
| 200-emp fintech; employee-only health, 5% match, 12d leave, no life/dental/parental | Gaps: dental, life, parental; quick-win recs |
| 1,000-emp manufacturer; family health, 8% pension, 25d leave, 2x life, income protection | P50–P75; gap = wellness |
| 30-person startup; stipend health, no retirement, unlimited leave, equity-heavy | Retirement + risk-benefit gaps |

**Benefits Advisor** (Responses) — ask conversational questions:

| Sample question | Exercises |
|-----------------|-----------|
| Compare dental+vision vs wellness stipend for 500 staff — cost table | code_interpreter |
| Project cost of 12→20 leave days for 250 staff at 60 CU/hr | calculation |
| Explain P50 benchmark; how to move P25→P50 | skills |
| Current 2026 parental-leave top-up trends | web_search (Toolbox) |

The portal **Agent playground** is also useful for interactive testing. Be sure to select the latest
`active` version: failed historical versions remain visible for audit and troubleshooting.

## 🧭 Troubleshooting

| Issue | Solution |
|-------|----------|
| **401 on deploy/invoke** | Acquire a token for `https://ai.azure.com`; confirm `az account show` points to the project tenant/subscription. |
| **403 on deploy** | Deployment requires **Foundry Project Manager** at project scope. **Foundry User** alone is not sufficient to create hosted versions. Allow time for role propagation. |
| **403 on invoke** | Grant **Foundry Agent Consumer** (invoke only) or **Foundry User** (develop and invoke) at project scope. |
| **HTTP 500 on `invoke` (Review/Invocations)** | The Invocations server calls `request.json()` — send **JSON**: `'{"message":"..."}'`, not a plain string. (Responses/Advisor accepts a plain string.) |
| **Version is `failed` / `CodeError`** | Read the version's `error.message`. Keep the ZIP flat and retain the explicit minimal dependency pins; don't use `agent-framework[foundry]`. |
| **`424 session_not_ready`** | Capture `x-agent-session-id`, stream `.../sessions/{id}:logstream?api-version=v1`, fix startup/readiness, and deploy a new version. |
| **Toolbox session closes immediately** | Foundry Toolbox doesn't implement MCP `ping`; keep the `_ping_available = False` compatibility setting in the advisor and AgentOps clients. |
| **HTTP 500 model access from a deployed agent** | Check the hosted agent's platform identity and project role assignments, wait for propagation, then retry. |
| **`az login` / wrong subscription** | `az login` then `az account set --subscription <id>`; confirm with `az account show`. |
| **Missing values** | These agents read the repo-root `.env` — no API keys; leave `AZURE_OPENAI_API_KEY` blank. |
| **`azd` or `azd ai agent` not found** | [Install/update azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd), then install/update the `azure.ai.agents` extension. |

## 📚 Learn more
