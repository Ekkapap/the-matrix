#!/usr/bin/env bash
set -Eeuo pipefail

readonly MARKETPLACE_REPO="giancarloerra/socraticode"
readonly NODE_MIN_MAJOR=18
readonly NODE_MIN_MINOR=17
readonly NVM_INSTALLER_VERSION="v0.40.3"

readonly EMBEDDING_PROVIDER="ollama"
readonly EMBEDDING_CONTEXT_LENGTH="8192"
readonly EMBEDDING_DIMENSIONS="1024"
readonly EMBEDDING_DOCUMENT_PREFIX=""
readonly EMBEDDING_MODEL="bge-m3"
readonly EMBEDDING_QUERY_PREFIX=""
readonly OLLAMA_MODE="external"
readonly OLLAMA_URL="https://ollama-npm.moph.go.th"
readonly QDRANT_MODE="external"
readonly QDRANT_URL="https://qdrant-npm.moph.go.th"

log() {
    printf '\n\033[1;36m==> %s\033[0m\n' "$1"
}

success() {
    printf '\033[1;32m[+] %s\033[0m\n' "$1"
}

warn() {
    printf '\033[1;33m[!] %s\033[0m\n' "$1"
}

fail() {
    printf '\033[1;31m[ERROR] %s\033[0m\n' "$1" >&2
    exit 1
}

confirm() {
    local answer
    printf '%s ' "$1"
    read -r answer
    [[ "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "ไม่พบคำสั่ง $1"
}

backup_once() {
    local file="$1"
    if [[ -f "$file" && ! -f "${file}.bak" ]]; then
        cp -p "$file" "${file}.bak"
        success "สำรองไฟล์: ${file}.bak"
    fi
}

check_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin)
            case "$arch" in
                arm64|x86_64) ;;
                *) fail "ไม่รองรับ macOS architecture: $arch" ;;
            esac
            success "รองรับ macOS ($arch)"
            ;;
        Linux)
            case "$arch" in
                x86_64|aarch64|arm64) ;;
                *) fail "ไม่รองรับ Linux architecture: $arch" ;;
            esac
            success "รองรับ Linux ($arch)"
            ;;
        *)
            fail "รองรับเฉพาะ macOS และ Linux"
            ;;
    esac
}

load_nvm() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        source "$NVM_DIR/nvm.sh"
    fi
}

node_version_supported() {
    local version major minor
    command -v node >/dev/null 2>&1 || return 1
    version="$(node -p 'process.versions.node' 2>/dev/null)" || return 1
    major="${version%%.*}"
    minor="${version#*.}"
    minor="${minor%%.*}"

    if (( major > NODE_MIN_MAJOR )); then
        return 0
    fi
    if (( major == NODE_MIN_MAJOR && minor >= NODE_MIN_MINOR )); then
        return 0
    fi
    return 1
}

install_node_lts() {
    require_command curl

    if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
        log "ติดตั้ง NVM สำหรับจัดการ Node.js แบบ User-level"
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_INSTALLER_VERSION}/install.sh" | bash
    fi

    load_nvm
    command -v nvm >/dev/null 2>&1 || fail "ติดตั้ง NVM ไม่สำเร็จ หรือยังโหลด nvm.sh ไม่ได้"

    log "ติดตั้ง Node.js LTS"
    nvm install --lts
    nvm use --lts
    nvm alias default 'lts/*'
    load_nvm
}

check_node() {
    log "ตรวจสอบ Node.js และ npx"
    load_nvm

    if ! node_version_supported || ! command -v npx >/dev/null 2>&1; then
        warn "ต้องใช้ Node.js ${NODE_MIN_MAJOR}.${NODE_MIN_MINOR} หรือใหม่กว่า พร้อม npx"

        if ! confirm "ต้องการติดตั้ง Node.js LTS ผ่าน NVM หรือไม่? (y/n)"; then
            fail "ยกเลิก เนื่องจาก Node.js/npx ยังไม่พร้อมใช้งาน"
        fi

        install_node_lts
    fi

    node_version_supported || fail "Node.js ต้องเป็นเวอร์ชัน ${NODE_MIN_MAJOR}.${NODE_MIN_MINOR} หรือใหม่กว่า"
    command -v npx >/dev/null 2>&1 || fail "ไม่พบ npx หลังติดตั้ง Node.js"

    success "Node.js $(node --version)"
    success "npm $(npm --version)"
    success "npx $(npx --version)"
}

install_claude_plugin() {
    log "ตรวจสอบ Claude Code"
    if ! command -v claude >/dev/null 2>&1; then
        warn "ไม่พบ Claude Code CLI ข้ามการติดตั้ง Claude Code Plugin"
        return 0
    fi

    local marketplaces
    marketplaces="$(claude plugin marketplace list 2>&1 || true)"

    if ! grep -qi 'socraticode' <<< "$marketplaces"; then
        log "เพิ่ม SocratiCode Marketplace ใน Claude Code"
        claude plugin marketplace add "$MARKETPLACE_REPO"
    fi

    log "ติดตั้ง Claude Code Plugin"
    claude plugin install --scope user socraticode@socraticode
    success "ติดตั้ง SocratiCode สำหรับ Claude Code แล้ว"
}

