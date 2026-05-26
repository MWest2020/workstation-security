#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: installer
#
# common/install-shell-tools.sh — installeer shell-tooling die als pre-commit
# gates worden gebruikt: shfmt (formatter --check), pre-commit (Yelp's framework),
# gitleaks (secret-scanner) en jscpd (duplication-detector).
#
# Aanvullend op de bestaande shellcheck-installatie (via distro pkg manager).
# Geen overlap met install-pm-cooldown.sh of install-base.sh.
#
# Design-keuze: alle tools werken in --check / gate modus, niet auto-fix.
# Hetzelfde principe als iso-audit's .pre-commit-config.yaml — hooks zijn
# poortwachters, geen stille code-mutators. Anders gaan CI en lokaal uit
# elkaar lopen.
#
# Schrijft user-level installs (geen sudo):
#   ~/.local/bin/shfmt            (binary download, 7MB)
#   ~/.local/bin/gitleaks         (binary download, 12MB)
#   ~/.local/bin/pre-commit       (via pip --user)
#   ~/.npm-global/bin/jscpd       (via npm -g, gerouteerd naar ~/.npm-global
#                                  per existing convention in PATH)
#
# Style-afwijking: shebang via `env bash` voor consistentie met repo.
#
# Idempotent: re-run upserts. Tools die al de gewenste versie hebben worden
# overgeslagen (ws_skip), niet opnieuw gedownload.
#
# Usage:
#   bash common/install-shell-tools.sh             # install/update all
#   bash common/install-shell-tools.sh --check     # alleen huidige state tonen
#   bash common/install-shell-tools.sh --tool jscpd  # only one tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib.sh disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

readonly LOCAL_BIN="${HOME}/.local/bin"
readonly NPM_GLOBAL="${HOME}/.npm-global"

# Pinned versions — bump deliberately, document why in CHANGELOG.
readonly SHFMT_VERSION="3.10.0"
readonly GITLEAKS_VERSION="8.30.1"

# pre-commit and jscpd: latest stable from upstream (pip / npm). They get
# their own version-pinning in per-project .pre-commit-config.yaml / package.json,
# so we don't pin the global binary itself.

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
mode="install"
only_tool=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --tool)
      only_tool="$2"
      shift 2
      ;;
    --version | -V)
      echo "workstation-security $(ws_version)"
      exit 0
      ;;
    -h | --help)
      sed -n '2,30p' "$0" | sed 's/^# //;s/^#$//'
      exit 0
      ;;
    *)
      ws_fail "Onbekend argument: $1"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
arch_for_binary() {
  # Return: amd64 | arm64 — used in shfmt/gitleaks download URLs
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    *)
      ws_fail "Unsupported arch: $(uname -m)"
      return 1
      ;;
  esac
}

os_for_binary() {
  case "$(uname -s)" in
    Linux) echo "linux" ;;
    Darwin) echo "darwin" ;;
    *)
      ws_fail "Unsupported OS: $(uname -s)"
      return 1
      ;;
  esac
}

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    ws_ok "created $dir"
  fi
}

# Verify dat een bestand de verwachte sha256 heeft. Pure check — geen
# side-effects op het bestand zelf. Caller blijft verantwoordelijk voor
# cleanup (rm van een tmpfile op mismatch). Reden: deze helper weet niet
# of het een tmp-download is of een al-geïnstalleerd-binary; auto-delete
# zou onverwacht een geïnstalleerd-binary kunnen wissen bij een verkeerd-
# aangeroepen test of debug.
#
# Vereist sha256sum (coreutils). Bij mismatch: stderr + return 1.
#
# Ironie-fix: een tool die expliciet over supply-chain-paranoia gaat, mag zelf
# niet binaries downloaden zonder integriteits-verificatie. Defense in depth
# zonder veel werk — shfmt en gitleaks publiceren beide hun checksums.
verify_sha256() {
  local file="$1" expected="$2"
  if ! command -v sha256sum >/dev/null 2>&1; then
    ws_fail "sha256sum niet beschikbaar — kan checksum-verificatie niet uitvoeren"
    return 1
  fi
  if [[ -z "$expected" ]]; then
    ws_fail "Lege expected-checksum doorgegeven aan verify_sha256"
    return 1
  fi
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    ws_fail "SHA-256 mismatch op $(basename "$file"):"
    ws_info "  Expected: ${expected}"
    ws_info "  Actual:   ${actual}"
    return 1
  fi
  return 0
}

