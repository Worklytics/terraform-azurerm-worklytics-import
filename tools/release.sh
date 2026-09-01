#!/usr/bin/env bash
# REQUIRES: git, gh
# DESCRIPTION: Cut a Terraform Registry module release by tagging origin/main
# after a clean tree and required GitHub checks. Pushing the tag is what the
# Registry indexes; the tag-triggered workflow then creates the GitHub Release.
#
# Usage: ./tools/release.sh vX.Y.Z [--wait] [--dry-run]

set -euo pipefail

# -- Colors --
RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RESET='\033[0m'

# Branch-protection gate job names (see .github/workflows/*.yaml).
REQUIRED_CHECKS=(
  'Terraform lint'
  'Terraform validate'
  'Terraform integration'
)
WAIT_TIMEOUT_SECS=1800
POLL_SECS=15

VERSION=""
WAIT=0
DRY_RUN=0
OWNER_REPO=""

usage() {
  cat <<'EOF'
Usage: ./tools/release.sh vX.Y.Z [--wait] [--dry-run]

Tag origin/main and push the tag so:
  1. Terraform Registry can pick up the version (git tags, not GitHub Releases)
  2. .github/workflows/release.yaml can create the GitHub Release notes

Does not create the GitHub Release itself (that would race the workflow).
The public registry indexes the new tag via webhook.

Options:
  --wait      Poll until required checks on origin/main complete (default: fail if pending)
  --dry-run   Print what would happen; do not tag or push
  -h, --help  Show this help
EOF
}

die() {
  echo -e "${RED}ERROR: $*${RESET}" >&2
  exit 1
}

info() {
  echo -e "$*"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --wait)
        WAIT=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        if [[ -n "$VERSION" ]]; then
          die "unexpected argument: $1"
        fi
        VERSION="$1"
        shift
        ;;
    esac
  done

  [[ -n "$VERSION" ]] || { usage >&2; die "version is required (e.g. v0.1.0)"; }
  [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    die "version must match vMAJOR.MINOR.PATCH (got ${BLUE}${VERSION}${RESET})"
}

require_tools() {
  local cmd
  for cmd in git gh; do
    if ! command -v "$cmd" &>/dev/null; then
      die "$cmd is required but not installed."
    fi
  done
}

bare_version() {
  echo "${VERSION#v}"
}

ensure_clean_and_main() {
  if [[ -n "$(git status --porcelain)" ]]; then
    die "working tree is not clean; commit or stash first (refusing to reset)."
  fi

  git fetch origin main
  git checkout main
  git pull --ff-only origin main

  local local_sha remote_sha
  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(git rev-parse origin/main)"
  if [[ "$local_sha" != "$remote_sha" ]]; then
    die "HEAD (${BLUE}${local_sha}${RESET}) is not origin/main (${BLUE}${remote_sha}${RESET})"
  fi
}

ensure_changelog() {
  local ver
  ver="$(bare_version)"
  [[ -f CHANGELOG.md ]] || die "CHANGELOG.md is missing"
  if ! grep -qE "^## \[${ver}\]" CHANGELOG.md; then
    die "CHANGELOG.md has no ## [${ver}] section"
  fi
}

ensure_tag_available() {
  if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
    die "local tag ${BLUE}${VERSION}${RESET} already exists"
  fi
  if git ls-remote --tags origin "refs/tags/${VERSION}" | grep -q .; then
    die "origin already has tag ${BLUE}${VERSION}${RESET}"
  fi
}

