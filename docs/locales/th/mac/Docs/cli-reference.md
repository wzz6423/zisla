# คู่มืออ้างอิงการเชื่อม `zislactl`

[English](../../../../../mac/Docs/cli-reference.md) | [简体中文](../../../../../mac/Docs/cli-reference.zh-CN.md) | **ไทย** | [ภาษาอื่น](../../../README.md)

`zislactl` เป็นโปรโตคอลสถานะในเครื่องร่วมกันสำหรับเครื่องมือ AI สคริปต์ และงาน CI ที่เชื่อมกับ zisla เขียนสถานะงาน การใช้ และแจ้งเตือนเป็นข้อมูลมีโครงสร้าง ใช้ธุรกรรม SQLite ป้องกันข้อมูลเขียนไม่ครบ เอกสารกำหนดผู้ให้บริการ คำสั่ง และข้อจำกัดฟิลด์ที่คงที่

## หลักการ

- เขียนในเครื่อง ไม่อัปโหลดพรอมป์ต์ คำตอบ หรือข้อมูลเข้าบัญชี
- อัปเดต ID เดียวซ้ำได้ผลเดิม ผู้อ่านเห็นฐานที่ยืนยันครบแล้ว
- รับชื่อผู้ให้บริการแบบเก่าแต่เก็บชื่อมาตรฐาน

## การเก็บในเครื่องและขอบเขต JSON

งาน การใช้ และแจ้งเตือนอยู่ `~/Library/Application Support/zisla/ai-state.sqlite` เขียนด้วยธุรกรรม SQLite ไม่เขียน `ai-state.json` ในโปรโตคอลปัจจุบัน ล้างงานยังเก็บประวัติการใช้

`zislactl` รับตัวเลือกบรรทัดคำสั่งที่ระบุ `list` แสดงข้อความรายบรรทัด การเชื่อมและตั้งค่ายังใช้ JSON มีโครงสร้าง รวมอินพุต session JSON/JSONL ภายนอกและเข้ารหัส/ถอดตั้งค่าตามกฎของตน CLI ใช้อาร์กิวเมนต์ ข้อความออก และ SQLite

## ผู้ให้บริการ

| ค่า | ชื่อเรียกอื่น |
| --- | --- |
| `claude` | `claude-code`, `claude-cli`, `claude-desktop` |
| `codex` | `openai-codex`, `codex-cli`, `codex-desktop` |
| `gemini` | `google-gemini`, `gemini-cli`, `gemini-code-assist` |
| `grok` | `grok-cli`, `xai` |
| `gpt` | `openai`, `chatgpt`, `openai-gpt` |
| `copilot` | `github-copilot`, `copilot-cli`, `copilot-chat` |
| `kimi` | `kimi-code`, `kimi-code-cli`, `kimi-vscode` |
| `qwen` | `tongyi`, `qwen-code`, `qwen-code-cli`, `qwen-vscode` |
| `coder` | `qoder`, `qoder-cli`, `qoderwork`, `qoderwork-cn`, `qoderwake`, `qwen-coder` |
| `zcode` | `z-code`, `zcode-cli`, `zcode-desktop`, `glm`, `glm-coding`, `z-ai`, `z.ai` |
| `trae` | `trae-work`, `traework`, `trae-solo`, `trae-cn` |
| `opencode` | `open-code`, `open_code` |
| `pi` | `pi-coding`, `pi-coding-agent`, `pi-cli`, `pi-agent` |
| `harness` | `harnext`, `harnext-cli`, `harness-cli` |
| `doubao` | `豆包` |
| `delta` | `delta-app`, `delta-desktop`, `zed-delta` |
| `orca` | `orca-desktop`, `orca-ide` |
| `workbuddy` | `workbuddy-desktop` |
| `workbuddy-ai` | `workbuddyai`, `workbuddy ai` |

WorkBuddy และ WorkBuddy AI เป็นผลิตภัณฑ์คนละตัวสำหรับในประเทศ/ต่างประเทศ ไม่ใช่รุ่นเก่าใหม่ ต้องแยก provider ฐานข้อมูล ไอคอน และลิงก์ลึก ประวัติ WorkBuddy ที่ใช้ `harness` ยังอ่านได้ ไม่เปลี่ยนชื่อ/ย้าย provider ทั้งระบบ ID แจ้งแยก provider/task ชัด (`ai-active-workbuddy:<id>` หรือ `ai-active-workbuddy-ai:<id>`) งาน manual ที่ ID ขึ้น `ai-` จึงไม่สับสนกับ WorkBuddy AI

### ตรวจ Delta, Orca, WorkBuddy และ WorkBuddy AI อัตโนมัติ

