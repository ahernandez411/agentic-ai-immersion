#!/usr/bin/env bash
# apply.sh: runs the full terraform workflow for this workshop's
# public-endpoint infra, start to finish, failing fast on the first error.
#
# What it does:
#   1. terraform init -upgrade, fmt, validate, then apply -- in order,
#      stopping immediately if any step fails. `apply` alone already computes
#      and displays the plan, then asks for interactive "yes" confirmation
#      before doing anything -- same review you'd get running it by hand.
#      All output is streamed live and also captured for diagnosis.
#   2. On a successful apply, reads `terraform output`, resolves every real
#      resource hostname via DNS-over-HTTPS, and patches /etc/hosts -- the
#      corporate-DNS workaround this session needed repeatedly, now automated.
#   3. Also on a successful apply, writes the workshop_env output into the
#      repository-root .env (auto-managed block; your other settings aren't
#      touched).
#   4. Whether it succeeded or failed, scans the captured output for error
#      patterns hit during this workshop's setup and prints the specific fix
#      for each one found.
#
# Usage:
#   bash apply.sh

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/apply-$(date +%Y%m%d-%H%M%S).log"
DOH_RESOLVER="https://1.1.1.1/dns-query"

status() { printf '\n==> %s\n' "$1"; }

# Runs one step, tee'd into the shared log. On failure, prints which step
# failed and returns its exit code so the caller can stop the pipeline.
run_step() {
  local label="$1"
  shift
  status "$label"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local exit_code=${PIPESTATUS[0]}
  if ((exit_code != 0)); then
    printf '\n==> FAILED: %s (exit %d)\n' "$label" "$exit_code"
  fi
  return "$exit_code"
}

# ---------------------------------------------------------------------------
# Step 1: the full terraform pipeline, stopping at the first failure.
# terraform apply alone already computes and displays the plan, then asks
# for interactive "yes" confirmation before doing anything -- no separate
# `terraform plan` step needed.
# ---------------------------------------------------------------------------
STEP_EXIT=0

run_step "terraform init -upgrade" terraform init -upgrade -input=false || STEP_EXIT=$?
if ((STEP_EXIT == 0)); then
  run_step "terraform fmt" terraform fmt || STEP_EXIT=$?
fi
if ((STEP_EXIT == 0)); then
  run_step "terraform validate" terraform validate || STEP_EXIT=$?
fi
if ((STEP_EXIT == 0)); then
  run_step "terraform apply" terraform apply || STEP_EXIT=$?
fi

APPLY_EXIT=$STEP_EXIT

