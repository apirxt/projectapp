## Admin Web (จัดการสิทธิ์ผู้ใช้)

มีหน้าเว็บสำหรับผู้ดูแลระบบอยู่ที่ `web_admin/` ใช้ควบคุมสิทธิ์ (ตั้ง/ถอนแอดมิน) และปิด/เปิดการใช้งานบัญชี ผ่าน Cloud Functions แบบ callable

ฟีเจอร์
- เข้าสู่ระบบด้วยอีเมล/รหัสผ่าน
- Bootstrap ผู้ดูแลคนแรก (เฉพาะกรณียังไม่มีแอดมินในระบบ)
- แสดงรายชื่อผู้ใช้แบบแบ่งหน้า พร้อมสถานะแอดมินและ disabled
- สั่งตั้ง/ถอนแอดมิน และปิด/เปิดบัญชีได้ทันที

ความต้องการ
- Firebase project พร้อม Authentication
- Cloud Functions (Gen1, Node 16) – ตั้งค่าไว้ใน `firebase.json`

ติดตั้งและดีพลอยฟังก์ชัน (อุปกรณ์นักพัฒนา)
1) ตรวจสอบ/ติดตั้ง Firebase CLI แล้วล็อกอิน
```
firebase login
```
2) เลือกโปรเจกต์ และดีพลอยเฉพาะฟังก์ชัน
```
firebase use <projectId>
firebase deploy --only functions
```

หมายเหตุ Windows: ขั้นตอนดีพลอยถูกตั้งค่าให้ไม่รัน `npm install` ใน predeploy แล้ว (เพื่อเลี่ยงปัญหา ENOENT บนบางเครื่องที่ `npm` ไม่อยู่ใน PATH ระหว่างสั่งจาก CLI)
- ฝั่งเซิร์ฟเวอร์ของ Cloud Functions (Gen1) จะติดตั้ง dependencies ให้อัตโนมัติระหว่าง build อยู่แล้ว
- ถ้าต้องการรัน ESLint ในเครื่อง ให้ติดตั้ง dependencies เองครั้งแรก: `npm --prefix functions install` แล้วสั่ง `npm --prefix functions run lint`

การใช้งานหน้าเว็บแอดมิน
1) เปิดไฟล์ `web_admin/app.js` แล้วกรอกค่า `firebaseConfig` จาก Firebase Console (Project settings > General > Your apps)
2) เปิดไฟล์ `web_admin/index.html` ด้วย Web Server (เช่น VS Code Live Server) หรืออัปโหลดขึ้น Firebase Hosting
3) เข้าสู่ระบบด้วยบัญชีผู้ดูแล (หรือใช้ปุ่ม "ฉันคือผู้ดูแลคนแรก" เพื่อ bootstrap เฉพาะครั้งแรกของโปรเจกต์ หากยังไม่มีแอดมิน)

หมายเหตุด้านความปลอดภัย
- ฟังก์ชันทุกตัวจะตรวจสอบ custom claim `isAdmin` ของผู้เรียกใช้งาน
- ฟังก์ชัน `grantSelfAdminIfNone` จะอนุญาตตั้งแอดมินให้ตัวเองได้เฉพาะกรณีที่ยังไม่มีผู้ใช้คนใดในระบบมีสิทธิ์แอดมินอยู่แล้วเท่านั้น
- แนะนำให้สร้างบัญชีผู้ดูแลและเก็บรักษาอย่างปลอดภัย

## Hosting (ทางเลือก)
- ถ้าต้องการเปิดใช้ Firebase Hosting สำหรับ `web_admin/` ให้รัน `firebase init hosting` แล้วเลือกโฟลเดอร์เป็น `web_admin`
- จากนั้นดีพลอยด้วย `firebase deploy --only hosting`
- บน Spark Plan ใช้ได้ตามปกติ เพราะหน้าแอดมินเรียกใช้เฉพาะ Authentication และ Callable Functions ซึ่งไม่คิดบิลเพิ่ม

# projectapp

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
