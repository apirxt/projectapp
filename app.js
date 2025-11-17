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
const extRequestsCard = $("extRequests");
const tabSwitcher = $("tabSwitcher");
const tabUsers = $("tabUsers");
const tabRequests = $("tabRequests");
const tabExtRequests = $("tabExtRequests");
const emailInput = $("email");
const passwordInput = $("password");
const btnSignIn = $("btnSignIn");
const btnSignOut = $("btnSignOut");
let currentTab = 'users';

function showTab(tab) {
  currentTab = tab;
  if (tab === 'users') {
    adminOnly.style.display = 'block';
    hostRequestsCard.style.display = 'none';
    extRequestsCard.style.display = 'none';
    tabUsers.classList.add('active');
    tabRequests.classList.remove('active');
    tabExtRequests.classList.remove('active');
    loadUsers();
  } else {
    adminOnly.style.display = 'none';
    tabUsers.classList.remove('active');
    if (tab === 'requests') {
      hostRequestsCard.style.display = 'block';
      extRequestsCard.style.display = 'none';
      tabRequests.classList.add('active');
      tabExtRequests.classList.remove('active');
      loadRequests();
    } else if (tab === 'ext') {
      hostRequestsCard.style.display = 'none';
      extRequestsCard.style.display = 'block';
      tabRequests.classList.remove('active');
      tabExtRequests.classList.add('active');
      loadExtRequests();
    }
  }
}

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
    const hostStatusTh = (() => {
      switch (String(hostStatus).toLowerCase()) {
        case 'pending':
          return 'รอตรวจสอบ';
        case 'approved':
          return 'ใช้งานอยู่';
        case 'rejected':
          return 'ปฏิเสธ';
        case 'active':
          return 'อนุมัติ';
        case 'expired':
          return 'หมดอายุ';
        default:
          return '-';
      }
    })();
    const hostStatusCls = (() => {
      switch (String(hostStatus).toLowerCase()) {
        case 'pending':
          return 'badge-nohost'; // ส้ม
        case 'approved':
        case 'active':
          return 'badge-host'; // เขียว
        case 'rejected':
        case 'expired':
          return 'badge-disabled'; // แดง
        default:
          return '';
      }
    })();
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
      <td>${hostStatusTh === '-' ? '-' : `<span class="badge ${hostStatusCls}">${hostStatusTh}</span>`}</td>
      <td>${expStr}</td>
      <td>${activeBadge}</td>
      <td>
        <div class="row">
          <button class="btn btn-outline btn-small" data-act="admin" data-uid="${u.uid}" data-val="${!isAdmin}">${isAdmin ? "ลบสิทธิ์แอดมิน" : "ตั้งเป็นแอดมิน"}</button>
          <button class="btn btn-outline btn-small" data-act="disable" data-uid="${u.uid}" data-val="${!u.disabled}">${u.disabled ? "เปิดใช้งาน" : "ปิดใช้งาน"}</button>
          <button class="btn btn-outline btn-small" data-act="host" data-uid="${u.uid}" data-val="${!canHost}">${canHost ? "ปลดสิทธิ์ปล่อยเช่า" : "ให้สิทธิ์ปล่อยเช่า"}</button>
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


// ปุ่มลบการจองที่ไม่ถูกต้อง (slot ถูกลบไปแล้ว)
$("btnCleanupBookings").addEventListener("click", async () => {
  try {
    if (!confirm('ยืนยันลบการจองที่อ้างอิงประกาศที่ถูกลบแล้ว?')) return;
    const fn = httpsCallable(functions, 'cleanupOrphanBookings');
    const { data } = await fn();
    alert(`ลบการจองที่ไม่ถูกต้องแล้ว ${data.deleted} รายการ`);
  } catch (e) {
    alert(e.message || e);
  }
});

//ส่วนโหลดคำขอสิทธิ์ Host (ซ่อนไว้ใน UI)
async function loadRequests() {
  const listHostRequests = httpsCallable(functions, "listHostRequests");
  const { data } = await listHostRequests({ limit: 100 });
  requestsTbody.innerHTML = "";
  for (const r of data.requests) {
    const tr = document.createElement("tr");
    const ts = r.requestedAt ? new Date(r.requestedAt).toLocaleString() : "-";
    const slip = r.slipUrl ? `<img data-slp="${r.slipUrl}" src="${r.slipUrl}" style="width:44px;height:44px;object-fit:cover;border-radius:6px;cursor:pointer" />` : '<span class="muted">-</span>';
    tr.innerHTML = `
      <td>${r.email ?? "-"}</td>
      <td>${r.displayName ?? "-"}</td>
      <td>${r.fullName ?? "-"}</td>
      <td>${r.phone ?? "-"}</td>
      <td>${slip}</td>
      <td style="font-family:monospace">${r.uid}</td>
      <td>${ts}</td>
      <td>
        <button class="btn btn-primary btn-small" data-act="approve" data-uid="${r.uid}">อนุมัติ</button>
        <button class="btn btn-outline btn-small" data-act="reject" data-uid="${r.uid}">ปฏิเสธ</button>
      </td>
    `;
    requestsTbody.appendChild(tr);
  }
}

