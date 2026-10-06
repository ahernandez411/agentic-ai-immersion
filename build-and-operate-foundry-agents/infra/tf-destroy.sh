#!/usr/bin/env bash
# tf-destroy.sh: runs the full terraform teardown for this workshop's infra,
# failing fast on the first error.
#
# What it does:
#   1. terraform init -upgrade, then validate.
#   2. Patches /etc/hosts for every hostname in the CURRENT deployment's
#      outputs (DNS-over-HTTPS workaround) -- needed because `destroy` must
#      refresh/read each resource before it can delete it, which hits the
#      same corporate-DNS gap tf-apply.sh works around.
#   3. terraform destroy -- its normal interactive plan review and typed
#      confirmation (not just "yes") stays intact; nothing here bypasses it.
#   4. On a successful destroy, clears the auto-managed workshop_env block
#      from the repository-root .env, since those endpoints no longer exist.
#   5. Whether it succeeded or failed, scans the captured output for error
#      patterns hit during this workshop's setup and prints the specific fix
#      for each one found.
#
# Usage:
#   bash tf-destroy.sh

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck source=tf-lib.sh
source "$SCRIPT_DIR/tf-lib.sh"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/destroy-$(date +%Y%m%d-%H%M%S).log"

# ---------------------------------------------------------------------------
# Step 1: init + validate, stopping at the first failure.
# ---------------------------------------------------------------------------
STEP_EXIT=0

run_step "$LOG_FILE" "terraform init -upgrade" terraform init -upgrade -input=false -no-color || STEP_EXIT=$?
if ((STEP_EXIT == 0)); then
  run_step "$LOG_FILE" "terraform validate" terraform validate -no-color || STEP_EXIT=$?
fi

# ---------------------------------------------------------------------------
# Step 2: patch DNS for the CURRENT deployment before destroying it --
# destroy's own refresh step needs to resolve these hostnames to read each
# resource before it can delete it.
# ---------------------------------------------------------------------------
if ((STEP_EXIT == 0)); then
  status "Patching /etc/hosts for the current deployment (needed for destroy's refresh step)"
  outputs_json="$(terraform output -json 2>/dev/null)"
  if [[ -n "$outputs_json" ]]; then
    patch_dns_for_hosts "$(extract_hostnames "$outputs_json")"
  else
    echo "Could not read terraform output (state may already be empty); skipping DNS patch."
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: terraform destroy, with its normal interactive confirmation.
# ---------------------------------------------------------------------------
if ((STEP_EXIT == 0)); then
  run_step "$LOG_FILE" "terraform destroy" terraform destroy -no-color || STEP_EXIT=$?
fi

DESTROY_EXIT=$STEP_EXIT

# ---------------------------------------------------------------------------
# Step 4: on success, clear the stale workshop_env block from .env -- those
# endpoints no longer exist.
# ---------------------------------------------------------------------------
if ((DESTROY_EXIT == 0)); then
  status "Clearing the workshop_env block from the repository-root .env"
  clear_env_block "$SCRIPT_DIR/../../.env"
fi

# ---------------------------------------------------------------------------
# Step 5: scan the captured log for error patterns seen during this
# workshop's setup, and print the specific fix for each one found.
# ---------------------------------------------------------------------------
status "Checking destroy output against known issues"
scan_known_issues "$LOG_FILE"

if ((DESTROY_EXIT != 0 && FOUND_ANY == 0)); then
  printf '\nDestroy failed but no known pattern matched. Re-run with the full error and ask for help; log saved at: %s\n' "$LOG_FILE"
fi

exit "$DESTROY_EXIT"
