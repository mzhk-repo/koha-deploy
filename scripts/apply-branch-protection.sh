#!/usr/bin/env bash
# Script Purpose: Apply GitHub branch protection to main (no direct push, required review, required checks).
# Usage: ./scripts/apply-branch-protection.sh [--repo owner/name] [--branch main] [--checks "check1,check2"] [--apply]
set -euo pipefail

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./scripts/apply-branch-protection.sh [options]

Options:
  --repo owner/name      GitHub repo (default: parsed from git remote origin)
  --branch BRANCH        Branch to protect (default: main)
  --checks a,b,c         Required status checks contexts (default: gitleaks)
  --apply                Apply settings via GitHub API (requires GITHUB_TOKEN)
  --dry-run              Print API payload only (default behavior)
  --help                 Show help

Environment:
  GITHUB_TOKEN           GitHub token with repo admin permissions (required only with --apply)
USAGE
}

infer_repo() {
  local remote url cleaned
  remote="$(git remote get-url origin 2>/dev/null || true)"
  [ -n "${remote}" ] || die "Cannot infer repo from git remote origin. Use --repo owner/name."

  # Supports: https://github.com/owner/repo.git and git@github.com:owner/repo.git
  url="${remote}"
  cleaned="${url#git@github.com:}"
  cleaned="${cleaned#https://github.com/}"
  cleaned="${cleaned%.git}"
  [ "${cleaned}" != "${url}" ] || true
  printf '%s\n' "${cleaned}"
}

main() {
  local repo=""
  local branch="main"
  local checks_csv="gitleaks"
  local do_apply=false

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        shift
        [ "$#" -gt 0 ] || die "--repo requires value"
        repo="$1"
        ;;
      --branch)
        shift
        [ "$#" -gt 0 ] || die "--branch requires value"
        branch="$1"
        ;;
      --checks)
        shift
        [ "$#" -gt 0 ] || die "--checks requires value"
        checks_csv="$1"
        ;;
      --apply)
        do_apply=true
        ;;
      --dry-run)
        do_apply=false
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1 (use --help)"
        ;;
    esac
    shift
  done

  [ -n "${repo}" ] || repo="$(infer_repo)"

  local owner name
  owner="${repo%%/*}"
  name="${repo##*/}"
  [ -n "${owner}" ] && [ -n "${name}" ] || die "Invalid repo format: ${repo} (expected owner/name)"

  local checks_json=""
  local c
  IFS=',' read -r -a arr <<<"${checks_csv}"
  for c in "${arr[@]}"; do
    c="$(printf '%s' "${c}" | xargs)"
    [ -n "${c}" ] || continue
    if [ -n "${checks_json}" ]; then
      checks_json="${checks_json}, "
    fi
    checks_json="${checks_json}\"${c}\""
  done
  [ -n "${checks_json}" ] || die "No required checks provided"

  local payload
  payload="$(cat <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": [${checks_json}]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": true
}
JSON
)"

  log "Target repo: ${owner}/${name}"
  log "Target branch: ${branch}"
  log "Required checks: ${checks_csv}"

  if ! ${do_apply}; then
    log "Dry-run mode. Payload to apply:"
    printf '%s\n' "${payload}"
    exit 0
  fi

  [ -n "${GITHUB_TOKEN:-}" ] || die "GITHUB_TOKEN is required for --apply"

  local api="https://api.github.com/repos/${owner}/${name}/branches/${branch}/protection"
  log "Applying branch protection via GitHub API..."

  curl -fsS -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${api}" \
    -d "${payload}" >/dev/null

  log "Branch protection applied successfully for ${owner}/${name}:${branch}"
}

main "$@"
