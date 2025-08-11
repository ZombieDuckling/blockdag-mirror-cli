#!/usr/bin/env bash

###############################################################################
# BlockDAG Repository Mirroring MVP
#
# This script implements a minimal viable product (MVP) for the BlockDAG
# mirroring service described in the design documents.  The goal of the MVP
# is to provide a working example of the CRUD + RESYNC model without all the
# bells and whistles of the full production system.  It pulls repositories
# from a source GitHub organisation and mirrors them into three destination
# organisations.  Each destination organisation has its own access token and
# mirror directory.  The script is idempotent and can be run on a timer or
# manually to keep the destinations in sync with the source.
#
# Key features implemented:
#   - Read (R): list all repositories in the source organisation
#   - Create (C): ensure each repository exists at each destination
#   - Update (U): mirror (fetch and push --mirror) changes into each destination
#   - Delete (D) (soft): placeholder for tombstoning removed repositories
#   - Logging: each run generates a timestamped log file under the cache
#
# Features not yet implemented in this MVP:
#   - Weekly deep resync (full re-clone, LFS handling)
#   - Soft deletion (tombstone creation)
#   - State caching and resync based on previous run
#   - Slack/email notifications on errors
#   - Branch protection enforcement
#
# To run this script you must:
#   - Install Git, gh (GitHub CLI), and jq on the runner machine.
#   - Create Personal Access Tokens (PATs) for the source and each destination
#     organisation with the correct scopes.  At minimum the source token must
#     have repo read permissions and the destination tokens must have repo
#     admin permissions (create/delete).
#   - Export the following environment variables before running:
#       SRC_GH_TOKEN      – GitHub token for the source organisation
#       DST_STRAT_TOKEN   – GitHub token for the Strattice destination
#       DST_BRAIN_TOKEN   – GitHub token for the BrainstormOnline destination
#       DST_ENG_TOKEN     – GitHub token for the BlockDAG Engineering destination
#   - Optionally set SRC_ORG and destination org names; defaults provided.
#
# Example usage:
#   SRC_GH_TOKEN=ghs_source_token \
#   DST_STRAT_TOKEN=ghs_strattice_token \
#   DST_BRAIN_TOKEN=ghs_brain_token \
#   DST_ENG_TOKEN=ghs_eng_token \
#   ./mirror.sh
#
set -euo pipefail

#------------------------------------
# Configuration
#------------------------------------
# Source organisation name (the owner of the repositories to mirror).  Change
# this to match your actual source organisation.
SRC_ORG="blockdag-network-labs"

# Destination organisations.  These can be overridden via environment
# variables if your organisation names differ.  For example, you could run
# `DST_STRAT_ORG=MyOrg ./mirror.sh` to mirror into a different destination.
DST_STRAT_ORG="Strattice"
DST_BRAIN_ORG="BrainstormOnline"
DST_ENG_ORG="BlockDAG-Engineering"

# Root directory for all mirrors and temporary state.  Adjust this to
# wherever you want to store the local bare mirror clones.  Each
# destination will have its own subdirectory under this root.
ROOT="${ROOT:-/srv/mirrors}"

# Ensure the cache directory exists; this is where JSON listings and log
# files will be stored.  The `cache` directory must be inside ROOT
CACHE_DIR="$ROOT/cache"
mkdir -p "$CACHE_DIR"

# Create destination workspaces.  The script will clone bare mirrors into
# these directories.  The directory names correspond to the destination
# organisation names for clarity.
mkdir -p "$ROOT/strattice" "$ROOT/brainstormonline" "$ROOT/blockdag-engineering"

# Validate that required environment variables are set.  If any are missing,
# the script will exit with an error.  This prevents accidental runs
# without credentials.
: "${SRC_GH_TOKEN:?Set SRC_GH_TOKEN to your source PAT}"
: "${DST_STRAT_TOKEN:?Set DST_STRAT_TOKEN to your Strattice PAT}"
: "${DST_BRAIN_TOKEN:?Set DST_BRAIN_TOKEN to your BrainstormOnline PAT}"
: "${DST_ENG_TOKEN:?Set DST_ENG_TOKEN to your BlockDAG Engineering PAT}"

#------------------------------------
# Logging helpers
#------------------------------------
log_info() {
  echo "[INFO] $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[ERROR] $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" | tee -a "$LOG_FILE" >&2
}

# Generate a new log file for each run.  Logs are timestamped so you can
# reconstruct history.  You can rotate old logs manually or via a cron job.
LOG_FILE="$CACHE_DIR/run-$(date -u +'%Y%m%dT%H%M%SZ').log"
touch "$LOG_FILE"
log_info "=== Mirror run started ==="

#------------------------------------
# Helper functions
#------------------------------------
# ensure_repo
# Ensure that a repository exists in the given destination organisation.  If
# it does not, create it with the same visibility as the source (public or
# private).  This function uses the GitHub CLI (gh).  The destination token
# must be available as an environment variable when invoking gh commands.
#
# Arguments:
#   $1 – destination organisation name
#   $2 – destination token (PAT) for gh authentication
#   $3 – repository name
#   $4 – visibility (true if private, false if public)
ensure_repo() {
  local dst_org="$1"; shift
  local dst_token="$1"; shift
  local name="$1"; shift
  local private="$1"; shift

  # Set the visibility flag for gh repo create
  local vis_flag="--public"
  if [[ "$private" == "true" ]]; then
    vis_flag="--private"
  fi

  # Test if the repository already exists in the destination organisation.
  # Suppress output; we only care about the exit status.  We pass the
  # destination token via GITHUB_TOKEN so gh can authenticate correctly.
  if GITHUB_TOKEN="$dst_token" gh repo view "$dst_org/$name" >/dev/null 2>&1; then
    return 0
  fi

  # The repository does not exist; create it now.  The --confirm flag
  # suppresses the interactive prompt so the command can run unattended.
  log_info "Creating repository $dst_org/$name ($vis_flag)"
  GITHUB_TOKEN="$dst_token" gh repo create "$dst_org/$name" $vis_flag --confirm >/dev/null
}

