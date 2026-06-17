#!/usr/bin/env bash
# AISDLC dev-environment setup — get a new contributor ready to use this repo.
#
# Assumes WSL2 / Debian-Ubuntu (apt). If you're on another platform, install
# the listed tools yourself and skip the auto-install — the version checks at
# the end still tell you what's missing.
#
# Verifies (and installs, where it safely can) the harness prerequisites the
# runner and skills depend on:
#   git, jq, rsync   — standard apt packages
#   yq               — mikefarah/yq Go binary (NOT the apt `yq` python wrapper;
#                      the manifest queries in .codex/scripts/ use mikefarah syntax)
#   gh               — GitHub CLI (the runner pushes, opens PRs, posts comments)
#
# Anything needing sudo or an interactive login (`gh auth login`) is left for
# you to run in your own terminal — this script prints the exact command.
#
# The `init-greenfield` skill appends a stack-specific block below the marker
# near the bottom of this file once the project's stack is settled.
#
# Usage:
#   bash .codex/scripts/setup-dev.sh            # check + install missing baseline tools
#   bash .codex/scripts/setup-dev.sh --check    # report only, install nothing

set -uo pipefail

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

# --- git / jq / rsync : plain apt packages ----------------------------------

for pkg in git jq rsync; do
  if have "$pkg"; then
    log "ok: $pkg ($(command -v "$pkg"))"
  else
    log "missing: $pkg"
    apt_install "$pkg"
    have "$pkg" || MISSING+=("$pkg")
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

# --- gh : GitHub CLI via the official apt repo ------------------------------

install_gh() {
  if [ "$CHECK_ONLY" = 1 ]; then
    MANUAL+=("see https://github.com/cli/cli/blob/trunk/docs/install_linux.md (apt repo setup, then: sudo apt-get install -y gh)")
    return
  fi
  log "installing gh via the official GitHub CLI apt repo..."
  if sudo mkdir -p -m 755 /etc/apt/keyrings \
     && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
     && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
     && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
     && sudo apt-get update >/dev/null 2>&1 \
     && sudo apt-get install -y gh >/dev/null 2>&1; then
    :
  else
    MANUAL+=("install gh: https://github.com/cli/cli/blob/trunk/docs/install_linux.md")
  fi
}

if have gh; then
  log "ok: gh ($(command -v gh))"
else
  log "missing: gh"
  install_gh
  have gh || MISSING+=("gh")
fi

# --- gh auth : interactive, cannot be automated -----------------------------

if have gh; then
  if gh auth status >/dev/null 2>&1; then
    log "ok: gh authenticated"
  else
    log "gh is installed but not authenticated"
    MANUAL+=("gh auth login   # interactive — run this in your own terminal")
  fi
fi

# --- stack-specific (managed by init-greenfield) ----------------------------
# init-greenfield appends this project's stack setup below this line.

# Deals AISDLC support repo: application commands run from the Corpay monorepo.
# Verify the global tools needed to carry assets and work in the target stack.

if have codex; then
  log "ok: codex ($(command -v codex))"
else
  log "missing: codex"
  MANUAL+=("install Codex CLI, then re-run bash .codex/scripts/setup-dev.sh")
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
  log "ok: npm ($(npm --version 2>/dev/null || command -v npm))"
else
  log "missing: npm"
  MANUAL+=("install npm or the package manager used by the Deals monorepo")
  MISSING+=("npm")
fi

log "note: no React/.NET dependencies are installed here; run discovered project commands from the Corpay monorepo."

# --- summary ----------------------------------------------------------------

echo "" >&2
if [ ${#MISSING[@]} -eq 0 ] && [ ${#MANUAL[@]} -eq 0 ]; then
  log "all set — baseline tooling present and gh authenticated."
  exit 0
fi

if [ ${#MANUAL[@]} -gt 0 ]; then
  log "run these yourself (need sudo / interactive login):"
  for c in "${MANUAL[@]}"; do log "  $c"; done
fi
if [ ${#MISSING[@]} -gt 0 ]; then
  log "still missing after this run: ${MISSING[*]}"
fi
log "re-run \`bash .codex/scripts/setup-dev.sh\` after addressing the above."
exit 1