# ---------------------------------------------------------------------------
# Step 2: on success, patch /etc/hosts for every real hostname this
# deployment produced, using DNS-over-HTTPS to bypass the local resolver.
# ---------------------------------------------------------------------------
patch_dns() {
  status "Patching /etc/hosts for deployment hostnames (corporate DNS workaround)"

  local outputs_json
  outputs_json="$(terraform output -json 2>/dev/null)" || {
    echo "Could not read terraform output; skipping DNS patch."
    return 1
  }

  # Pull every https://host[...] URL plus the bare ACR login-server hostname
  # out of the outputs that carry one, de-duplicated.
  local hosts
  hosts="$(python3 - "$outputs_json" <<'PYEOF'
import json, sys
from urllib.parse import urlparse

data = json.loads(sys.argv[1])

def host_of(value):
    if not value:
        return None
    if "://" in value:
        return urlparse(value).hostname
    return value.strip("/") or None

keys = (
    "foundry_account_endpoint", "foundry_project_endpoint", "azure_openai_endpoint",
    "search_endpoint", "blob_storage_url", "cosmos_db_endpoint", "key_vault_uri",
    "container_registry_login_server",
)
seen = []
for key in keys:
    entry = data.get(key, {})
    h = host_of(entry.get("value") if isinstance(entry, dict) else None)
    if h and h not in seen:
        seen.append(h)
print("\n".join(seen))
PYEOF
)"

  if [[ -z "$hosts" ]]; then
    echo "No hostnames found in terraform output; nothing to patch."
    return 0
  fi

  local marker_start="# --- apply.sh DNS workaround (auto-managed; safe to delete) ---"
  local marker_end="# --- end apply.sh DNS workaround ---"

  # Drop any previous block this script added, so stale hostnames from an
  # earlier deployment don't linger alongside the current ones.
  if grep -qF "$marker_start" /etc/hosts 2>/dev/null; then
    sudo sed -i "/$(printf '%s' "$marker_start" | sed 's/[.[\*^$/]/\\&/g')/,/$(printf '%s' "$marker_end" | sed 's/[.[\*^$/]/\\&/g')/d" /etc/hosts
  fi

  local lines="$marker_start"
  lines+=$'\n'"# Added $(date -u +%Y-%m-%dT%H:%M:%SZ). Corporate DNS fails to resolve these"
  lines+=$'\n'"# per-resource Azure hostnames even though the network path is open."
  lines+=$'\n'"# Regenerate by rerunning apply.sh; see infra/README.md for the manual recipe."

  local failures=0
  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    local ip
    ip="$(curl -s -m 5 -H 'accept: application/dns-json' "${DOH_RESOLVER}?name=${host}&type=A" \
          | python3 -c "import json,sys; d=json.load(sys.stdin); a=[x['data'] for x in d.get('Answer',[]) if x.get('type')==1]; print(a[-1] if a else '')" 2>/dev/null)"
    if [[ -n "$ip" ]]; then
      lines+=$'\n'"$ip $host"
      echo "  resolved $host -> $ip"
    else
      echo "  WARNING: could not resolve $host via DNS-over-HTTPS; skipping"
      failures=$((failures + 1))
    fi
  done <<< "$hosts"
  lines+=$'\n'"$marker_end"

  printf '\n%s\n' "$lines" | sudo tee -a /etc/hosts > /dev/null

  echo "Verifying..."
  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    if getent hosts "$host" > /dev/null 2>&1; then
      echo "  OK   $host"
    else
      echo "  FAIL $host (still unresolvable; see infra/README.md troubleshooting)"
    fi
  done <<< "$hosts"

  if ((failures > 0)); then
    echo "Note: $failures hostname(s) could not be resolved even via DNS-over-HTTPS. If a resource was just created, wait a minute and rerun: bash apply.sh (DNS propagation can lag briefly)."
  fi
}

# ---------------------------------------------------------------------------
# Step 2b: write/update the repository-root .env from the workshop_env
# output, without touching any other settings already in that file.
# ---------------------------------------------------------------------------
write_env() {
  status "Writing workshop values into the repository-root .env"

  local repo_root="$SCRIPT_DIR/../.."
  local env_file="$repo_root/.env"

  if [[ ! -f "$env_file" && -f "$repo_root/.env.example" ]]; then
    cp "$repo_root/.env.example" "$env_file"
    echo "Created .env from .env.example"
  fi

  local workshop_env_json
  workshop_env_json="$(terraform output -json workshop_env 2>/dev/null)" || {
    echo "Could not read the workshop_env output; skipping .env update."
    return 1
  }

  python3 - "$env_file" "$workshop_env_json" <<'PYEOF'
import json, sys

env_file, raw_json = sys.argv[1], sys.argv[2]
workshop_env = json.loads(raw_json)  # single "KEY=VALUE\nKEY=VALUE\n..." string

start = "# --- apply.sh workshop_env (auto-managed; safe to delete, will be rewritten) ---"
end = "# --- end apply.sh workshop_env ---"

try:
    with open(env_file, encoding="utf-8") as f:
        existing = f.read()
except FileNotFoundError:
    existing = ""

if start in existing:
    head = existing.split(start, 1)[0]
    tail = existing.split(end, 1)[1] if end in existing else ""
    existing = head.rstrip("\n") + ("\n" if head.strip() else "") + tail.lstrip("\n")

block_lines = [start] + workshop_env.splitlines() + [end]
block = "\n".join(block_lines) + "\n"

separator = "\n" if existing and not existing.endswith("\n\n") else ""
with open(env_file, "w", encoding="utf-8") as f:
    f.write(existing.rstrip("\n") + "\n" + separator + block if existing.strip() else block)

print(f"Wrote {len(workshop_env.splitlines())} keys to {env_file}")
PYEOF
}

if ((APPLY_EXIT == 0)); then
  patch_dns
  write_env