- Delta: อ่านเมทาดาทาเธรดสตรีมที่ทำดัชนีใน `Library/Application Support/Delta/user_*/data.sqlite` และฐานรากเดิม ตัดเก็บถาวร ว่าง และเก่า ตัวเลขจาก `app_model_usage_daily` รวมแคชอ่าน/เขียน รุ่นไม่มีบัญชีนี้ไม่รายงานการใช้ ไม่เดาจากบทสนทนา
- Orca: อ่าน `agent-hooks/last-status.json` และเทิร์นแชตมีโครงสร้างใน `agent-session-journal.db` รวมโฟลเดอร์โปรไฟล์และ v1/v2/v3 ยึด revision สูงสุดและลำดับเดิม ตัดเสร็จ หมดอายุ ระยะไกล และมีแต่ identity เส้นทางข้อความอ้างอิงจริงและบ้านบัญชี Claude/Codex ที่ปักยังให้โทเคน ตัวอย่างรักษา CLI provider และ event ID ไม่ให้ตรวจ CLI นับซ้ำ ไม่เพิ่มแคชการใช้ทั้งเครื่องของ Orca
- WorkBuddy: อ่าน `~/.workbuddy/workbuddy.db` ของตนด้วย `workbuddy` ไอคอน WorkBuddy และ `workbuddy://chat/<id>` ไม่อ่านฐาน WorkBuddy AI
- WorkBuddy AI: อ่านสถานะ ชื่อ โมเดล เวลา `~/.workbuddy-ai/workbuddy.db` แยกจาก `~/.workbuddy/workbuddy.db` ตัดเสร็จ ลบ เก่า ใช้เวลาสดกว่า `updated_at`/`last_activity_at` รักษางานนาน ใช้ `workbuddy-ai` ไอคอนและ `workbuddy-ai://chat/<id>` ตรวจ session เท่านั้น `session_usage.used` คือบริบทที่เต็ม เครดิตไม่ใช่ USD/โทเคน จึงไม่ลงโทเคนคิดเงิน รายงานตัวเลขเองผ่าน `zislactl usage`
- ทุกการเชื่อมอ่านอย่างเดียวเท่าที่ทำได้ ฐานไม่มี/ไม่เข้ากันคืนไม่มีข้อมูล ไม่อ่านเนื้อหาเธรด Delta ที่ทำสำเนาหรือข้อความ journal Orca ใช้ `zislactl usage` หากไม่มีตัวเลขบันทึก

## รูปแบบตัวเลือก

- `--key value` หรือ `--key=value` ตัวเลือกเกิดครั้งเดียวต่อคำสั่ง ซ้ำคือผิดใช้ รหัส 64
- ค่าเริ่ม `--` ได้ เช่น `--detail --verbose` ยกเว้น flag คำสั่งเดียว `--failed` ของ `finish` และ `--queued` ของ `update` ไม่ถือเป็นค่า ตัวแปรว่างไม่ใส่ quote ใน `--detail $DETAIL --failed` จึงยังทำเครื่องหมายล้มเหลว ค่า literal ใช้ `--detail=--failed`
- `--failed`/`--queued` เป็น flag เดี่ยว true รูป `--failed=false` หรือ `--failed false` และ queued แบบเดียวปิด ค่าอื่นผิดใช้

## `update`

สร้างหรือแทนงาน `id` เดียวกัน

```text
zislactl update --id <id> --provider <provider> --title <title>
  [--progress <0-100>] [--detail <text>] [--pid <process PID>]
  [--status <running|queued|blocked|error>] [--queued]
```

- ไม่ `--progress` แสดงความคืบหน้าไม่กำหนด
- `--pid` เลือกใช้เฉพาะระบุ process งานได้
- `--status` แจ้งกำลังทำ เข้าคิว รอผู้ใช้ หรือผิดขณะทำชัด
- `--queued` ชื่อแทน `--status queued` ไม่มีสถานะชัดถือกำลังทำ `--status` สำคัญกว่า `--queued`

## `finish`

```text
zislactl finish --id <id> [--failed] [--detail <text>]
```

สำเร็จเป็น 100% ล้มเหลวคง progress ล่าสุด

## `remove`

```text
zislactl remove --id <id>
```

ไม่มีงานออก 65

## `clear`

```text
zislactl clear
```

ล้างงาน รักษาประวัติและแจ้งเตือน

## `list`

```text
zislactl list
```

พิมพ์สถานะ provider ชื่อ เปอร์เซ็นต์ทีละบรรทัด

## `usage`

```text
zislactl usage --provider <provider>
  --input-tokens <n> --output-tokens <n>
  [--cost <USD>] [--model <model>] [--timestamp <Unix seconds>]
```

เติมกราฟ 12 ชั่วโมงและฮีตแมป 7x24

## `notify`

```text
zislactl notify --title <title>
  [--detail <text>]
  [--kind <info|success|warning|error>]
  [--side <left|right>]
```

แจ้งจากด้านเลือก พักปิดอัตโนมัติเมื่อตัวชี้ทับ

## `message`

แจ้งข้อความสองด้าน ซ้าย logo/ผู้ส่ง ขวาเลื่อนเนื้อหา

```text
zislactl message --app <app> --sender <sender> --content <content>
  [--app-bundle-id <bundle id>]
```

ตัวอย่าง:

```bash
zislactl message \
  --app "Messages" \
  --sender "Alice" \
  --content "Meet in the conference room at 7 PM" \
  --app-bundle-id com.apple.MobileSMS
```

- `--app` `--sender` `--content` ต้องมี `--app-bundle-id` เลือกเพื่อหาไอคอนติดตั้ง
- รวมบรรทัด/ช่องว่างเกิน ตัดราว 48 ตัวอักษรและจุดไข่ปลา
- ธุรกรรม SQLite เดียวเก็บ `IslandNotice` ทั้งคู่ไม่เปลี่ยน `notify`

## รหัสออก

| รหัส | ความหมาย |
| --- | --- |
| `0` | สำเร็จ |
| `64` | อาร์กิวเมนต์/คำสั่งย่อยผิด |
| `65` | ข้อมูลผิด งานไม่มี หรือฐานเสีย |
| `70` | ระบบไฟล์หรือการรันผิด |