install_codex_plugin() {
    log "ตรวจสอบ Codex CLI"
    if ! command -v codex >/dev/null 2>&1; then
        warn "ไม่พบ Codex CLI ข้ามการติดตั้ง Codex Plugin"
        return 0
    fi

    local marketplaces
    marketplaces="$(codex plugin marketplace list 2>&1 || true)"

    if ! grep -qi 'socraticode' <<< "$marketplaces"; then
        log "เพิ่ม SocratiCode Marketplace ใน Codex"
        codex plugin marketplace add "$MARKETPLACE_REPO" --ref main
    fi

    log "ติดตั้ง Codex Plugin"
    codex plugin add socraticode@socraticode
    success "ติดตั้ง SocratiCode สำหรับ Codex แล้ว"
}

configure_claude() {
    local config_dir config_file
    config_dir="$HOME/.claude"
    config_file="$config_dir/settings.json"

    mkdir -p "$config_dir"

    log "กำหนดค่า Claude Code"
    if [[ ! -f "$config_file" ]]; then
        printf '{}\n' > "$config_file"
    fi

    node - "$config_file" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
const config = JSON.parse(fs.readFileSync(path, "utf8"));
if (!config.env || typeof config.env !== "object" || Array.isArray(config.env)) {
  config.env = {};
}
Object.assign(config.env, {
  EMBEDDING_PROVIDER: "ollama",
  EMBEDDING_CONTEXT_LENGTH: "8192",
  EMBEDDING_DIMENSIONS: "1024",
  EMBEDDING_DOCUMENT_PREFIX: "",
  EMBEDDING_MODEL: "bge-m3",
  EMBEDDING_QUERY_PREFIX: "",
  OLLAMA_MODE: "external",
  OLLAMA_URL: "https://ollama-npm.moph.go.th",
  QDRANT_MODE: "external",
  QDRANT_URL: "https://qdrant-npm.moph.go.th"
});
fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
NODE

    success "อัปเดต $config_file"
}

configure_codex() {
    local config_dir config_file
    config_dir="$HOME/.codex"
    config_file="$config_dir/config.toml"

    mkdir -p "$config_dir"
    touch "$config_file"

    log "กำหนดค่า Codex"

    node - "$config_file" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
let lines = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n").split("\n");

function setTomlValue(section, key, value) {
  const header = `[${section}]`;
  let start = lines.findIndex(line => line.trim() === header);

  if (start === -1) {
    while (lines.length && lines[lines.length - 1].trim() === "") lines.pop();
    if (lines.length) lines.push("");
    lines.push(header, `${key} = ${value}`);
    return;
  }

  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^\s*\[/.test(lines[i])) {
      end = i;
      break;
    }
  }

  const keyPattern = new RegExp(`^\\s*${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*=`);
  for (let i = start + 1; i < end; i++) {
    if (keyPattern.test(lines[i])) {
      lines[i] = `${key} = ${value}`;
      return;
    }
  }

  lines.splice(end, 0, `${key} = ${value}`);
}

setTomlValue('plugins."socraticode@socraticode".mcp_servers.socraticode', "enabled", "false");
setTomlValue("mcp_servers.socraticode", "command", '"npx"');
setTomlValue("mcp_servers.socraticode", "args", '["-y", "--prefer-online", "socraticode@latest"]');

const env = {
  EMBEDDING_PROVIDER: '"ollama"',
  EMBEDDING_CONTEXT_LENGTH: '"8192"',
  EMBEDDING_DIMENSIONS: '"1024"',
  EMBEDDING_DOCUMENT_PREFIX: '""',
  EMBEDDING_MODEL: '"bge-m3"',
  EMBEDDING_QUERY_PREFIX: '""',
  OLLAMA_MODE: '"external"',
  OLLAMA_URL: '"https://ollama-npm.moph.go.th"',
  QDRANT_MODE: '"external"',
  QDRANT_URL: '"https://qdrant-npm.moph.go.th"'
};

for (const [key, value] of Object.entries(env)) {
  setTomlValue("mcp_servers.socraticode.env", key, value);
}

fs.writeFileSync(path, `${lines.join("\n").replace(/\n+$/, "")}\n`, { mode: 0o600 });
NODE

    success "อัปเดต $config_file"
}

main() {
    printf '\n\033[1;36m--- SocratiCode Installer ---\033[0m\n'
    check_platform
    check_node

    local installed=0
    if command -v claude >/dev/null 2>&1; then
        install_claude_plugin
        backup_once "$HOME/.claude/settings.json"
        configure_claude
        installed=1
    else
        warn "Claude Code CLI ไม่ได้ติดตั้ง"
    fi

    if command -v codex >/dev/null 2>&1; then
        install_codex_plugin
        backup_once "$HOME/.codex/config.toml"
        configure_codex
        installed=1
    else
        warn "Codex CLI ไม่ได้ติดตั้ง"
    fi

    (( installed == 1 )) || fail "ไม่พบ Claude Code CLI หรือ Codex CLI อย่างน้อยหนึ่งรายการ"

    log "ติดตั้งเสร็จ"
    printf 'Ollama: %s\n' "$OLLAMA_URL"
    printf 'Qdrant: %s\n' "$QDRANT_URL"
    printf 'Embedding: %s / %s dimensions\n' "$EMBEDDING_MODEL" "$EMBEDDING_DIMENSIONS"
    printf '\nปิดและเปิด Claude Code / Codex ใหม่เพื่อโหลด Plugin และ MCP Configuration\n'
}

main "$@"
