# สถาปัตยกรรมและการออกแบบประสิทธิภาพ

[English](../../../../../mac/Docs/architecture.md) | [简体中文](../../../../../mac/Docs/architecture.zh-CN.md) | **ไทย** | [ภาษาอื่น](../../../README.md)

## กระตุ้นจากขอบบน

สถานะซ่อนไม่มีหน้าต่างโปร่งใส `PointerEdgeMonitor` ติดตัวตรวจ `NSEvent` ทั่วระบบและในแอปสำหรับเคลื่อนเมาส์/ลาก `ScreenLayoutEngine` ใช้รูปทรงล้วนตรวจเข้าพื้นที่ 6 px ตรงกลางบนแต่ละจอ

แต่ละจอมี ID คงที่จาก `NSScreenNumber` กับ `CGDirectDisplayID` ผูก layout กับ `screen.frame.maxY` จึงรองรับพิกัดลบ จอซ้อนแนวตั้ง และจอนอกรอยบาก

เมื่อเชื่อมต่อหลายจอ การตั้งค่า → ทั่วไป → โหมดจอภาพ ให้เลือกโหมด Dynamic Island (ตำแหน่งกล้องหรือกำหนดเอง) โหมดรอยบาก หรือซ่อนแยกแต่ละจอได้ เมื่อมีจอเดียวจะซ่อนการตั้งค่านี้และใช้รูปแบบส่วนกลาง เมื่อเชื่อมต่ออีกครั้งจะคืนค่าการตั้งค่าที่บันทึกไว้ของแต่ละจอ ทุกจอที่เปิดให้แสดงเกาะจะแสดงเกาะแบบย่อพร้อมกัน การขยายเกาะ การดำเนินการด่วน การบันทึก และข้อความชั่วคราวจะแทนที่เกาะเฉพาะบนจอนั้น การเลือกจอสำหรับการแจ้งเตือนจะกรองเฉพาะเนื้อหา โดยไม่ซ่อนเกาะที่ไม่มีงานทำ

## หน้าต่าง

เกาะหลักมี `.borderless + .nonactivatingPanel` เดียว:

- ระดับ `.statusBar` ไม่ทับหน้าล็อก/เมนูระบบ
- `.canJoinAllSpaces + .fullScreenAuxiliary` รองรับ Spaces และแอปเต็มจอทั่วไป
- hover ไม่เรียก `NSApp.activate` ไม่แย่งโฟกัส
- ซ่อนใช้ `orderOut` ไม่ยึดพื้นที่เมนูด้วยหน้าต่างโปร่งใส

แผงแจ้งซ้ายขวาสร้างตามต้องการและซ่อนทันทีเมื่อคิวว่าง

## สถานะและงานพร้อมกัน

- AppKit, SwiftUI state และหน้าต่างอยู่ `MainActor`
- เมื่อเปิดใช้การจัดการแถบเมนู zisla จะสร้างตัวควบคุม `NSStatusItem` สองตัว ขณะที่รายการไอคอนเปิดอยู่ zisla จะอ่าน `AXExtrasMenuBar` และตรวจสอบตำแหน่งของไอคอนที่เลือกหลังจากย้าย
- ดาวน์โหลด อากาศ และ GitHub ใช้ actor
- AI hook ตรวจด้วย event ระบบไฟล์ directory แต่ละแหล่งเทียบไฟล์ session/activity ล่าสุดด้วย mtime/ขนาด ใช้ parse cache เดิมถ้าไม่เปลี่ยน
- auto อ่านเหตุการณ์มีโครงสร้าง marker คงที่และ metadata จำเป็น ไม่อ่านพรอมป์ต์/คำตอบ parser provider ผิดไม่ขวางอื่น
- โควตาบัญชี AI มาจากการตรวจของผู้ให้บริการแต่ละราย โควตา Gemini และ Claude/GPT ของ Antigravity มีช่วงรีเซ็ตและการแจ้งเตือนแยกกัน โควตาแชตปกติของ Gemini App ใช้ Cookie เว็บที่บันทึกไว้ของบัญชี Google เดียวกัน ส่วน Gemini CLI ใช้ OAuth ในเครื่อง ไม่ประมาณค่าโควตาที่ไม่มีข้อมูล
- หน่วงยุบใช้ `Task` ยกเลิกได้และ generation token งานเก่าจึงซ่อนเกาะเปิดใหม่ไม่ได้
- ซ่อนไม่มี `TimelineView` timer 60 Hz หรือส่ง animation ต่อเนื่อง

## ตรวจสื่อ

MediaRemote ให้ชื่อ ปก progress และ controls Core Audio 14.4+ process properties ยืนยัน output active และแอปสำรองเมื่อไม่มี metadata รายการ/สถานะใช้ property listeners พร้อมตรวจยืนยันเป็นช่วงจำกัด ไม่เก็บเนื้อหาเสียง ไม่ขอ Screen Recording/Accessibility แหล่งพัก/หยุด/เงียบไม่คงพื้นที่สื่อ

## บันทึกและมิกซ์แอป

แยกจาก metadata บันทึกขอ Screen Recording กับไมค์/กล้องที่เปิด เก็บสื่อในเครื่องและโปรเจกต์ในโฟลเดอร์เลือก มิกซ์ใช้ Core Audio taps macOS 14.4+ ต้อง System Audio Recording

## วัสดุ

macOS 26 SwiftUI `glassEffect` ชั้นเดียว; 14/15 `NSVisualEffectView` ชั้นเดียว Reduce Transparency เปลี่ยนทึบ ไม่ซ้อน blur/material หลายชั้น

## ขอบเขตความปลอดภัยดาวน์โหลด

Swift เริ่ม `yt-dlp` ด้วย `Process.executableURL` กับ array URL argv แยกหลัง `--` เสมอ ปิด config/plugin/exec ระบาย output พร้อมกัน progress ใช้ JSON sentinel

สำเร็จเมื่อ exit 0 path มีและ resolved อยู่โฟลเดอร์อนุญาต แต่ละงานล้างเฉพาะ temp UUID ของตน

## ตรวจและดาวน์โหลดอัปเดต

ช่องเลือกตรวจประเทศออก public ครั้งเดียว แล้ว Sparkle รับ signed appcast ตรง build ดึง ZIP HTTPS ตรวจ EdDSA archive/feed ก่อนแตก แทนแอปและเปิดใหม่ `CN` เริ่ม Gitee (`update-release` Release, `preview` Preview) ย้อน GitHub matching ครั้งเดียว อื่น GitHub ก่อน Gitee ครั้งเดียว ไม่รู้คง Gitee แต่ละ feed ชี้ ZIP signed host ตน ปล่อย appcast ต่อ architecture ข้าง `appcast.xml` single ขอ slice ตน (x86_64 แปลขอ `arm64`) ไม่แทนด้วย universal universal นับ slice executable และคง `appcast.xml` ที่รับรุ่นก่อนแยก architecture เปลี่ยนค่ามีผล auto/manual และ reset Sparkle รอบหน้า public key ไม่มีบัญชี private key อยู่ macOS Keychain ผู้ดูแลหรือไฟล์ส่วนตัวป้องกันแยก
