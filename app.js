//ส่วนนำเข้า SDK ของ Firebase
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import { getAuth, signInWithEmailAndPassword, signOut, onAuthStateChanged, getIdTokenResult, sendPasswordResetEmail } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import { getFunctions, httpsCallable, connectFunctionsEmulator } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-functions.js";

// ส่วนตั้งค่า Firebase config ของโปรเจคจาก Firebase Console (Project settings > General > Your apps > Web app)
const firebaseConfig = {
  apiKey: "AIzaSyDfF2QMYEe_G34w8l_yJSIJdUqaNNusy_w",
    authDomain: "myloginapp-fbed0.firebaseapp.com",
    projectId: "myloginapp-fbed0",
    storageBucket: "myloginapp-fbed0.firebasestorage.app",
    messagingSenderId: "587348245983",
    appId: "1:587348245983:web:23c56c9eb0a2421658986a",
    measurementId: "G-0R1L1H42H4"
};

// ส่วนตรวจสอบค่า config เบื้องต้น แจ้งเตือนถ้ายังไม่ได้กรอกค่า config จริง
(() => {
  const v = firebaseConfig;
  const looksPlaceholder = !v.apiKey || v.apiKey.includes("YOUR_") || !v.projectId || String(v.projectId).includes("YOUR_");
  if (looksPlaceholder) {
    alert("ยังไม่ตั้งค่า Firebase config ใน web_admin/app.js กรุณาคัดลอกโค้ด config ของ Web App จาก Firebase Console แล้ววางแทนค่า YOUR_*");
    throw new Error("Missing Firebase config");
  }
})();

//ส่วนเริ่มต้นแอป Firebase และบริการหลัก
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const functions = getFunctions(app, "us-central1");

// หากต้องการทดสอบกับ emulator ให้ลบบรรทัดด้านล่าง
// connectFunctionsEmulator(functions, "localhost", 5001);

//ส่วนอ้างอิง element ใน DOM ที่ใช้บ่อย
const $ = (id) => document.getElementById(id);
const usersTbody = $("users");
const requestsTbody = $("requests");
const adminOnly = $("adminOnly");
const notAdmin = $("notAdmin");
const me = $("me");
const hostRequestsCard = $("hostRequests");

//ส่วนสถานะการแบ่งหน้า
let pageTokens = [null];
let currentPage = 0;

//ส่วนแสดงรายการผู้ใช้ในตาราง
function renderUsers(items) {
  usersTbody.innerHTML = "";
  for (const u of items) {
    const tr = document.createElement("tr");
    const isAdmin = Boolean(u.customClaims?.isAdmin);
    const canHost = Boolean(u.customClaims?.canHostParking);
    const hostStatus = u.hostStatus || "-";
    const expStr = u.hostActiveUntil ? new Date(u.hostActiveUntil).toLocaleString() : "-";
    const roleBadge = isAdmin ? `<span class="badge badge-admin">Admin</span>` : `<span class="badge badge-user">User</span>`;
    const hostBadge = canHost ? `<span class="badge badge-host">ปล่อยเช่าได้</span>` : `<span class="badge badge-nohost">หาเช่าอย่างเดียว</span>`;
    const activeBadge = u.disabled ? `<span class="badge badge-disabled">ปิดการใช้งาน</span>` : `<span class="badge badge-host">ใช้งานได้</span>`;
    tr.innerHTML = `
      <td>${u.email ?? "-"}</td>
      <td>${u.displayName ?? "-"}</td>
      <td style="font-family:monospace">${u.uid}</td>
      <td>${roleBadge}</td>
      <td>${hostBadge}</td>
      <td>${hostStatus}</td>
      <td>${expStr}</td>
      <td>${activeBadge}</td>
      <td>
        <div class="row">
          <button class="btn btn-outline btn-small" data-act="admin" data-uid="${u.uid}" data-val="${!isAdmin}">${isAdmin ? "ลบสิทธิ์แอดมิน" : "ตั้งเป็นแอดมิน"}</button>
          <button class="btn btn-outline btn-small" data-act="disable" data-uid="${u.uid}" data-val="${!u.disabled}">${u.disabled ? "เปิดใช้งาน" : "ปิดใช้งาน"}</button>
          <button class="btn btn-outline btn-small" data-act="host" data-uid="${u.uid}" data-val="${!canHost}">${canHost ? "ปลดสิทธิ์ปล่อยเช่า" : "ให้สิทธิ์ปล่อยเช่า"}</button>
          <button class="btn btn-primary btn-small" data-act="extend" data-uid="${u.uid}">ต่ออายุ +5 นาที</button>
        </div>
      </td>
      <td>
        ${u.email ? `<button class="btn btn-outline btn-small" data-act="pwReset" data-email="${u.email}">ส่งอีเมลรีเซ็ต</button>` : `<span class="muted">-</span>`}
        <div class="row" style="margin-top:6px; gap:6px">
          <input id="pw-${u.uid}" type="password" placeholder="รหัสชั่วคราว" style="max-width:150px" />
          <button class="btn btn-outline btn-small" data-act="pwTemp" data-uid="${u.uid}">ตั้งค่า</button>
        </div>
      </td>
    `;
    usersTbody.appendChild(tr);
  }
}

