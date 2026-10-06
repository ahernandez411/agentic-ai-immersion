# Repository index

## Functional areas

- `azure-ai-agents/`: numbered, capability-oriented Foundry notebooks.
- `agent-framework/`: provider, workflow, middleware, context, state, skills and telemetry notebooks.
- `observability-and-evaluations/`: tracing, evaluator and red-team notebooks.
- `hosted-agents/`: small deployable examples for the Responses and Invocations protocols.
- `AgentOps/`: standalone GitOps example with infrastructure and tests.
- `build-and-operate-foundry-agents/`: cumulative Healthcare Marketplace workshop; four core labs and two stretch labs. Replaces the old hosted-agent lab track.
- `byouc/`: use-case specification templates.

## Boundaries and navigation

- Agent navigation and index maintenance: `.github/copilot-instructions.md`, `.github/skills/repo-index/SKILL.md`, and this index.
- Shared line-ending policy: root `.gitattributes` normalizes text to LF; `.vscode/settings.json` defaults new files to LF. `.gitignore` permits these shared settings while excluding other VS Code files.
- Learner setup: `.devcontainer/devcontainer.json`, `.devcontainer/compose.yaml`, `.env.example`, root `requirements.in` and `requirements.txt`.
- Workshop entry point: `build-and-operate-foundry-agents/README.md` and `SETUP.md`.
- Workshop customer collateral: `build-and-operate-foundry-agents/Datasheets/` contains editable HTML sources and rendered PDF/Word deliverables.
- Workshop implementation: `common/` (data, environment and state), `data/` (synthetic fixtures), `labs/` (drivers and notebooks).
- Lab 2 conversation history: Azure Blob/Azurite or files; shared `common/message_store.py` retains Redis support for other labs. Cloud Blob uses an existing account/container and managed identity.
- Hosted model resilience: `common/model_resilience.py` provides visible, retry-header-aware Agent Framework
  throttling retries and consistent failed Responses payload handling for Labs 1-3 and Stretch 6.
- Workshop resource lifecycle: `common/resource_names.py` applies one attendee suffix to every created
  agent, evaluation, Search resource and project connection; `tools/cleanup_workshop.py` provides
  dry-run-first cleanup for one suffix or every workshop suffix without deleting shared infrastructure.
