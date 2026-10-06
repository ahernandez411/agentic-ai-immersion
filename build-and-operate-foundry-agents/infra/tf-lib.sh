#!/usr/bin/env bash
# tf-lib.sh: shared helpers for tf-apply.sh and tf-destroy.sh.
# Not meant to be run directly -- source it from another script.

DOH_RESOLVER="https://1.1.1.1/dns-query"

status() { printf '\n==> %s\n' "$1"; }

# Runs one step, tee'd into the given log file. On failure, prints which
# step failed and returns its exit code so the caller can stop the pipeline.
run_step() {
  local log_file="$1" label="$2"
  shift 2
  status "$label"
  "$@" 2>&1 | tee -a "$log_file"
  local exit_code=${PIPESTATUS[0]}
  if ((exit_code != 0)); then
    printf '\n==> FAILED: %s (exit %d)\n' "$label" "$exit_code"
  fi
  return "$exit_code"
}

# Extracts every real resource hostname out of a `terraform output -json`
# blob, de-duplicated, one per line.
extract_hostnames() {
  local outputs_json="$1"
  python3 - "$outputs_json" <<'PYEOF'
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
}

# Patches /etc/hosts for a newline-delimited list of hostnames, using
# DNS-over-HTTPS to bypass a broken local resolver (a known issue on some
# corporate networks). Replaces any previous block either script added.
patch_dns_for_hosts() {
  local hosts="$1"

  if [[ -z "$hosts" ]]; then
    echo "No hostnames to patch."
    return 0
  fi

  local marker_start="# --- tf-apply.sh/tf-destroy.sh DNS workaround (auto-managed; safe to delete) ---"
  local marker_end="# --- end DNS workaround ---"

  if grep -qF "$marker_start" /etc/hosts 2>/dev/null; then
    sudo sed -i "/$(printf '%s' "$marker_start" | sed 's/[.[\*^$/]/\\&/g')/,/$(printf '%s' "$marker_end" | sed 's/[.[\*^$/]/\\&/g')/d" /etc/hosts
  fi

  local lines="$marker_start"
  lines+=$'\n'"# Added $(date -u +%Y-%m-%dT%H:%M:%SZ). Corporate DNS fails to resolve these"
  lines+=$'\n'"# per-resource Azure hostnames even though the network path is open."
  lines+=$'\n'"# Regenerate by rerunning tf-apply.sh or tf-destroy.sh; see infra/README.md."

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
    echo "Note: $failures hostname(s) could not be resolved even via DNS-over-HTTPS. Wait ~60s and rerun if a resource was just created/destroyed (DNS propagation can lag briefly)."
  fi
}

# Removes the DNS workaround block from /etc/hosts entirely, with nothing to
# replace it (used by tf-destroy.sh once the resources it described are gone).
clear_dns_block() {
  local marker_start="# --- tf-apply.sh/tf-destroy.sh DNS workaround (auto-managed; safe to delete) ---"
  local marker_end="# --- end DNS workaround ---"

  if grep -qF "$marker_start" /etc/hosts 2>/dev/null; then
    sudo sed -i "/$(printf '%s' "$marker_start" | sed 's/[.[\*^$/]/\\&/g')/,/$(printf '%s' "$marker_end" | sed 's/[.[\*^$/]/\\&/g')/d" /etc/hosts
    echo "Cleared the DNS workaround block from /etc/hosts (those resources no longer exist)."
  else
    echo "No DNS workaround block found in /etc/hosts; nothing to clear."
  fi
}

# Removes the auto-managed workshop_env block from the repository-root .env
# (used by tf-destroy.sh once the resources it describes no longer exist).
clear_env_block() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  python3 - "$env_file" <<'PYEOF'
import sys

env_file = sys.argv[1]
start = "# --- tf-apply.sh workshop_env (auto-managed; safe to delete, will be rewritten) ---"
end = "# --- end tf-apply.sh workshop_env ---"

with open(env_file, encoding="utf-8") as f:
    existing = f.read()

if start not in existing:
    print("No auto-managed workshop_env block found; nothing to clear.")
    raise SystemExit(0)

head = existing.split(start, 1)[0]
tail = existing.split(end, 1)[1] if end in existing else ""
remaining = head.rstrip("\n") + ("\n" if head.strip() else "") + tail.lstrip("\n")

with open(env_file, "w", encoding="utf-8") as f:
    f.write(remaining)

print(f"Cleared the workshop_env block from {env_file} (those resources no longer exist).")
PYEOF
}