//ส่วนโหลดรายการผู้ใช้จาก Cloud Functions
async function loadUsers() {
  const pageToken = pageTokens[currentPage] || null;
  const listUsers = httpsCallable(functions, "listUsersWithHost");
  const { data } = await listUsers({ pageToken, maxResults: 50 });
  renderUsers(data.users);
  if (data.nextPageToken) {
    // เก็บ token ของหน้าถัดไปไว้ เผื่อกดเลื่อนไปข้างหน้า
    pageTokens[currentPage + 1] = data.nextPageToken;
  } else {
    pageTokens[currentPage + 1] = null;
  }
}

//ส่วนอีเวนต์คลิกปุ่มในแถวผู้ใช้ (สิทธิ์/ปิดการใช้งาน/ต่ออายุ/รหัสผ่าน)
usersTbody.addEventListener("click", async (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;
  const uid = btn.getAttribute("data-uid");
  const val = btn.getAttribute("data-val") === "true";
  const act = btn.getAttribute("data-act");
  try {
    if (act === "admin") {
      const setUserAdmin = httpsCallable(functions, "setUserAdmin");
      await setUserAdmin({ uid, isAdmin: val });
    } else if (act === "disable") {
      const setUserDisabled = httpsCallable(functions, "setUserDisabled");
      await setUserDisabled({ uid, disabled: val });
    } else if (act === "host") {
      const setUserHostPermission = httpsCallable(functions, "setUserHostPermission");
      await setUserHostPermission({ uid, canHost: val });
    } else if (act === "extend") {
      const extendHostPermission = httpsCallable(functions, "extendHostPermission");
      await extendHostPermission({ uid, minutes: 5 });
    } else if (act === "pwReset") {
      const email = btn.getAttribute("data-email");
      if (!email) return alert("ไม่มีอีเมล");
      await sendPasswordResetEmail(auth, email);
      alert("ส่งอีเมลรีเซ็ตรหัสผ่านแล้ว");
    } else if (act === "pwTemp") {
      const input = document.getElementById(`pw-${uid}`);
      const password = (input?.value || "").trim();
      if (password.length < 6) return alert("รหัสผ่านอย่างน้อย 6 ตัวอักษร");
      const setTempPassword = httpsCallable(functions, "setTempPassword");
      await setTempPassword({ uid, password });
      input.value = "";
      alert("ตั้งรหัสชั่วคราวเรียบร้อย");
    }
    await loadUsers();
  } catch (err) {
    alert(err.message || err);
  }
});

//ส่วนปุ่มไปหน้าถัดไป
$("btnNext").addEventListener("click", async () => {
  if (!pageTokens[currentPage + 1]) return;
  currentPage += 1;
  await loadUsers();
});

//ส่วนปุ่มย้อนกลับหน้าก่อน
$("btnPrev").addEventListener("click", async () => {
  if (currentPage === 0) return;
  currentPage -= 1;
  await loadUsers();
});

