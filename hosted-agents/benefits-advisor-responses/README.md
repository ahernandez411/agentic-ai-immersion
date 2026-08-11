# Employee Benefits Advisor — Responses agent

A **Microsoft Foundry hosted agent** using the **Responses** protocol: multi-turn, streaming,
model-directed tools. Adds a **Foundry Toolbox** (web search + code interpreter) and **Foundry
Skills** (embedded `SKILL.md` guidance). Good for interactive advisory and research.

## Files
- `main.py` — builds the agent and serves it on `ResponsesHostServer` (Toolbox + Skills wired in)
- `provision_skills.py` — registers the Skills with the project (`beta.skills`)
- `skills/<name>/SKILL.md` — cost-analysis + regulatory-guidance skills
- `agent.yaml` / `agent.manifest.yaml` — Foundry agent definition + deploy manifest
- `requirements.txt` — local and Foundry remote-build dependencies
- `Dockerfile` — optional container-based deployment path (not used by the source-code steps below)
- `test_local.py` — build the agent and run one turn against your project

## Run locally
```bash
# from repo root, workshop venv active, after `az login`
python hosted-agents/benefits-advisor-responses/test_local.py
```
Optional tools/skills (repo-root `.env`): `TOOLBOX_NAME=agent-tools`,
`SKILL_NAMES=cost-analysis-methodology,regulatory-guidance`. If unset, the agent still runs
(without tools/skills). Full host server: `pip install -r requirements.txt && python main.py` (port 8088).

## Deploy to Azure

Follow the shared [Microsoft Foundry source-code deployment prerequisites](../README.md#deploy-to-microsoft-foundry-azure). From the repository root, provision the Toolbox and managed Skills
first, then deploy the checked-in `benefits-advisor-responses` agent with Responses 1.0.0:

```powershell
$env:TOOLBOX_NAME = "agent-tools"
python AgentOps/src/tools/toolbox_config.py
python hosted-agents/benefits-advisor-responses/provision_skills.py

Push-Location hosted-agents/benefits-advisor-responses

# First deployment in this directory only. Skip init when the azd environment is already configured.
azd ai agent init --no-prompt --project-id $ProjectResourceId --agent-name benefits-advisor-responses --model-deployment gpt-5.4-mini --protocol responses --deploy-mode code --runtime python_3_14 --entry-point main.py --dep-resolution remote_build
azd up

Pop-Location
```

Wait until the new version is **`active`** before testing. The source ZIP must contain `main.py`,
`requirements.txt`, and `skills/*/SKILL.md` at its root. The deployment environment must contain
`AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-5.4-mini`, `TOOLBOX_NAME=agent-tools`, and
`SKILL_NAMES=cost-analysis-methodology,regulatory-guidance`.

## Test the Azure deployment

This is the **Responses** protocol: multi-turn, streaming, model-directed tools. Ask conversational questions; it computes/searches and replies with tables.

```powershell
$Endpoint = $env:AI_FOUNDRY_PROJECT_ENDPOINT.TrimEnd("/")
$Token = az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv
$Headers = @{ Authorization = "Bearer $Token"; "Content-Type" = "application/json" }
$Body = @{
	input = "Use code_interpreter to project the annual cost of 8 extra leave days for 250 staff at 8 hours/day and 60 CU/hour."
	stream = $false
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
	-Uri "$Endpoint/agents/benefits-advisor-responses/endpoint/protocols/openai/responses?api-version=v1" `
	-Headers $Headers `
	-Body $Body `
	-ResponseHeadersVariable ResponseHeaders

$ResponseHeaders["x-agent-session-id"]
```

Success is HTTP 200. For the prompt above, inspect `output` for `function_call`,
`function_call_output`, and `message`, with tool name `code_interpreter` and result `960000`.
Run question 4 below and confirm a `web_search` call plus current source URLs to validate the other
Toolbox capability.

More sample questions to try:

| # | Question | Exercises |
|---|----------|-----------|
| 1 | `Compare adding dental+vision vs a wellness stipend for 500 employees — show a cost table.` | code_interpreter + tables |
| 2 | `Project the annual cost of raising leave from 12 to 20 days for 250 staff at 60 CU/hr.` | calculation + assumptions |
| 3 | `What is a P50 benefits cost benchmark and how do I move from P25 to P50?` | skills knowledge |
| 4 | `Find current 2026 market trends for parental-leave top-ups and summarize.` | web_search (needs Toolbox) |

Call from Python (OpenAI-compatible Responses endpoint):
```python
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
c = AIProjectClient(endpoint="<project-endpoint>", credential=DefaultAzureCredential(), allow_preview=True)
oai = c.get_openai_client(agent_name="benefits-advisor-responses")
print(oai.responses.create(input="Benchmark dental coverage cost for 300 staff.", model="gpt-5.4-mini").output_text)
```
Tool questions (#1, #4) need a Toolbox: redeploy with `TOOLBOX_NAME` set; without it the agent still answers from reasoning + skills.