# name<TAB>status<TAB>conclusion for each required check (missing => empty status)
check_state() {
  local sha="$1"
  local all name row status conclusion
  all="$(gh api "repos/${OWNER_REPO}/commits/${sha}/check-runs?per_page=100" \
    --jq '.check_runs[] | [.name, (.status // ""), (.conclusion // "")] | @tsv')"

  for name in "${REQUIRED_CHECKS[@]}"; do
    row="$(printf '%s\n' "$all" | awk -F '\t' -v n="$name" '$1 == n { line = $0 } END { print line }')"
    status="$(printf '%s\n' "$row" | awk -F '\t' '{ print $2 }')"
    conclusion="$(printf '%s\n' "$row" | awk -F '\t' '{ print $3 }')"
    printf '%s\t%s\t%s\n' "$name" "$status" "$conclusion"
  done
}

summarize_checks() {
  local sha="$1"
  local name status conclusion
  while IFS=$'\t' read -r name status conclusion; do
    if [[ -z "$status" ]]; then
      info "  ${name}: ${RED}missing${RESET}"
    elif [[ "$status" != "completed" ]]; then
      info "  ${name}: ${BLUE}${status}${RESET}"
    elif [[ "$conclusion" == "success" ]]; then
      info "  ${name}: ${GREEN}success${RESET}"
    else
      info "  ${name}: ${RED}${conclusion:-unknown}${RESET}"
    fi
  done < <(check_state "$sha")
}

# stdout: success | failed | pending
checks_verdict() {
  local sha="$1"
  local pending=0 name status conclusion
  while IFS=$'\t' read -r name status conclusion; do
    if [[ "$status" == "completed" && "$conclusion" == "success" ]]; then
      continue
    fi
    if [[ "$status" == "completed" ]]; then
      echo failed
      return 0
    fi
    pending=1
  done < <(check_state "$sha")
  if [[ "$pending" -eq 1 ]]; then
    echo pending
  else
    echo success
  fi
}

ensure_checks() {
  local sha="$1"
  local verdict

  info "Required checks on ${BLUE}${sha}${RESET}:"
  summarize_checks "$sha"
  verdict="$(checks_verdict "$sha")"

  if [[ "$verdict" == "success" ]]; then
    return 0
  fi
  if [[ "$verdict" == "failed" ]]; then
    die "a required check failed on origin/main; not tagging."
  fi

  if [[ "$WAIT" -ne 1 ]]; then
    die "required checks are pending. Re-run with ${BLUE}--wait${RESET} after CI finishes, or pass --wait to poll."
  fi

  info "Waiting up to ${WAIT_TIMEOUT_SECS}s for checks..."
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECS))
  while (( SECONDS < deadline )); do
    sleep "$POLL_SECS"
    verdict="$(checks_verdict "$sha")"
    if [[ "$verdict" == "success" ]]; then
      info "Required checks on ${BLUE}${sha}${RESET}:"
      summarize_checks "$sha"
      return 0
    fi
    if [[ "$verdict" == "failed" ]]; then
      summarize_checks "$sha"
      die "a required check failed on origin/main; not tagging."
    fi
    info "  still pending..."
  done
  summarize_checks "$sha"
  die "timed out waiting for required checks on ${sha}"
}

tag_and_push() {
  local sha="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "${GREEN}Dry run.${RESET} Would annotated-tag ${BLUE}${VERSION}${RESET} at ${BLUE}${sha}${RESET} and push to origin."
    return 0
  fi

  git tag -a "$VERSION" -m "Release ${VERSION}"
  git push origin "$VERSION"
  info "${GREEN}Pushed tag ${BLUE}${VERSION}${RESET}${GREEN} at ${BLUE}${sha}${RESET}${GREEN}.${RESET}"
  info "GitHub Actions should create the GitHub Release; Terraform Registry will index the tag."
}

main() {
  parse_args "$@"
  require_tools
  OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

  info "Creating release ${GREEN}${VERSION}${RESET} from origin/main"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "(dry run)"
  fi

  ensure_clean_and_main
  local sha
  sha="$(git rev-parse HEAD)"
  info "origin/main is ${BLUE}${sha}${RESET}"

  ensure_changelog
  ensure_tag_available
  ensure_checks "$sha"
  tag_and_push "$sha"
}

main "$@"
