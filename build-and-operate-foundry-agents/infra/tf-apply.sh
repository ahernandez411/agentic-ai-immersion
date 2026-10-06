#!/usr/bin/env bash
# tf-apply.sh: runs the full terraform workflow for this workshop's
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
#   bash tf-apply.sh

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck source=tf-lib.sh
source "$SCRIPT_DIR/tf-lib.sh"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/apply-$(date +%Y%m%d-%H%M%S).log"

# ---------------------------------------------------------------------------
# Step 1: the full terraform pipeline, stopping at the first failure.
# terraform apply alone already computes and displays the plan, then asks
# for interactive "yes" confirmation before doing anything -- no separate
# `terraform plan` step needed.
# ---------------------------------------------------------------------------
STEP_EXIT=0

run_step "$LOG_FILE" "terraform init -upgrade" terraform init -upgrade -input=false || STEP_EXIT=$?
if ((STEP_EXIT == 0)); then
  run_step "$LOG_FILE" "terraform fmt" terraform fmt || STEP_EXIT=$?
fi
if ((STEP_EXIT == 0)); then
  run_step "$LOG_FILE" "terraform validate" terraform validate || STEP_EXIT=$?
fi
if ((STEP_EXIT == 0)); then
  run_step "$LOG_FILE" "terraform apply" terraform apply || STEP_EXIT=$?
fi

APPLY_EXIT=$STEP_EXIT

# ---------------------------------------------------------------------------
# Step 2: on success, patch /etc/hosts for every real hostname this
# deployment produced, and write the workshop_env output into .env.
# ---------------------------------------------------------------------------
if ((APPLY_EXIT == 0)); then
  status "Patching /etc/hosts for deployment hostnames (corporate DNS workaround)"
  outputs_json="$(terraform output -json 2>/dev/null)"
  if [[ -n "$outputs_json" ]]; then
    patch_dns_for_hosts "$(extract_hostnames "$outputs_json")"
  else
    echo "Could not read terraform output; skipping DNS patch."
  fi

  status "Writing workshop values into the repository-root .env"
  repo_root="$SCRIPT_DIR/../.."
  env_file="$repo_root/.env"
  if [[ ! -f "$env_file" && -f "$repo_root/.env.example" ]]; then
    cp "$repo_root/.env.example" "$env_file"
    echo "Created .env from .env.example"
  fi
  workshop_env_json="$(terraform output -json workshop_env 2>/dev/null)"
  if [[ -n "$workshop_env_json" ]]; then
    write_env_block "$env_file" "$workshop_env_json"
  else
    echo "Could not read the workshop_env output; skipping .env update."
  fi
fi

# ---------------------------------------------------------------------------
# Step 3: scan the captured log for error patterns seen during this
# workshop's setup, and print the specific fix for each one found.
# ---------------------------------------------------------------------------
status "Checking apply output against known issues"
scan_known_issues "$LOG_FILE"

if ((APPLY_EXIT != 0 && FOUND_ANY == 0)); then
  printf '\nApply failed but no known pattern matched. Re-run with the full error and ask for help; log saved at: %s\n' "$LOG_FILE"
fi

exit "$APPLY_EXIT"
