import { initializeApp } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import { getAuth, signInWithEmailAndPassword, signOut, onAuthStateChanged, getIdTokenResult } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import { getFunctions, httpsCallable, connectFunctionsEmulator } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-functions.js";

// TODO: เติมค่า config ของโปรเจกต์คุณจาก Firebase Console (Project settings > General > Your apps > Web app)
const firebaseConfig = {
  apiKey: "AIzaSyDfF2QMYEe_G34w8l_yJSIJdUqaNNusy_w",
    authDomain: "myloginapp-fbed0.firebaseapp.com",
    projectId: "myloginapp-fbed0",
    storageBucket: "myloginapp-fbed0.firebasestorage.app",
    messagingSenderId: "587348245983",
    appId: "1:587348245983:web:23c56c9eb0a2421658986a",
    measurementId: "G-0R1L1H42H4"
};

// Guard: แจ้งเตือนถ้ายังไม่ได้กรอกค่า config จริง
(() => {
  const v = firebaseConfig;
  const looksPlaceholder = !v.apiKey || v.apiKey.includes("YOUR_") || !v.projectId || String(v.projectId).includes("YOUR_");
  if (looksPlaceholder) {
    alert("ยังไม่ตั้งค่า Firebase config ใน web_admin/app.js กรุณาคัดลอกโค้ด config ของ Web App จาก Firebase Console แล้ววางแทนค่า YOUR_*");
    throw new Error("Missing Firebase config");
  }
})();

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const functions = getFunctions(app, "us-central1");

// หากต้องการทดสอบกับ emulator ให้ uncomment บรรทัดด้านล่าง
// connectFunctionsEmulator(functions, "localhost", 5001);

const $ = (id) => document.getElementById(id);
const usersTbody = $("users");
const adminOnly = $("adminOnly");
const notAdmin = $("notAdmin");
const me = $("me");

let pageTokens = [null];
let currentPage = 0;

function renderUsers(items) {
  usersTbody.innerHTML = "";
  for (const u of items) {
    const tr = document.createElement("tr");
    const isAdmin = Boolean(u.customClaims?.isAdmin);
    tr.innerHTML = `
      <td>${u.email ?? "-"}</td>
      <td>${u.displayName ?? "-"}</td>
      <td style="font-family:monospace">${u.uid}</td>
      <td>${isAdmin ? "Admin" : "User"}</td>
      <td>${u.disabled ? "ปิดการใช้งาน" : "ใช้งานได้"}</td>
      <td>
        <button data-act="admin" data-uid="${u.uid}" data-val="${!isAdmin}">${isAdmin ? "ลบสิทธิ์แอดมิน" : "ตั้งเป็นแอดมิน"}</button>
        <button data-act="disable" data-uid="${u.uid}" data-val="${!u.disabled}">${u.disabled ? "เปิดใช้งาน" : "ปิดใช้งาน"}</button>
      </td>
    `;
    usersTbody.appendChild(tr);
  }
}

async function loadUsers() {
  const pageToken = pageTokens[currentPage] || null;
  const listUsers = httpsCallable(functions, "listUsers");
  const { data } = await listUsers({ pageToken, maxResults: 50 });
  renderUsers(data.users);
  if (data.nextPageToken) {
    // store next token if navigating forward
    pageTokens[currentPage + 1] = data.nextPageToken;
  } else {
    pageTokens[currentPage + 1] = null;
  }
}

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
    }
    await loadUsers();
  } catch (err) {
    alert(err.message || err);
  }
});

$("btnNext").addEventListener("click", async () => {
  if (!pageTokens[currentPage + 1]) return;
  currentPage += 1;
  await loadUsers();
});

$("btnPrev").addEventListener("click", async () => {
  if (currentPage === 0) return;
  currentPage -= 1;
  await loadUsers();
});

$("btnRefresh").addEventListener("click", async () => {
  await loadUsers();
});

$("btnSignIn").addEventListener("click", async () => {
  try {
    const email = $("email").value.trim();
    const password = $("password").value;
    await signInWithEmailAndPassword(auth, email, password);
  } catch (err) {
    alert(err.message || err);
  }
});

$("btnSignOut").addEventListener("click", async () => {
  await signOut(auth);
});

$("btnBootstrap").addEventListener("click", async () => {
  try {
    const grantSelf = httpsCallable(functions, "grantSelfAdminIfNone");
    await grantSelf();
    // refresh id token to get new claims
    await auth.currentUser?.getIdToken(true);
  } catch (err) {
    alert(err.message || err);
  }
});

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
    notAdmin.style.display = "none";
    currentPage = 0; pageTokens = [null];
    await loadUsers();
  } else {
    adminOnly.style.display = "none";
    notAdmin.style.display = "flex";
  }
});