// ส่วนโหลดคำขอต่ออายุสิทธิ์
const extRequestsTbody = $("extRequestsTbody");
async function loadExtRequests() {
  const listExt = httpsCallable(functions, 'listExtensionRequests');
  const { data } = await listExt({ limit: 100 });
  extRequestsTbody.innerHTML = "";
  const items = (data.requests || []).filter(r => !r.status || r.status === 'pending');
  for (const r of items) {
    const tr = document.createElement("tr");
    const ts = r.createdAt ? new Date(r.createdAt).toLocaleString() : "-";
    const slip = r.slipUrl ? `<img data-slp="${r.slipUrl}" src="${r.slipUrl}" style="width:44px;height:44px;object-fit:cover;border-radius:6px;cursor:pointer" />` : '<span class="muted">-</span>';
    tr.innerHTML = `
      <td>${r.email ?? "-"}</td>
      <td>${r.displayName ?? "-"}</td>
      <td>${r.fullName ?? "-"}</td>
      <td>${r.phone ?? "-"}</td>
      <td>${slip}</td>
      <td style="font-family:monospace">${r.uid}</td>
      <td>${ts}</td>
      <td>
        <button class="btn btn-primary btn-small" data-act="ext-approve" data-id="${r.id}">อนุมัติ</button>
        <button class="btn btn-outline btn-small" data-act="ext-reject" data-id="${r.id}">ปฏิเสธ</button>
      </td>
    `;
    extRequestsTbody.appendChild(tr);
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

// ปุ่มรีเฟรชคำขอต่ออายุ
$("btnExtRefresh").addEventListener("click", async () => {
  await loadExtRequests();
});


//ส่วนปุ่มเข้าสู่ระบบ
btnSignIn.addEventListener("click", async () => {
  try {
    const email = emailInput.value.trim();
    const password = passwordInput.value;
    await signInWithEmailAndPassword(auth, email, password);
  } catch (err) {
    alert(err.message || err);
  }
});

//ส่วนปุ่มออกจากระบบ
btnSignOut.addEventListener("click", async () => {
  await signOut(auth);
});

// ลบปุ่ม bootstrap ออกจากระบบ (ไม่ใช้งาน)

//ส่วนเปลี่ยนสถานะการเข้าสู่ระบบและปรับ UI ตามสิทธิ์
onAuthStateChanged(auth, async (user) => {
  if (!user) {
    me.textContent = "";
    me.parentElement.style.display = "none";
    adminOnly.style.display = "none";
    notAdmin.style.display = "none";
    tabSwitcher.classList.add('hidden');
    emailInput.style.display = "";
    passwordInput.style.display = "";
    btnSignIn.style.display = "";
    btnSignOut.style.display = "none";
    return;
  }
  me.textContent = `${user.email || "(ไม่มีอีเมล)"}`;
  me.parentElement.style.display = "flex";
  const tokenResult = await getIdTokenResult(user, true);
  const isAdmin = Boolean(tokenResult.claims?.isAdmin);
  if (isAdmin) {
    adminOnly.style.display = "block";
    // แสดงตัวสลับแท็บและเปิดแท็บผู้ใช้เป็นค่าเริ่มต้น
    tabSwitcher.classList.remove('hidden');
    hostRequestsCard.style.display = "none";
    notAdmin.style.display = "none";
    currentPage = 0; pageTokens = [null];
    showTab('users');
    emailInput.style.display = "none";
    passwordInput.style.display = "none";
    btnSignIn.style.display = "none";
    btnSignOut.style.display = "";
  } else {
    adminOnly.style.display = "none";
    hostRequestsCard.style.display = "none";
    notAdmin.style.display = "block";
    tabSwitcher.classList.add('hidden');
    emailInput.style.display = "none";
    passwordInput.style.display = "none";
    btnSignIn.style.display = "none";
    btnSignOut.style.display = "";
  }
});

// คลิกเปลี่ยนแท็บ
tabUsers.addEventListener('click', () => showTab('users'));
tabRequests.addEventListener('click', () => showTab('requests'));
tabExtRequests.addEventListener('click', () => showTab('ext'));

// Modal preview รูปสลิป
const imgModal = $("imgModal");
const imgPreview = $("imgPreview");
const imgClose = $("imgClose");

requestsTbody.addEventListener("click", (e) => {
  const img = e.target.closest('img[data-slp]');
  if (!img) return;
  const url = img.getAttribute('data-slp');
  imgPreview.src = url;
  imgModal.style.display = 'flex';
});

imgClose?.addEventListener('click', () => {
  imgModal.style.display = 'none';
  imgPreview.src = '';
});

imgModal?.addEventListener('click', (e) => {
  if (e.target === imgModal) {
    imgModal.style.display = 'none';
    imgPreview.src = '';
  }
});

// อีเวนต์อนุมัติ/ปฏิเสธคำขอต่ออายุ + preview รูป
extRequestsTbody.addEventListener('click', async (e) => {
  const img = e.target.closest('img[data-slp]');
  if (img) {
    const url = img.getAttribute('data-slp');
    imgPreview.src = url;
    imgModal.style.display = 'flex';
    return;
  }
  const btn = e.target.closest('button');
  if (!btn) return;
  const act = btn.getAttribute('data-act');
  try {
    const decide = httpsCallable(functions, 'decideExtensionRequest');
    if (act === 'ext-approve') {
      await decide({ reqId: btn.getAttribute('data-id'), approve: true, minutes: 10 });
    } else if (act === 'ext-reject') {
      await decide({ reqId: btn.getAttribute('data-id'), approve: false });
    }
    await loadExtRequests();
  } catch (err) {
    alert(err.message || err);
  }
});