# Haal de verwachte sha256 op uit een upstream-published checksums-file.
# Format: '<sha256>  <filename>' per regel (standaard sha256sum -c format).
# Op fail (curl error, asset niet in file): return 1 + lege output.
fetch_expected_sha256() {
  local sums_url="$1" asset_name="$2"
  local sums_content
  if ! sums_content="$(curl -fsSL "$sums_url" 2>/dev/null)"; then
    return 1
  fi
  local sha
  sha="$(echo "$sums_content" | awk -v a="$asset_name" '$2 == a {print $1; exit}')"
  if [[ -z "$sha" ]]; then
    return 1
  fi
  printf '%s' "$sha"
}

# ---------------------------------------------------------------------------
# shfmt — formatter, used in --check mode in pre-commit
# ---------------------------------------------------------------------------
install_shfmt() {
  local dest="${LOCAL_BIN}/shfmt"
  local arch os url
  arch="$(arch_for_binary)"
  os="$(os_for_binary)"

  if [[ -x "$dest" ]]; then
    local current
    current="$("$dest" --version 2>/dev/null | tr -d 'v ')"
    if [[ "$current" == "$SHFMT_VERSION" ]]; then
      ws_skip "shfmt ${SHFMT_VERSION} already installed at ${dest}"
      return 0
    fi
    ws_info "shfmt upgrade: ${current} → ${SHFMT_VERSION}"
  fi

  local asset_name="shfmt_v${SHFMT_VERSION}_${os}_${arch}"
  url="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/${asset_name}"
  local sums_url="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/sha256sums.txt"

  local expected_sha
  if ! expected_sha="$(fetch_expected_sha256 "$sums_url" "$asset_name")"; then
    ws_fail "Kon expected sha256 niet ophalen voor ${asset_name}"
    ws_info "  Checked: ${sums_url}"
    return 1
  fi

  ensure_dir "$LOCAL_BIN"
  local tmp_file
  tmp_file="$(mktemp)"
  curl -fsSL "$url" -o "$tmp_file"
  if ! verify_sha256 "$tmp_file" "$expected_sha"; then
    rm -f "$tmp_file"
    return 1
  fi
  mv "$tmp_file" "$dest"
  chmod +x "$dest"
  ws_ok "installed shfmt ${SHFMT_VERSION} → ${dest} (sha256 verified)"
}

# ---------------------------------------------------------------------------
# gitleaks — secret scanner, gate in pre-commit
# ---------------------------------------------------------------------------
install_gitleaks() {
  local dest="${LOCAL_BIN}/gitleaks"
  local arch os url tarball
  arch="$(arch_for_binary)"
  os="$(os_for_binary)"

  if [[ -x "$dest" ]]; then
    local current
    current="$("$dest" version 2>/dev/null | head -1)"
    if [[ "$current" == "$GITLEAKS_VERSION" ]]; then
      ws_skip "gitleaks ${GITLEAKS_VERSION} already installed at ${dest}"
      return 0
    fi
    ws_info "gitleaks upgrade: ${current} → ${GITLEAKS_VERSION}"
  fi

  # Gitleaks uses 'x64' (not 'amd64') in its release asset naming.
  local gl_arch
  case "$arch" in
    amd64) gl_arch="x64" ;;
    arm64) gl_arch="arm64" ;;
    *)
      ws_fail "Unsupported arch for gitleaks: ${arch}"
      return 1
      ;;
  esac
  local asset_name="gitleaks_${GITLEAKS_VERSION}_${os}_${gl_arch}.tar.gz"
  url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${asset_name}"
  local sums_url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt"

  local expected_sha
  if ! expected_sha="$(fetch_expected_sha256 "$sums_url" "$asset_name")"; then
    ws_fail "Kon expected sha256 niet ophalen voor ${asset_name}"
    ws_info "  Checked: ${sums_url}"
    return 1
  fi

  ensure_dir "$LOCAL_BIN"
  tarball="$(mktemp)"
  curl -fsSL "$url" -o "$tarball"
  if ! verify_sha256 "$tarball" "$expected_sha"; then
    rm -f "$tarball"
    return 1
  fi
  tar -xzf "$tarball" -C "$LOCAL_BIN" gitleaks
  rm -f "$tarball"
  chmod +x "$dest"
  ws_ok "installed gitleaks ${GITLEAKS_VERSION} → ${dest} (sha256 verified)"
}