# Writes/replaces the workshop_env output into the repository-root .env,
# without touching any other settings already in that file.
write_env_block() {
  local env_file="$1" workshop_env_json="$2"

  python3 - "$env_file" "$workshop_env_json" <<'PYEOF'
import json, sys

env_file, raw_json = sys.argv[1], sys.argv[2]
workshop_env = json.loads(raw_json)  # single "KEY=VALUE\nKEY=VALUE\n..." string

start = "# --- tf-apply.sh workshop_env (auto-managed; safe to delete, will be rewritten) ---"
end = "# --- end tf-apply.sh workshop_env ---"

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

# Scans a log file for error patterns seen during this workshop's setup and
# prints the specific fix for each one found. Sets $FOUND_ANY=1 if at least
# one pattern matched (checked by the caller after invoking this).
FOUND_ANY=0
scan_known_issues() {
  local log_file="$1"
  FOUND_ANY=0

  _check_issue() {
    local pattern="$1" title="$2" fix="$3"
    if grep -qiE "$pattern" "$log_file"; then
      FOUND_ANY=1
      printf '\n--- %s ---\n%s\n' "$title" "$fix"
    fi
  }

  _check_issue \
    'dial tcp: lookup .* no such host|Could not resolve host|Name or service not known|NameResolutionError' \
    "Corporate DNS cannot resolve an Azure hostname" \
    "This should have been auto-patched above. If it's still failing: the hostname may be new
and not yet covered by the DNS-patch step, or DNS-over-HTTPS itself returned nothing
(propagation lag for a brand-new/just-deleted resource -- wait ~60s and rerun).
Manual recipe: see the 'Troubleshooting: corporate DNS' section in NON-DOCKER-SETUP.md."

  _check_issue \
    'Plugin did not respond' \
    "Terraform provider plugin hung and was considered unresponsive" \
    "Usually caused by the DNS issue above: a slow/hanging DNS lookup during a resource
refresh can exceed the provider's internal timeout. Check the resource named just above this
error, make sure its hostname is patched in /etc/hosts (rerunning should catch it), and retry."

  _check_issue \
    'RequestConflict: Another operation is in progress' \
    "409 Conflict: another operation in progress on the Foundry/Cognitive Services account" \
    "Transient -- the account's internal write lock from a previous call (e.g. a model
deployment) hadn't released yet. Just rerun the script.
If it recurs repeatedly, rerun with -parallelism=1 to serialize writes against the account."

  _check_issue \
    'VaultAlreadyExists|recently deleted but not purged' \
    "Key Vault name collision (soft-deleted vault still exists under this name)" \
    "Vault names are globally unique across every Azure tenant. With this config's random
6-character suffix, a collision with your OWN previous deployment or another learner's is
astronomically unlikely but not impossible on an unlucky draw. Force a fresh suffix and retry:
  terraform apply -replace=random_string.unique_suffix
(Plain 'terraform apply' alone will retry the SAME already-computed suffix and fail again.)"

  _check_issue \
    'to be managed via Terraform this resource needs to be imported' \
    "A resource already exists in Azure but isn't in Terraform state" \
    "A previous partial apply likely created this successfully before a later step failed.
Find the resource address and ID in the error above, then run:
  terraform import '<resource_address>' '<azure_resource_id>'
Then rerun."

  _check_issue \
    'Foundry Account capabilityHost Not Found' \
    "Missing account-level capability host" \
    "This config already includes azapi_resource.foundry_account_capability_host in
standard-agent.tf (required by the live API for public Standard Agent setup, even though it's
undocumented). If you still see this, confirm that resource wasn't accidentally removed."

  _check_issue \
    'can only be (updated|deleted) by the workspace that created it' \
    "A connection resource is locked to a different internal 'workspace' surface" \
    "Known API quirk on certain azapi-managed connections (hit this with Application Insights,
since removed from this config). Terraform can't fix this via PUT/DELETE -- tell it to stop
managing the resource instead:
  terraform state rm '<resource_address>'
The orphaned object in Azure is harmless once its target resource is also gone."

  _check_issue \
    'rate_limit_exceeded|429' \
    "Model deployment rate limit (429) during a lab run, not terraform" \
    "Not a terraform error -- this happens when running a lab script.
The deployed capacity (variables.tf's model_deployments) may still be too low for your usage.
Bump the relevant model's capacity and reapply. Otherwise just retry the lab after ~60s; token
quota resets every minute."

  _check_issue \
    '"The definition field is required"|Could not find member .enablePublicHostingEnvironment' \
    "Capability host schema mismatch with published API docs" \
    "Already worked around in this config: standard-agent.tf creates the account-level
capability host with empty properties (no enablePublicHostingEnvironment, no customerSubnet),
which is what the live API actually accepts despite its own docs showing otherwise."

  _check_issue \
    'RequestConflict.*provisioning state is not terminal|provisioning state .* is not terminal' \
    "409 Conflict purging the Foundry/Cognitive Services account during destroy" \
    "Transient timing race: the purge call for the soft-deleted account fires just before its
own deletion has fully settled on Azure's side. The account is almost always already gone by
the time you see this -- confirm with:
  az cognitiveservices account list-deleted -o table
If it's not listed (or the error doesn't recur), the destroy already succeeded; just rerun
tf-destroy.sh and it will report nothing left to do. If it keeps recurring, increase
time_sleep.foundry_purge_cooldown's duration in standard-agent.tf (currently 60s)."

  unset -f _check_issue
}