- Workshop infrastructure: `build-and-operate-foundry-agents/infra/README.md` is the entry point for a
  self-contained, publicly-reachable Microsoft Foundry Standard Agent deployment (no VNet/private
  endpoints/private DNS; Entra ID RBAC is the access boundary). `variables.tf` carries workshop-ready
  defaults for naming, models and capacity; `terraform.tfvars` only pins `subscription_id`, `tenant_id`,
  and `operator_principal_id`. Terraform owns identity, Storage, Cosmos DB, AI Search, Foundry
  account/project/capability hosts (both account- and project-level; the account-level
  `capabilityHosts` resource is required by the live API even though it's undocumented), registry and
  vault (Application Insights and Log Analytics were both removed; no diagnostic-settings wiring
  remains). Storage, Key Vault, Container Registry, Foundry account, AI Search, Cosmos DB, and the
  managed identity all share one random suffix (`random_string.unique_suffix` in `main.tf`) for
  consistent, collision-resistant naming. Outputs map directly to the workshop `.env`; no concrete
  Azure identifiers are committed except in the gitignored local `terraform.tfvars`.
  `tf-post-deploy-validation.sh` reuses Azure CLI credentials, verifies the tfvars/variable-default-selected
  Azure context and Foundry resources, and runs a mini-model Responses API smoke test.
  `tf-apply.sh`/`tf-destroy.sh` run the full init/fmt/validate/apply (or validate/destroy) pipeline in
  one command, sharing DNS-over-HTTPS `/etc/hosts` patching (a corporate-DNS workaround some networks
  need for per-resource Azure hostnames), `.env` workshop_env writing/clearing, and known-failure-pattern
  diagnosis from `tf-lib.sh`. All `infra/` scripts use a `tf-` prefix so they sort/group together.
- Non-Docker learner path: `build-and-operate-foundry-agents/NON-DOCKER-SETUP.md` is a Docker-free
  alternative to `SETUP.md`'s dev-container path (native Python 3.14, `az`/`azd`, optional native
  Redis instead of the dev-container's Redis/Azurite sidecars), cross-linked from `SETUP.md`.
- Deployment: each lab's `hosted*/main.py` and minimal pinned requirements; `prepare.py` vendors shared files. Generated packages, credentials and runtime artifacts are not source.
- Shell integration: `labs/deployment.py`; Bash is the learner shell, Python holds deployment validation/logic.
- Notebooks: edit the adjacent `# %%` Python driver and regenerate with `tools/py_to_ipynb.py`; preserve exercise gates.
- Lab teaching alignment: `labs/README.md`, each lab README, and Markdown cells in the six adjacent Python
  drivers connect outcomes to engineering decisions, acceptance evidence, ownership, and measurement limits.
  Generated notebooks mirror that wording; runtime instructions and executable cells remain unchanged.
- Offline checks: the workshop's `tools/validate_workshop.py` and `tests/`, plus `.github/workflows/workshop-validate.yml`. Validation checks notebook cells, dependency pins, self-tests, regression tests and all five hosted packages in a temporary copy.
- Cloud pipeline: Lab 4's nested workflow is an opt-in template, not an active deployment workflow.
- Shared RBAC setup: `scripts/setup-permissions.ps1` (PowerShell 7 in the dev container).

## Conventions

Use the root Python lock for workstation dependencies. Hosted requirements match its versions but contain only runtime packages.
Azure authentication is Entra-based; no committed credentials. Cloud operations require explicit learner action.
Keep capability notebooks independent from the cumulative use-case track.
Presentation decks and slide-build plans belong outside the runnable lab track.

## Freshness

Baseline: `ec19e83bc42f4a332d46a9b9a4e6a6b0361d0ab9` (after squashing the initial workshop commits).
Pending additions considered: `.gitattributes`, `.vscode/settings.json`,
`.github/skills/repo-index/SKILL.md`, and this index; related updates to `.gitignore`
and `.github/copilot-instructions.md` establish shared LF settings and index startup/maintenance rules.
Updated for the replacement of `foundry-hosted-agents-labs/` with `build-and-operate-foundry-agents/`,
the shared dev-container Redis service, Bash/Python deployment path and offline validation workflow.
Updated for attendee-scoped resource naming, dry-run cleanup, startup Redis configuration and enforced
lab-specific step identifiers in generated walkthrough notebooks.
Updated for optional Azure Blob conversation history and the local Azurite emulator in Lab 2.
Removed the workshop's `deck/` directory on 2026-09-30; runnable lab assets remain in place.
Also removed seven facilitator/authoring documents and the old top-level workshop `infra/`
scaffolding. A self-contained private Standard Agent `infra/` implementation is pending addition;
Lab 4's `infra/README.md`, hosted packaging rules and runnable lab assets remain.
Lab 2 history is limited to Azure Blob/Azurite or files, and Lab 3 uses file-backed session state;
shared Redis remains available to generic store configurations.
Added `build-and-operate-foundry-agents/common/model_resilience.py` for shared hosted-agent rate-limit
handling and Responses failure reporting; updated affected drivers, hosted entry points, and generated notebooks.
Added the two-page Build and Operate Foundry Agents workshop datasheet, Word version, and editable HTML source under
`build-and-operate-foundry-agents/Datasheets/`.
Lab 3 handler-registration and human-approval regression tests are in
`build-and-operate-foundry-agents/tests/test_lab3_workflow.py` (real workflow, offline packet writer and
streaming AgentExecutor graph). Lab 3 designates only the advisor coordinator as the final-output executor;
specialist streaming updates are intermediate outputs.
Baseline for this addition: `e34129302cdfbff4ed1a41defa5c9b930641a5da`; pending structural change considered:
the new Lab 3 regression test file.
Baseline for the lab-alignment documentation pass: `1d7fdc56a41928596ff64b6d2d7efb66a3c89331`.
Pending changes considered: the lab overview, core and stretch READMEs, artifact and infrastructure guidance,
six Python Markdown-cell sources, and their regenerated walkthrough notebooks. No runtime architecture,
dependencies, executable cells, deployment workflow, storage implementation, or artifact contract changed.
Baseline for the sanitized workshop infrastructure addition: `2798ac5d51e00ed6d418d27c5f67dc9a813ba000`.
Pending structural change considered: `build-and-operate-foundry-agents/infra/`, including the deployment
README, ignored local tfvars convention, provider lock, complete Standard Agent resource graph and workshop
environment outputs. This supersedes the registry-coupled draft and its PowerShell-only deployment checks.
Baseline for the post-deployment validator: `15f9fdbca29b5137618ff947009cfa58d45e504f`.
Pending structural change considered: `build-and-operate-foundry-agents/infra/tf-post-deploy-validation.sh`
and its README/index navigation updates.
Pending structural change considered: `build-and-operate-foundry-agents/infra/troubleshoot-private-endpoint.sh`
and its README/index navigation updates.
Baseline for the public-endpoint infra refactor: `2385c814463b5cdf7a7f6d92c952f7af96afb77d` ("remove
app insights", already committed). History: `a9a6999` moved `build-and-operate-foundry-agents/infra/`
from private VNet/private-endpoint isolation to public network access throughout (Foundry account,
Storage, Cosmos DB, Search, Key Vault, ACR); `network.tf` and `infra/troubleshoot-private-endpoint.sh`
were deleted; most `terraform.tfvars` values moved to `variables.tf` defaults, leaving only
`subscription_id`/`tenant_id`/`operator_principal_id` as required inputs. `eea46b0` added an
account-level `Microsoft.CognitiveServices/accounts/capabilityHosts` resource in `standard-agent.tf`
(required by the live API for public Standard Agent setup, independent of the account's own
published API docs). `2385c81` removed Application Insights (Log Analytics workspace remains for
other resources' diagnostic settings).
Pending structural change considered: added `build-and-operate-foundry-agents/NON-DOCKER-SETUP.md` as
a Docker-free alternative to `SETUP.md`'s dev-container path, cross-linked from `SETUP.md`.
Pending structural change considered: `build-and-operate-foundry-agents/infra/monitoring.tf` was
deleted and Log Analytics removed entirely (the diagnostic-settings destination noted above as
"remains" after the Application Insights removal has since also been removed; no monitoring/diagnostic
resources remain in this root). The managed identity now shares `random_string.unique_suffix` with
Storage/Key Vault/ACR/Foundry account/AI Search/Cosmos DB for naming consistency, though it doesn't
strictly need it (identity names are unique per resource group, not globally). `apply.sh` was renamed
`tf-apply.sh`, and a new `tf-destroy.sh` plus shared `tf-lib.sh` (sourced, not run directly) were
added; every `infra/` operational script now uses a `tf-` prefix to sort/group together.