# mirror_to
# Mirror a single repository to a specific destination.  This function will
# clone the repository as a bare mirror (if it has not been cloned yet),
# fetch the latest changes from the source, and push a mirror to the
# destination.  It creates a dest remote if one does not exist.  The
# function expects the source token to be available in SRC_GH_TOKEN and the
# destination token passed as an argument.
#
# Arguments:
#   $1 – destination organisation name
#   $2 – destination token (PAT)
#   $3 – workspace directory under which the bare mirror clone will live
#   $4 – repository name
#   $5 – SSH URL of the source repository
#
mirror_to() {
  local dst_org="$1"; shift
  local dst_token="$1"; shift
  local workspace="$1"; shift
  local name="$1"; shift
  local ssh_url="$1"; shift

  # Ensure the repo exists on the destination.  You must know whether it
  # should be private or public.  In this MVP we pass the visibility via
  # ensure_repo up front.
  # This function assumes ensure_repo has already been called.

  mkdir -p "$workspace"
  cd "$workspace"

  # Use a separate directory for each bare clone.  Suffix .git to make it
  # clear that this is a bare mirror.  The directory stores all branches
  # and tags; the mirror will be updated on each run.
  local bare_dir="$name.git"

  if [[ ! -d "$bare_dir" ]]; then
    log_info "Cloning $name into $bare_dir"
    # Use HTTPS URLs with tokens for authentication.  To convert the ssh_url
    # into an HTTPS URL, we strip the ssh:// prefix (if present) and
    # substitute github.com.  The SRC_GH_TOKEN will be embedded directly in
    # the URL for simplicity.  If your organisation uses enterprise
    # endpoints, adjust the domain accordingly.
    local https_url="https://${SRC_GH_TOKEN}@github.com/${SRC_ORG}/${name}.git"
    GIT_ASKPASS=/bin/true git clone --mirror "$https_url" "$bare_dir" || {
      log_error "Failed to clone $name"
      return 1
    }
  fi

  cd "$bare_dir"
  # Always fetch updates from the source.  Force update all refs.  We
  # override the origin URL each run to ensure the token is applied.
  local src_https_url="https://${SRC_GH_TOKEN}@github.com/${SRC_ORG}/${name}.git"
  git remote set-url origin "$src_https_url"
  log_info "Fetching updates for $name"
  GIT_ASKPASS=/bin/true git fetch --prune origin

  # Configure the destination remote if not present.  We name it "dest" for
  # clarity.  Embed the destination token in the URL for authentication.  The
  # mirror push will force update all refs, including deleting obsolete
  # branches on the destination.
  local dest_url="https://${dst_token}@github.com/${dst_org}/${name}.git"
  if ! git remote | grep -q '^dest$'; then
    git remote add dest "$dest_url"
  else
    git remote set-url dest "$dest_url"
  fi

  log_info "Pushing mirror to $dst_org/$name"
  GIT_ASKPASS=/bin/true git push --prune --mirror dest || {
    log_error "Push failed for $dst_org/$name"
    return 1
  }

  # Return to top-level to avoid issues if functions are nested
  cd - >/dev/null
}

#------------------------------------
# Main loop
#------------------------------------

log_info "Listing repositories from $SRC_ORG"

# Retrieve the full list of repositories from the source organisation.  We
# request all types (public, private, forks, archived) to ensure we mirror
# everything.  The results are saved into a JSON file.  gh will handle
# pagination automatically when the --paginate flag is set.
REPOS_JSON="$CACHE_DIR/repos.json"
GITHUB_TOKEN="$SRC_GH_TOKEN" gh api -H "Accept: application/vnd.github+json" \
  "/orgs/$SRC_ORG/repos?per_page=100&type=all" --paginate > "$REPOS_JSON"

log_info "Mirroring repositories"

# Iterate over each repository in the JSON file.  We use jq to extract
# relevant fields: name, private (true/false), ssh_url, and default_branch.
mapfile -t NAMES < <(jq -r '.[].name' "$REPOS_JSON")
for name in "${NAMES[@]}"; do
  # Pull values from the JSON for this repository
  private=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .private' "$REPOS_JSON")
  ssh_url=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .ssh_url' "$REPOS_JSON")

  # Ensure the repo exists in each destination.  We pass the visibility as
  # 'true' for private and 'false' for public.
  ensure_repo "$DST_STRAT_ORG" "$DST_STRAT_TOKEN" "$name" "$private"
  ensure_repo "$DST_BRAIN_ORG" "$DST_BRAIN_TOKEN" "$name" "$private"
  ensure_repo "$DST_ENG_ORG" "$DST_ENG_TOKEN" "$name" "$private"

  # Mirror the repository to each destination.  The workspace directories
  # correspond to the destination organisation names.  If any mirror
  # operation fails, we log the error but continue with the next repo.
  mirror_to "$DST_STRAT_ORG" "$DST_STRAT_TOKEN" "$ROOT/strattice" "$name" "$ssh_url" || true
  mirror_to "$DST_BRAIN_ORG" "$DST_BRAIN_TOKEN" "$ROOT/brainstormonline" "$name" "$ssh_url" || true
  mirror_to "$DST_ENG_ORG" "$DST_ENG_TOKEN" "$ROOT/blockdag-engineering" "$name" "$ssh_url" || true
done

log_info "Mirroring complete"
log_info "=== Mirror run finished ==="