fi

# ---------------------------------------------------------------------------
# Step 3: scan the captured log for error patterns seen during this
# workshop's setup, and print the specific fix for each one found.
# ---------------------------------------------------------------------------
status "Checking apply output against known issues"

FOUND_ANY=0

check_issue() {
  local pattern="$1" title="$2" fix="$3"
  if grep -qiE "$pattern" "$LOG_FILE"; then
    FOUND_ANY=1
    printf '\n--- %s ---\n%s\n' "$title" "$fix"
  fi
}

check_issue \
  'dial tcp: lookup .* no such host|Could not resolve host|Name or service not known|NameResolutionError' \
  "Corporate DNS cannot resolve an Azure hostname" \
  "This should have been auto-patched above. If it's still failing: the hostname may be new
and not yet covered by patch_dns()'s output list, or DNS-over-HTTPS itself returned nothing
(propagation lag for a brand-new resource -- wait ~60s and rerun 'bash apply.sh').
Manual recipe: see the 'Troubleshooting: corporate DNS' section in NON-DOCKER-SETUP.md."

check_issue \
  'RequestConflict: Another operation is in progress' \
  "409 Conflict: another operation in progress on the Foundry/Cognitive Services account" \
  "Transient -- the account's internal write lock from a previous call (e.g. a model
deployment) hadn't released yet. Just rerun: bash apply.sh
If it recurs repeatedly, add -parallelism=1 to serialize writes against the account:
  bash apply.sh -parallelism=1"

check_issue \
  'VaultAlreadyExists|recently deleted but not purged' \
  "Key Vault name collision (soft-deleted vault still exists under this name)" \
  "Vault names are globally unique across every Azure tenant. With this config's random
6-character suffix, a collision with your OWN previous deployment or another learner's is
astronomically unlikely but not impossible on an unlucky draw. Force a fresh suffix and retry:
  terraform apply -replace=random_string.unique_suffix
(Plain 'terraform apply' alone will retry the SAME already-computed suffix and fail again.)"

check_issue \
  'to be managed via Terraform this resource needs to be imported' \
  "A resource already exists in Azure but isn't in Terraform state" \
  "A previous partial apply likely created this successfully before a later step failed.
Find the resource address and ID in the error above, then run:
  terraform import '<resource_address>' '<azure_resource_id>'
Then rerun: bash apply.sh"

check_issue \
  'Foundry Account capabilityHost Not Found' \
  "Missing account-level capability host" \
  "This config already includes azapi_resource.foundry_account_capability_host in
standard-agent.tf (required by the live API for public Standard Agent setup, even though it's
undocumented). If you still see this, confirm that resource wasn't accidentally removed, then
rerun: bash apply.sh"

check_issue \
  'can only be (updated|deleted) by the workspace that created it' \
  "A connection resource is locked to a different internal 'workspace' surface" \
  "Known API quirk on certain azapi-managed connections (hit this with Application Insights,
since removed from this config). Terraform can't fix this via PUT/DELETE -- tell it to stop
managing the resource instead:
  terraform state rm '<resource_address>'
The orphaned object in Azure is harmless once its target resource is also gone."

check_issue \
  'rate_limit_exceeded|429' \
  "Model deployment rate limit (429) during a lab run, not apply" \
  "Not an apply error -- this happens when running a lab script, not 'terraform apply'.
The deployed capacity (variables.tf's model_deployments) may still be too low for your usage.
Bump the relevant model's capacity and rerun: bash apply.sh
Otherwise just retry the lab after ~60s; token quota resets every minute."

check_issue \
  '"The definition field is required"|Could not find member .enablePublicHostingEnvironment' \
  "Capability host schema mismatch with published API docs" \
  "Already worked around in this config: standard-agent.tf creates the account-level
capability host with empty properties (no enablePublicHostingEnvironment, no customerSubnet),
which is what the live API actually accepts despite its own docs showing otherwise."

if ((APPLY_EXIT != 0 && FOUND_ANY == 0)); then
  printf '\nApply failed but no known pattern matched. Re-run with the full error and ask for help; log saved at: %s\n' "$LOG_FILE"
fi

exit "$APPLY_EXIT"
