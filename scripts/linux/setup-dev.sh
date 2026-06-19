#!/usr/bin/env bash
# AISDLC dev-environment setup — get a new contributor ready to use this repo.
#
# Assumes WSL2 / Debian-Ubuntu (apt). If you're on another platform, install
# the listed tools yourself and skip the auto-install — the version checks at
# the end still tell you what's missing.
#
# Verifies (and installs, where it safely can) the harness prerequisites the
# runner and skills depend on:
#   git, jq, rsync, curl, wget, ca-certificates
#   yq               — mikefarah/yq Go binary (NOT the apt `yq` python wrapper;
#                      the manifest queries in scripts/ use mikefarah syntax)
#   Bitbucket auth   — the runner opens PRs and posts comments through REST
#
# Anything needing sudo or secret setup is left for you to run in your own
# terminal — this script prints the exact command.
#
# The `init-greenfield` skill appends a stack-specific block below the marker
# near the bottom of this file once the project's stack is settled.
#
# Usage:
#   bash scripts/linux/setup-dev.sh            # check + install missing baseline tools
#   bash scripts/linux/setup-dev.sh --check    # report only, install nothing

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_REPO="$REPO_ROOT/code"

CHECK_ONLY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

log()  { echo "[setup] $*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
have_deb() { dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii '; }
is_wsl() { [ -r /proc/version ] && grep -qi microsoft /proc/version; }

MISSING=()        # tools still missing after this run
MANUAL=()         # commands the dev must run themselves (sudo / interactive)

apt_install() {
  local pkg="$1"
  if [ "$CHECK_ONLY" = 1 ]; then
    MANUAL+=("sudo apt-get install -y $pkg")
    return
  fi
  log "installing $pkg via apt..."
  if ! sudo apt-get install -y "$pkg" >/dev/null 2>&1; then
    MANUAL+=("sudo apt-get install -y $pkg")
  fi
}

# --- plain apt packages ------------------------------------------------------

for pkg in git jq rsync curl wget; do
  if have "$pkg"; then
    log "ok: $pkg ($(command -v "$pkg"))"
  else
    log "missing: $pkg"
    apt_install "$pkg"
    have "$pkg" || MISSING+=("$pkg")
  fi
done

if have_deb ca-certificates; then
  log "ok: ca-certificates ($(dpkg-query -W -f='${Version}' ca-certificates 2>/dev/null))"
else
  log "missing: ca-certificates"
  apt_install ca-certificates
  have_deb ca-certificates || MISSING+=("ca-certificates")
fi

for tool in timeout setsid; do
  if have "$tool"; then
    log "ok: $tool ($(command -v "$tool"))"
  else
    case "$tool" in
      timeout) apt_install coreutils ;;
      setsid) apt_install util-linux ;;
    esac
    have "$tool" || MISSING+=("$tool")
  fi
done

# --- yq : must be mikefarah's Go build, not the apt python wrapper -----------

YQ_VERSION="v4.44.3"
YQ_BIN="/usr/local/bin/yq"

install_yq() {
  if [ "$CHECK_ONLY" = 1 ]; then
    MANUAL+=("sudo wget -q https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 -O ${YQ_BIN} && sudo chmod +x ${YQ_BIN}")
    return
  fi
  log "installing mikefarah/yq ${YQ_VERSION} -> ${YQ_BIN} ..."
  if sudo wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -O "${YQ_BIN}" \
     && sudo chmod +x "${YQ_BIN}"; then
    :
  else
    MANUAL+=("sudo wget -q https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 -O ${YQ_BIN} && sudo chmod +x ${YQ_BIN}")
  fi
}

if have yq; then
  if yq --version 2>&1 | grep -qi mikefarah; then
    log "ok: yq ($(yq --version 2>&1))"
  else
    log "WARN: a non-mikefarah 'yq' is on PATH ($(command -v yq)) — the apt 'yq' is a different tool and breaks manifest queries."
    log "      remove it (sudo apt-get remove -y yq) and re-run, or install the mikefarah binary manually."
    MISSING+=("yq (wrong build on PATH)")
  fi
else
  log "missing: yq"
  install_yq
  have yq || MISSING+=("yq")
fi

# --- Bitbucket auth ----------------------------------------------------------