# ---------------------------------------------------------------------------
# pre-commit — Python framework that orchestrates hooks per project
# ---------------------------------------------------------------------------
install_pre_commit() {
  if command -v pre-commit >/dev/null 2>&1; then
    ws_skip "pre-commit already installed ($(pre-commit --version 2>&1 | head -1))"
    return 0
  fi

  if ! command -v pip >/dev/null 2>&1 && ! command -v pip3 >/dev/null 2>&1; then
    ws_fail "pip/pip3 niet gevonden — installeer eerst python3-pip via install-base.sh"
    return 1
  fi

  # Prefer pipx if available (cleaner — avoids polluting user-site).
  if command -v pipx >/dev/null 2>&1; then
    pipx install pre-commit
    ws_ok "installed pre-commit via pipx"
  else
    local pip
    pip="$(command -v pip3 || command -v pip)"
    "$pip" install --user pre-commit
    ws_ok "installed pre-commit via ${pip} --user"
    ws_warn "consider 'pipx' for isolated installs (https://pipx.pypa.io)"
  fi
}

# ---------------------------------------------------------------------------
# jscpd — duplication detector. Token-based, supports bash via --languages bash.
# ---------------------------------------------------------------------------
install_jscpd() {
  if command -v jscpd >/dev/null 2>&1; then
    ws_skip "jscpd already installed ($(jscpd --version 2>&1 | head -1))"
    return 0
  fi

  if ! command -v npm >/dev/null 2>&1; then
    ws_fail "npm niet gevonden — installeer eerst node via install-base.sh"
    return 1
  fi

  # Use ~/.npm-global per workstation convention (already in PATH).
  ensure_dir "$NPM_GLOBAL"
  npm config set prefix "$NPM_GLOBAL" --location=user

  # jscpd is published with postinstall scripts that just download wasm parsers —
  # not the kind of postinstall that pulls arbitrary network deps. Still, run
  # with --ignore-scripts first to be safe, then verify.
  npm install -g --ignore-scripts jscpd
  ws_ok "installed jscpd → ${NPM_GLOBAL}/bin/jscpd"
}

# ---------------------------------------------------------------------------
# check mode — report current state without changes
# ---------------------------------------------------------------------------
check_state() {
  ws_info "Shell tooling state on this workstation:"
  for tool in shellcheck shfmt gitleaks pre-commit jscpd; do
    if command -v "$tool" >/dev/null 2>&1; then
      local version
      version="$("$tool" --version 2>&1 | head -1 | tr -d '\n')"
      ws_ok "${tool} — ${version}"
    else
      ws_fail "${tool} — niet geïnstalleerd"
    fi
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if [[ "$mode" == "check" ]]; then
    check_state
    return 0
  fi

  # PATH sanity
  if ! echo ":$PATH:" | grep -q ":${LOCAL_BIN}:"; then
    ws_warn "${LOCAL_BIN} niet in PATH — voeg toe aan ~/.bashrc / ~/.zshrc:"
    # shellcheck disable=SC2016  # literal-string is opzet: gebruiker copy-paste't dit
    ws_warn '    export PATH="$HOME/.local/bin:$PATH"'
  fi
  if ! echo ":$PATH:" | grep -q ":${NPM_GLOBAL}/bin:"; then
    ws_warn "${NPM_GLOBAL}/bin niet in PATH — voeg toe aan ~/.bashrc / ~/.zshrc:"
    # shellcheck disable=SC2016  # literal-string is opzet: gebruiker copy-paste't dit
    ws_warn '    export PATH="$HOME/.npm-global/bin:$PATH"'
  fi

  if [[ -z "$only_tool" ]]; then
    install_shfmt
    install_gitleaks
    install_pre_commit
    install_jscpd
  else
    case "$only_tool" in
      shfmt) install_shfmt ;;
      gitleaks) install_gitleaks ;;
      pre-commit) install_pre_commit ;;
      jscpd) install_jscpd ;;
      *)
        ws_fail "Onbekende tool: ${only_tool}"
        exit 1
        ;;
    esac
  fi

  echo
  ws_info "Klaar. Verifieer met:"
  ws_info "  bash common/install-shell-tools.sh --check"
  ws_info ""
  ws_info "Voor per-project gates: kopieer common/templates/pre-commit-config-shell.yaml.example"
  ws_info "naar <repo>/.pre-commit-config.yaml en draai 'pre-commit install'."
}

main "$@"
