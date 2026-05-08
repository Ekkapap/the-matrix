## ⚡ Quick Installation

เลือกคำสั่งตามระบบปฏิบัติการของคุณ แล้วคัดลอกไปรันใน Terminal เพียงบรรทัดเดียว ระบบจะทำการติดตั้ง/อัปเดต และตั้งค่า PATH ให้โดยอัตโนมัติ

### 🪟 Windows (PowerShell)

เปิด PowerShell แล้วรันคำสั่งนี้:

```powershell
iex (iwr -useb "https://raw.githubusercontent.com/Ekkapap/the-matrix/refs/heads/main/rtk-ai/install/windows.ps1")

```

*(ติดตั้งไปยัง `%USERPROFILE%\.local\bin` และเปิดเบราว์เซอร์ไปยัง GitHub เมื่อเสร็จสิ้น)*

### 🍎 macOS / 🐧 Linux (Bash)

เปิด Terminal แล้วรันคำสั่งนี้:

```bash
curl -fsSL https://raw.githubusercontent.com/Ekkapap/the-matrix/refs/heads/main/rtk-ai/install/unix.sh | bash

```

*(รองรับทั้ง Homebrew และการติดตั้งแบบ Standalone พร้อมเปิดเบราว์เซอร์เมื่อเสร็จสิ้นบน macOS)*

---

## 🚀 Quick Start

หลังจากติดตั้งเสร็จสิ้น ให้เปิด Terminal แล้วเข้าไปที่โฟลเดอร์โปรเจ็คของคุณ จากนั้นเลือกคำสั่ง Initialize ให้ตรงกับ AI ที่คุณใช้:

```bash
rtk init -g                  # Claude Code / Copilot (default)
rtk init -g --gemini         # Gemini CLI
rtk init --agent cursor      # Cursor
rtk init --agent windsurf    # Windsurf
rtk init --agent antigravity # Google Antigravity

rtk --version # ตรวจสอบเวอร์ชั่น
rtk gain    # ตรวจสอบสถิติการประหยัด Token

```

---

## 📊 Token Savings

| Operation | Standard | rtk | Savings |
| --- | --- | --- | --- |
| `git status` | 3,000 | 600 | **-80%** |
| `ls` / `tree` | 2,000 | 400 | **-80%** |
| `npm test` | 25,000 | 2,500 | **-90%** |
| **Total Session** | **~118,000** | **~23,900** | **-80%** |

## 🛠️ How It Works

RTK ทำหน้าที่เป็น Proxy ขั้นกลางระหว่าง AI และ Shell ของคุณ โดยใช้กลยุทธ์:

1. **Smart Filtering**: ตัด Noise และช่องว่างที่ไม่จำเป็น
2. **Grouping**: ยุบรวมไฟล์หรือ Error ประเภทเดียวกัน
3. **Truncation**: เก็บเฉพาะ Context ที่สำคัญ
4. **Deduplication**: ลดการซ้ำซ้อนของ Log

---