windows_home_from_repo() {
  case "$REPO_ROOT" in
    /mnt/*/Users/*/*) echo "$REPO_ROOT" | sed -E 's#^(/mnt/[^/]+/Users/[^/]+).*$#\1#' ;;
    /?/[Uu]sers/*/*) echo "$REPO_ROOT" | sed -E 's#^(/[^/]+/[Uu]sers/[^/]+).*$#\1#' ;;
  esac
}

codex_config_candidates() {
  [ -n "${CODEX_CONFIG:-}" ] && echo "$CODEX_CONFIG"
  [ -n "${HOME:-}" ] && echo "$HOME/.codex/config.toml"
  local win_home
  win_home=$(windows_home_from_repo || true)
  [ -n "$win_home" ] && echo "$win_home/.codex/config.toml"
}

read_codex_config_key() {
  local key="$1" file value
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ -f "$file" ] || continue
    value=$(sed -nE "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*$/\1/p" "$file" | tail -n 1)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done < <(codex_config_candidates | awk '!seen[$0]++')
  return 1
}

load_secret() {
  local var="$1" value
  value="${!var:-}"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi
  read_codex_config_key "$var"
}

if ! have jq || ! have curl; then
  log "skipping Bitbucket auth check until jq and curl are available"
elif [ ! -f "$REPO_ROOT/.codex/aisdlc.json" ]; then
  log "missing $REPO_ROOT/.codex/aisdlc.json"
  MISSING+=("aisdlc.json")
else
SCM_PROVIDER=$(jq -r '.sourceControl.provider // "bitbucket"' "$REPO_ROOT/.codex/aisdlc.json" 2>/dev/null || echo "bitbucket")
if [ "$SCM_PROVIDER" = "bitbucket" ]; then
  BB_BASE_URL=$(jq -r '.sourceControl.baseUrl // empty' "$REPO_ROOT/.codex/aisdlc.json")
  BB_PROJECT_KEY=$(jq -r '.sourceControl.projectKey // empty' "$REPO_ROOT/.codex/aisdlc.json")
  BB_REPO_SLUG=$(jq -r '.sourceControl.repositorySlug // empty' "$REPO_ROOT/.codex/aisdlc.json")
  BB_TOKEN_ENV=$(jq -r '.sourceControl.apiTokenEnv // "BITBUCKET_API_TOKEN"' "$REPO_ROOT/.codex/aisdlc.json")
  BB_TOKEN=$(load_secret "$BB_TOKEN_ENV" 2>/dev/null || true)

  if [ -z "$BB_BASE_URL" ] || [ -z "$BB_PROJECT_KEY" ] || [ -z "$BB_REPO_SLUG" ]; then
    log "missing Bitbucket sourceControl config in .codex/aisdlc.json"
    MISSING+=("bitbucket-config")
  elif [ -z "$BB_TOKEN" ]; then
    log "missing Bitbucket API token ($BB_TOKEN_ENV)"
    MANUAL+=("export $BB_TOKEN_ENV=...   # or add $BB_TOKEN_ENV to your Codex config")
    MISSING+=("$BB_TOKEN_ENV")
  else
    bb_check_error=""
    if bb_check_error=$(curl -fsS \
      -H "Authorization: Bearer $BB_TOKEN" \
      -H "Accept: application/json" \
      "$BB_BASE_URL/rest/api/latest/projects/$BB_PROJECT_KEY/repos/$BB_REPO_SLUG" 2>&1 >/dev/null); then
      log "ok: Bitbucket auth for $BB_PROJECT_KEY/$BB_REPO_SLUG"
    else
      log "Bitbucket auth/network check failed for $BB_PROJECT_KEY/$BB_REPO_SLUG"
      [ -n "$bb_check_error" ] && log "curl: $(printf '%s' "$bb_check_error" | tr '\n' ' ')"
      MANUAL+=("verify $BB_TOKEN_ENV can read $BB_BASE_URL/projects/$BB_PROJECT_KEY/repos/$BB_REPO_SLUG")
      MISSING+=("bitbucket-auth")
    fi
  fi
else
  log "unsupported sourceControl.provider: $SCM_PROVIDER"
  MISSING+=("sourceControl.provider")
fi
fi

# --- stack-specific (managed by init-greenfield) ----------------------------
# init-greenfield appends this project's stack setup below this line.

# Deals AISDLC support repo: application commands run from the nested Corpay monorepo.
# Verify the global tools needed to carry assets and work in the target stack.

if [ -d "$APP_REPO" ]; then
  log "ok: nested Corpay monorepo path exists ($APP_REPO)"
  if git -C "$APP_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "ok: code/ is a git repository"
  else
    log "warning: code/ exists but git cannot inspect it"
    MANUAL+=("git config --global --add safe.directory '$APP_REPO'   # if git reports dubious ownership")
  fi
else
  log "missing: nested Corpay monorepo at $APP_REPO"
  MANUAL+=("clone or move the Corpay monorepo to '$APP_REPO'")
fi

if have codex; then
  log "ok: codex ($(command -v codex))"
else
  log "missing: codex"
  MANUAL+=("install Codex CLI, then re-run bash scripts/linux/setup-dev.sh")
  MISSING+=("codex")
fi

if have dotnet; then
  log "ok: dotnet ($(dotnet --version 2>/dev/null || command -v dotnet))"
else
  log "missing: dotnet"
  MANUAL+=("install the .NET SDK used by the Deals monorepo")
  MISSING+=("dotnet")
fi

if have node; then
  log "ok: node ($(node --version 2>/dev/null || command -v node))"
else
  log "missing: node"
  MANUAL+=("install the Node.js LTS/runtime version used by the Deals monorepo")
  MISSING+=("node")
fi

if have npm; then
  npm_path=$(command -v npm)
  if is_wsl && case "$npm_path" in /mnt/c/*) true ;; *) false ;; esac; then
    log "WARN: npm resolves to Windows interop ($npm_path); install Node.js inside WSL for Linux builds."
    MISSING+=("npm")
  else
    log "ok: npm ($(npm --version 2>/dev/null || command -v npm))"
  fi
else
  log "missing: npm"
  MANUAL+=("install npm or the package manager used by the Deals monorepo")
  MISSING+=("npm")
fi

log "note: no React/.NET dependencies are installed at the harness root; run discovered project commands from code/."

# --- summary ----------------------------------------------------------------

echo "" >&2
if [ ${#MISSING[@]} -eq 0 ] && [ ${#MANUAL[@]} -eq 0 ]; then
  log "all set — baseline tooling present and Bitbucket auth verified."
  exit 0
fi

if [ ${#MANUAL[@]} -gt 0 ]; then
  log "run these yourself (need sudo / secret setup):"
  for c in "${MANUAL[@]}"; do log "  $c"; done
fi
if [ ${#MISSING[@]} -gt 0 ]; then
  log "still missing after this run: ${MISSING[*]}"
fi
log "re-run \`bash scripts/linux/setup-dev.sh\` after addressing the above."
exit 1
