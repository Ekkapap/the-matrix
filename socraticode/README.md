# SocratiCode

ติดตั้งและกำหนดค่า [SocratiCode](https://github.com/giancarloerra/socraticode) สำหรับ Claude Code และ Codex ให้ใช้ Ollama และ Qdrant ส่วนกลางโดยอัตโนมัติ

## ⚡ Quick Installation

เลือกคำสั่งตามระบบปฏิบัติการ แล้วคัดลอกไปรันใน Terminal เพียงบรรทัดเดียว ระบบจะติดตั้ง/อัปเดต SocratiCode Plugin และกำหนดค่า Remote Ollama/Qdrant ให้โดยอัตโนมัติ

### 🪟 Windows (PowerShell)

เปิด PowerShell แล้วรัน:

```powershell
iex (iwr -useb "https://raw.githubusercontent.com/Ekkapap/the-matrix/main/socraticode/install/windows.ps1")
```

### 🍎 macOS / 🐧 Linux (Bash)

Coming soon.

```bash

```

## 🚀 Quick Start

หลังติดตั้งเสร็จ ให้ปิดและเปิด Claude Code หรือ Codex ใหม่ จากนั้นเข้าโฟลเดอร์โปรเจกต์ที่ต้องการใช้งาน SocratiCode

SocratiCode จะทำงานผ่าน MCP Server โดยใช้ configuration กลางที่ Installer กำหนดให้

## ⚙️ Central Configuration

ทุกเครื่องจะใช้ Embedding Model และ Vector Database ชุดเดียวกัน

| Setting | Value |
| --- | --- |
| Embedding Provider | `ollama` |
| Embedding Model | `bge-m3` |
| Embedding Dimensions | `1024` |
| Embedding Context Length | `8192` |
| Ollama Mode | `external` |
| Ollama URL | `https://ollama-npm.moph.go.th` |
| Qdrant Mode | `external` |
| Qdrant URL | `https://qdrant-npm.moph.go.th` |

### Network

- Ollama: `https://ollama-npm.moph.go.th`
- Qdrant: `https://qdrant-npm.moph.go.th`

Developer workstation ต้องเชื่อมต่อ Headscale VPN และ resolve hostname ทั้งสองผ่าน MagicDNS ได้

## 🧩 Supported Clients

### Claude Code

Installer จะติดตั้ง SocratiCode Plugin ใน User Scope และเพิ่ม Environment Variables ลงใน:

```text
%USERPROFILE%\.claude\settings.json
```

### Codex

Installer จะติดตั้ง SocratiCode Plugin และคง Plugin Skills ไว้ พร้อมปิด bundled MCP server ของ Plugin แล้วลงทะเบียน MCP Server ใหม่ด้วย Global Environment Configuration ใน:

```text
%USERPROFILE%\.codex\config.toml
```

## 🛠️ Installer Behavior

- ตรวจสอบ Node.js และ npx ก่อนเริ่มติดตั้ง
- หากไม่พบหรือเวอร์ชันไม่รองรับ จะถามก่อนติดตั้ง Node.js LTS ผ่าน winget
- ตรวจสอบและเพิ่ม Node.js ลง User PATH หากตัวติดตั้งยังไม่ได้ตั้งค่า PATH ให้
- ตรวจสอบ Claude Code CLI และ Codex CLI
- ติดตั้ง SocratiCode Plugin สำหรับทั้งสอง Client
- ใช้ `socraticode@latest` สำหรับ MCP Engine
- Inject ค่า Remote Ollama และ Qdrant ตาม Configuration กลาง
- สำรองไฟล์ Configuration เดิมเป็น `.bak` ก่อนแก้ไข
- ไม่เขียนทับ Configuration ส่วนอื่นที่ไม่เกี่ยวข้อง
- รองรับการรัน Installer ซ้ำ

## 📋 Requirements

- Windows 10/11 หรือ Windows Server ที่รองรับ PowerShell
- PowerShell
- Node.js 18.17 หรือใหม่กว่า พร้อม npm/npx
- Claude Code CLI และ/หรือ Codex CLI
- winget เฉพาะกรณีที่ต้องติดตั้ง Node.js อัตโนมัติ
- เชื่อมต่อ Headscale VPN เพื่อเข้าถึง Ollama และ Qdrant

## 🔄 Reinstall / Update

เรียก Quick Installation command ซ้ำได้ Installer จะตรวจและปรับ Configuration ให้ตรงกับค่ากลางอีกครั้ง โดยสำรองไฟล์ต้นฉบับไว้เมื่อยังไม่มีไฟล์สำรอง

## 📁 Project Structure

```text
socraticode/
├── README.md
└── install/
    └── windows.ps1
```

## 🔗 References

- [SocratiCode](https://github.com/giancarloerra/socraticode)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Codex](https://developers.openai.com/codex)