//ส่วนปุ่มรีเฟรชข้อมูลผู้ใช้
$("btnRefresh").addEventListener("click", async () => {
  await loadUsers();
});

//ส่วนโหลดคำขอสิทธิ์ Host (ซ่อนไว้ใน UI)
async function loadRequests() {
  const listHostRequests = httpsCallable(functions, "listHostRequests");
  const { data } = await listHostRequests({ limit: 100 });
  requestsTbody.innerHTML = "";
  for (const r of data.requests) {
    const tr = document.createElement("tr");
    const ts = r.requestedAt ? new Date(r.requestedAt).toLocaleString() : "-";
    tr.innerHTML = `
      <td>${r.email ?? "-"}</td>
      <td>${r.displayName ?? "-"}</td>
      <td style="font-family:monospace">${r.uid}</td>
      <td>${ts}</td>
      <td>
        <button data-act="approve" data-uid="${r.uid}">อนุมัติ</button>
        <button data-act="reject" data-uid="${r.uid}">ปฏิเสธ</button>
      </td>
    `;
    requestsTbody.appendChild(tr);
  }
}

//ส่วนอีเวนต์คลิกอนุมัติ/ปฏิเสธคำขอ Host
requestsTbody.addEventListener("click", async (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;
  const uid = btn.getAttribute("data-uid");
  const act = btn.getAttribute("data-act");
  try {
    const decide = httpsCallable(functions, "decideHostRequest");
    if (act === "approve") {
      await decide({ uid, approve: true });
    } else if (act === "reject") {
      await decide({ uid, approve: false });
    }
    await loadRequests();
  } catch (err) {
    alert(err.message || err);
  }
});

//ส่วนปุ่มรีเฟรชคำขอ Host
$("btnReqRefresh").addEventListener("click", async () => {
  await loadRequests();
});

//ส่วนปุ่มเข้าสู่ระบบ
$("btnSignIn").addEventListener("click", async () => {
  try {
    const email = $("email").value.trim();
    const password = $("password").value;
    await signInWithEmailAndPassword(auth, email, password);
  } catch (err) {
    alert(err.message || err);
  }
});

//ส่วนปุ่มออกจากระบบ
$("btnSignOut").addEventListener("click", async () => {
  await signOut(auth);
});

//ส่วนปุ่มตั้งตัวเองเป็นแอดมินคนแรก (bootstrap)
$("btnBootstrap").addEventListener("click", async () => {
  try {
    const grantSelf = httpsCallable(functions, "grantSelfAdminIfNone");
    await grantSelf();
    // รีเฟรช id token เพื่อดึง claims ล่าสุด
    await auth.currentUser?.getIdToken(true);
  } catch (err) {
    alert(err.message || err);
  }
});

//ส่วนเปลี่ยนสถานะการเข้าสู่ระบบและปรับ UI ตามสิทธิ์
onAuthStateChanged(auth, async (user) => {
  if (!user) {
    me.textContent = "ยังไม่ได้เข้าสู่ระบบ";
    adminOnly.style.display = "none";
    notAdmin.style.display = "none";
    return;
  }
  me.textContent = `${user.email || "(ไม่มีอีเมล)"}`;
  const tokenResult = await getIdTokenResult(user, true);
  const isAdmin = Boolean(tokenResult.claims?.isAdmin);
  if (isAdmin) {
    adminOnly.style.display = "block";
    // ซ่อนบัตรคำขอปล่อยเช่า ตามนโยบายปัจจุบัน (ยังคงโค้ดไว้ แต่ไม่แสดงผล)
    hostRequestsCard.style.display = "none";
    notAdmin.style.display = "none";
    currentPage = 0; pageTokens = [null];
    await loadUsers();
    // ไม่โหลดรายการคำขอ เพื่อไม่เรียกใช้งานฟังก์ชันส่วนนี้
    // await loadRequests();
  } else {
    adminOnly.style.display = "none";
    hostRequestsCard.style.display = "none";
    notAdmin.style.display = "flex";
  }
});
