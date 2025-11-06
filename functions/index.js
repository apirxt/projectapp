"use strict";

const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const Stripe = require("stripe");
let legacyConfig = {};
try { legacyConfig = require("firebase-functions").config(); } catch (_) { legacyConfig = {}; }

// คีย์ลับสำหรับโปรเจกต์ (แนะนำให้เก็บใน Secret Manager บน Gen2)
const STRIPE_SECRET = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const GOOGLE_MAPS_API_KEY = defineSecret("GOOGLE_MAPS_API_KEY");

try {
  admin.app();
} catch (_) {
  admin.initializeApp();
}

// ตั้งค่าพื้นฐานของฟังก์ชัน (โซนทำงานเริ่มต้นของ Gen2)
setGlobalOptions({ region: "us-central1" });

// ฟังก์ชันช่วยเช็กว่าคนเรียกเป็นแอดมินหรือไม่ (สำหรับ v2 request)
function assertAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ต้องเข้าสู่ระบบก่อน");
  }
  const claims = request.auth.token || {};
  if (!claims.isAdmin) {
    throw new HttpsError("permission-denied", "ต้องเป็นผู้ดูแลระบบเท่านั้น");
  }
}

// ฟังก์ชันช่วยบันทึก log การทำงานของแอดมิน (เก็บหลักฐานว่าใครทำอะไรเมื่อไหร่)
async function logAdminAction(action, request, details = {}) {
  try {
    const db = admin.firestore();
    const FieldValue = admin.firestore.FieldValue;
    await db.collection("logs_admin_actions").add({
      action,
      at: FieldValue.serverTimestamp(),
      by: request?.auth ? {
        uid: request.auth.uid,
        email: request.auth.token?.email || null,
      } : null,
      details,
    });
  } catch (_) {
    // ถ้าบันทึก log ล้มเหลว ไม่ต้องหยุดงานหลัก ปล่อยผ่านไป
  }
}

// ดึงรายชื่อผู้ใช้แบบแบ่งหน้า
// data: { pageToken?: string, maxResults?: number }
exports.listUsers = onCall(async (request) => {
  assertAdmin(request);
  const data = request.data || {};
  const maxResults = Math.min(Number(data.maxResults || 50), 1000);
  const pageToken = data.pageToken || undefined;
  const result = await admin.auth().listUsers(maxResults, pageToken);
  const users = result.users.map((u) => ({
    uid: u.uid,
    email: u.email || null,
    displayName: u.displayName || null,
    disabled: u.disabled || false,
    customClaims: u.customClaims || {},
    metadata: {
      creationTime: u.metadata.creationTime,
      lastSignInTime: u.metadata.lastSignInTime,
    },
  }));
  return { users, nextPageToken: result.pageToken || null };
});

// ดึงรายชื่อผู้ใช้ พร้อมข้อมูลสถานะ Host จาก Firestore
// data: { pageToken?: string, maxResults?: number }
exports.listUsersWithHost = onCall(async (request) => {
  assertAdmin(request);
  const data = request.data || {};
  const maxResults = Math.min(Number(data.maxResults || 50), 1000);
  const pageToken = data.pageToken || undefined;
  const result = await admin.auth().listUsers(maxResults, pageToken);
  const baseUsers = result.users.map((u) => ({
    uid: u.uid,
    email: u.email || null,
    displayName: u.displayName || null,
    disabled: u.disabled || false,
    customClaims: u.customClaims || {},
    metadata: {
      creationTime: u.metadata.creationTime,
      lastSignInTime: u.metadata.lastSignInTime,
    },
  }));

  // ดึงข้อมูลเอกสาร Firestore ทีละชุดเพื่อความเร็ว
  const db = admin.firestore();
  const refs = baseUsers.map((u) => db.collection("users").doc(u.uid));
  const snaps = await db.getAll(...refs);
  const byId = new Map();
  snaps.forEach((s) => byId.set(s.id, s.exists ? s.data() : {}));

  const users = baseUsers.map((u) => {
    const doc = byId.get(u.uid) || {};
    const hostStatus = doc.hostStatus || null;
    const hostActiveUntil = doc.hostActiveUntil ? doc.hostActiveUntil.toMillis() : null;
    return { ...u, hostStatus, hostActiveUntil };
  });
  return { users, nextPageToken: result.pageToken || null };
});

// ตั้งค่าหรือยกเลิกสิทธิ์แอดมิน
// data: { uid: string, isAdmin: boolean }
exports.setUserAdmin = onCall(async (request) => {
  assertAdmin(request);
  const data = request.data || {};
  const uid = data.uid;
  const isAdmin = Boolean(data.isAdmin);
  if (!uid) throw new HttpsError("invalid-argument", "ต้องระบุ uid");
  const user = await admin.auth().getUser(uid);
  const existing = user.customClaims || {};
  existing.isAdmin = isAdmin;
  await admin.auth().setCustomUserClaims(uid, existing);
  await logAdminAction("setUserAdmin", request, { targetUid: uid, isAdmin });
  return { ok: true };
});

// เปิด/ปิดการใช้งานบัญชีผู้ใช้
// data: { uid: string, disabled: boolean }
exports.setUserDisabled = onCall(async (request) => {
  assertAdmin(request);
  const data = request.data || {};
  const uid = data.uid;
  const disabled = Boolean(data.disabled);
  if (!uid) throw new HttpsError("invalid-argument", "ต้องระบุ uid");
  await admin.auth().updateUser(uid, { disabled });
  await logAdminAction("setUserDisabled", request, { targetUid: uid, disabled });
  return { ok: true };
});

// เปิดสิทธิ์แอดมินให้ตัวเอง ถ้าในระบบยังไม่มีแอดมินคนไหนเลย (ใช้ตอนเริ่มต้นระบบ)
exports.grantSelfAdminIfNone = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ต้องเข้าสู่ระบบก่อน");
  }
  // เช็กว่ามีแอดมินอยู่แล้วหรือยัง
  let token = undefined;
  let found = false;
  do {
    const batch = await admin.auth().listUsers(1000, token);
    for (const u of batch.users) {
      if (u.customClaims && u.customClaims.isAdmin) {
        found = true;
        break;
      }
    }
    token = batch.pageToken;
  } while (token && !found);

  if (found) {
    throw new HttpsError("failed-precondition", "มีผู้ดูแลระบบอยู่แล้ว");
  }
  await admin.auth().setCustomUserClaims(request.auth.uid, { isAdmin: true });
  return { ok: true };
});

// ตั้งรหัสผ่านชั่วคราวให้ผู้ใช้ (เฉพาะแอดมิน)
// data: { uid: string, password: string }
exports.setTempPassword = onCall(async (request) => {
  assertAdmin(request);
  const data = request.data || {};
  const uid = data.uid;
  const password = String(data.password || "");
  if (!uid) throw new HttpsError("invalid-argument", "ต้องระบุ uid");
  if (password.length < 6) {
    throw new HttpsError("invalid-argument", "รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร");
  }
  await admin.auth().updateUser(uid, { password });
  await logAdminAction("setTempPassword", request, { targetUid: uid });
  return { ok: true, uid };
});

// ผู้ใช้ยื่นคำขอเป็น Host เพื่อปล่อยเช่าที่จอดรถ
// จะสร้าง/อัปเดตเอกสาร users/{uid} ให้มี hostStatus='requested'
exports.requestHostRole = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ต้องเข้าสู่ระบบก่อน");
  }
  const uid = request.auth.uid;
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  const data = snap.exists ? snap.data() || {} : {};
  const status = data.hostStatus || "none";
  if (status === "requested") {
    throw new HttpsError("failed-precondition", "คุณได้ส่งคำขอไว้แล้ว");
  }
  if (status === "approved") {
    throw new HttpsError("failed-precondition", "คุณได้รับสิทธิ์แล้ว");
  }
  // เก็บอีเมล/ชื่อไว้ในเอกสาร เพื่อให้แอดมินดูสะดวกในหน้าเว็บ
  let email = request.auth.token?.email || null;
  let displayName = request.auth.token?.name || null;
  try {
    const u = await admin.auth().getUser(uid);
    email = u.email || email;
    displayName = u.displayName || displayName;
  } catch (_) {}
  await ref.set(
    {
      uid,
      email: email || null,
      displayName: displayName || null,
      hostStatus: "requested",
      requestedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { status: "requested" };
});

// ฝั่งแอดมิน: ดึงลิสต์คำขอเป็น Host (users ที่ hostStatus='requested')
// data: { limit?: number }
exports.listHostRequests = onCall(async (request) => {
  assertAdmin(request);
  const db = admin.firestore();
  const limit = Math.min(Number(request.data?.limit || 50), 200);
  const qs = await db
    .collection("users")
    .where("hostStatus", "==", "requested")
    .orderBy("requestedAt", "desc")
    .limit(limit)
    .get();
  const items = qs.docs.map((d) => {
    const v = d.data();
    return {
      uid: v.uid || d.id,
      email: v.email || null,
      displayName: v.displayName || null,
      requestedAt: v.requestedAt ? v.requestedAt.toMillis() : null,
    };
  });
  return { requests: items };
});

// ฝั่งแอดมิน: อนุมัติ/ปฏิเสธ คำขอเป็น Host
// data: { uid: string, approve: boolean, note?: string }
exports.decideHostRequest = onCall(async (request) => {
  assertAdmin(request);
  const data = request.data || {};
  const uid = data.uid;
  const approve = Boolean(data.approve);
  const note = data.note || null;
  if (!uid) throw new HttpsError("invalid-argument", "ต้องระบุ uid");

  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const ref = db.collection("users").doc(uid);

  const user = await admin.auth().getUser(uid);
  const claims = user.customClaims || {};

  if (approve) {
    claims.canHostParking = true;
    await admin.auth().setCustomUserClaims(uid, claims);
    await ref.set(
      {
        hostStatus: "approved",
        approvedAt: FieldValue.serverTimestamp(),
        approvedBy: {
          uid: request.auth.uid,
          email: request.auth.token?.email || null,
        },
        decisionNote: note,
      },
      { merge: true }
    );
    await logAdminAction("approveHost", request, { targetUid: uid, note });
    return { uid, status: "approved" };
  } else {
  // ถ้ามีสิทธิ์ค้างอยู่ ให้ลบสิทธิ์ก่อน
    if (claims.canHostParking) {
      delete claims.canHostParking;
      await admin.auth().setCustomUserClaims(uid, claims);
    }
    await ref.set(
      {
        hostStatus: "rejected",
        rejectedAt: FieldValue.serverTimestamp(),
        approvedBy: {
          uid: request.auth.uid,
          email: request.auth.token?.email || null,
        },
        decisionNote: note,
      },
      { merge: true }
    );
    await logAdminAction("rejectHost", request, { targetUid: uid, note });
    return { uid, status: "rejected" };
  }
});

  // ฝั่งแอดมิน: ให้หรือยกเลิกสิทธิ์ Host โดยตรง
  // data: { uid: string, canHost: boolean, note?: string }
  exports.setUserHostPermission = onCall(async (request) => {
    assertAdmin(request);
    const data = request.data || {};
    const uid = data.uid;
    const canHost = Boolean(data.canHost);
    const note = data.note || null;
    if (!uid) throw new HttpsError("invalid-argument", "ต้องระบุ uid");

    const db = admin.firestore();
    const FieldValue = admin.firestore.FieldValue;
    const ref = db.collection("users").doc(uid);
    const user = await admin.auth().getUser(uid);
    const claims = user.customClaims || {};

    if (canHost) {
      claims.canHostParking = true;
      await admin.auth().setCustomUserClaims(uid, claims);
      await ref.set(
        {
          hostStatus: "approved",
          approvedAt: FieldValue.serverTimestamp(),
          approvedBy: {
            uid: request.auth.uid,
            email: request.auth.token?.email || null,
          },
          decisionNote: note,
        },
        { merge: true }
      );
      await logAdminAction("setUserHostPermission.grant", request, { targetUid: uid, note });
      return { uid, canHost: true };
    } else {
      if (claims.canHostParking) {
        delete claims.canHostParking;
        await admin.auth().setCustomUserClaims(uid, claims);
      }
      await ref.set(
        {
          hostStatus: "none",
          revokedAt: FieldValue.serverTimestamp(),
          approvedBy: {
            uid: request.auth.uid,
            email: request.auth.token?.email || null,
          },
          decisionNote: note,
        },
        { merge: true }
      );
      await logAdminAction("setUserHostPermission.revoke", request, { targetUid: uid, note });
      return { uid, canHost: false };
    }
  });

// ฝั่งแอดมิน: ต่ออายุสิทธิ์ Host เพิ่มจากตอนนี้ + N นาที (ค่าเริ่มต้น 5 นาที)
// data: { uid: string, minutes?: number }
exports.extendHostPermission = onCall(async (request) => {
  assertAdmin(request);
  const uid = request.data?.uid;
  const minutes = Number(request.data?.minutes || 5);
  if (!uid) throw new HttpsError("invalid-argument", "ต้องระบุ uid");

  const db = admin.firestore();
  const ref = db.collection("users").doc(uid);
  const newUntil = new Date(Date.now() + minutes * 60 * 1000);

  // ยืนยันให้ claim เป็น true เสมอ (กันกรณีค่าไม่ตรง)
  try {
    const user = await admin.auth().getUser(uid);
    const claims = user.customClaims || {};
    claims.canHostParking = true;
    await admin.auth().setCustomUserClaims(uid, claims);
  } catch (_) {}

  await ref.set(
    {
      hostStatus: "active",
      hostActiveUntil: admin.firestore.Timestamp.fromDate(newUntil),
    },
    { merge: true }
  );
  await logAdminAction("extendHostPermission", request, { targetUid: uid, minutes });
  return { uid, hostActiveUntil: newUntil.getTime() };
});

// ส่วนชำระเงินด้วย Stripe สำหรับการสมัครเป็น Host

function getStripe() {
  // พยายามใช้คีย์จาก Secret Manager ก่อน ถ้าไม่มีค่อยลองจาก env/config อื่นๆ
  const key =
    STRIPE_SECRET.value() ||
    process.env.STRIPE_SECRET ||
    process.env.STRIPE_SECRET_KEY ||
    process.env.stripe_secret ||
    legacyConfig?.stripe?.secret;
  if (!key) return null;
  // ใช้ API version ตามค่าเริ่มต้นของแอคเคานต์ เพื่อลดปัญหาเวอร์ชันไม่ตรงกัน
  return new Stripe(key);
}

// สร้าง Stripe Checkout สำหรับลงทะเบียน Host (ตัวอย่างคิดราคา 100 บาท)
// คืนค่า: { url }
exports.createHostRegistration = onCall({ secrets: [STRIPE_SECRET] }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "ต้องเข้าสู่ระบบก่อน");
  const stripe = getStripe();
  if (!stripe) throw new HttpsError("failed-precondition", "ยังไม่ตั้งค่า stripe.secret (STRIPE_SECRET) บน Functions env");

  const uid = request.auth.uid;
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const ref = db.collection("users").doc(uid);

  // สร้าง Checkout Session
  let session;
  try {
    session = await stripe.checkout.sessions.create({
      mode: "payment",
      client_reference_id: uid,
      metadata: { uid },
      line_items: [
        {
          price_data: {
            currency: "thb",
            // Stripe กำหนดขั้นต่ำสำหรับ THB ตามที่บัญชีแจ้งใน error (฿100.00)
            // ใช้หน่วยเป็น satang จึงใส่ 10000 = ฿100.00
            unit_amount: 10000, // 100.00 THB
            product_data: { name: "Host Registration (5 minutes)" },
          },
          quantity: 1,
        },
      ],
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel",
    });
  } catch (e) {
    console.error("createHostRegistration: Stripe error", e?.message || e);
    throw new HttpsError("internal", `stripe_error: ${e?.message || "unknown"}`);
  }

  await ref.set(
    {
      uid,
      hostStatus: "payment_pending",
      lastPaymentStatus: "pending",
      registration: {
        provider: "stripe",
        sessionId: session.id,
        amount: 1,
        currency: "THB",
        createdAt: FieldValue.serverTimestamp(),
      },
    },
    { merge: true }
  );

  return { url: session.url };
});

// Stripe webhook: เปิดสิทธิ์ Host หลังชำระเงินสำเร็จ และกำหนดเวลาใช้งาน 5 นาที
exports.stripeWebhook = onRequest({ secrets: [STRIPE_SECRET, STRIPE_WEBHOOK_SECRET] }, async (req, res) => {
  const stripe = getStripe();
  const webhookSecret = STRIPE_WEBHOOK_SECRET.value() || process.env.STRIPE_WEBHOOK_SECRET || process.env.stripe_webhook_secret || legacyConfig?.stripe?.webhook_secret;
  if (!stripe || !webhookSecret) {
    res.status(500).send("Stripe not configured");
    return;
  }
  let event;
  try {
    const sig = req.headers["stripe-signature"];
    event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
  } catch (err) {
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object;
    const uid = session.client_reference_id || session.metadata?.uid;
    if (uid) {
      const db = admin.firestore();
      const FieldValue = admin.firestore.FieldValue;
      const ref = db.collection("users").doc(uid);

  const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // ตอนนี้ + 5 นาที
  // ตั้งสิทธิ์และสถานะ
      try {
        const user = await admin.auth().getUser(uid);
        const claims = user.customClaims || {};
        claims.canHostParking = true;
        await admin.auth().setCustomUserClaims(uid, claims);
      } catch (_) {}

      await ref.set(
        {
          hostStatus: "active",
          hostActiveUntil: admin.firestore.Timestamp.fromDate(expiresAt),
          lastPaymentStatus: "success",
          registration: {
            paidAt: FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
      await logAdminAction("stripe.activateHost", null, { uid, sessionId: session.id });
    }
  }

  res.json({ received: true });
});

// ตัวช่วย: จัดการไฟล์ใน Storage
function getDefaultBucket() {
  try {
    const cfg = process.env.FIREBASE_CONFIG ? JSON.parse(process.env.FIREBASE_CONFIG) : null;
    const bucketName = cfg?.storageBucket || `${process.env.GCLOUD_PROJECT}.appspot.com`;
    return admin.storage().bucket(bucketName);
  } catch (_) {
    return admin.storage().bucket();
  }
}

function extractPathFromImageUrl(url) {
  // รองรับรูปแบบ URL: https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?...
  try {
    const marker = '/o/';
    const i = url.indexOf(marker);
    if (i === -1) return null;
    const after = url.substring(i + marker.length);
    const pathEncoded = after.split('?')[0];
    return decodeURIComponent(pathEncoded);
  } catch (_) {
    return null;
  }
}

async function deleteImagesForDocData(data) {
  const bucket = getDefaultBucket();
  const paths = new Set();
  const arr = data?.image_paths;
  if (Array.isArray(arr)) {
    for (const p of arr) if (typeof p === 'string' && p) paths.add(p);
  }
  const imageUrl = data?.image_url;
  if (typeof imageUrl === 'string' && imageUrl) {
    const p = extractPathFromImageUrl(imageUrl);
    if (p) paths.add(p);
  }
  for (const p of paths) {
    try {
      await bucket.file(p).delete({ ignoreNotFound: true });
  } catch (_) { /* ลบไม่ได้ก็ข้ามไป */ }
  }
}

// งานตามเวลา (ทุกนาที): ยกเลิกสิทธิ์ Host ที่หมดอายุ
exports.revokeExpiredHosts = onSchedule("* * * * *", async () => {
  const db = admin.firestore();
  const now = new Date();
  const qs = await db
    .collection("users")
    .where("hostStatus", "==", "active")
    .where("hostActiveUntil", "<=", admin.firestore.Timestamp.fromDate(now))
    .limit(300)
    .get();

  for (const doc of qs.docs) {
    const uid = doc.id;
    try {
      const user = await admin.auth().getUser(uid);
      const claims = user.customClaims || {};
      if (claims.canHostParking) {
        delete claims.canHostParking;
        await admin.auth().setCustomUserClaims(uid, claims);
      }
    } catch (_) {}

    await doc.ref.set(
      { hostStatus: "expired", revokedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    await logAdminAction("auto.revokeExpiredHost", null, { uid });

  // ลบประกาศทั้งหมดของผู้ใช้รายนี้พร้อมรูปภาพ
    try {
      const listings = await db
        .collection('parking_slots')
        .where('ownerId', '==', uid)
        .limit(500)
        .get();
      for (const d of listings.docs) {
        const data = d.data() || {};
        await deleteImagesForDocData(data);
        await d.ref.delete();
        await logAdminAction('auto.deleteListingOnExpiry', null, { uid, slotId: d.id });
      }
  // ตีธงว่าล้างแล้ว เพื่อลดการทำงานซ้ำในรอบถัดไป
      await doc.ref.set({ listingsPurged: true }, { merge: true });
    } catch (e) {
      await logAdminAction('auto.deleteListingOnExpiry.error', null, { uid, error: String(e) });
    }
  }

  // เก็บตก: ผู้ใช้ที่หมดอายุแล้ว แต่ยังไม่ได้ล้างประกาศ
  const qsExpired = await db
    .collection('users')
    .where('hostStatus', '==', 'expired')
    .where('hostActiveUntil', '<=', admin.firestore.Timestamp.fromDate(now))
    .limit(300)
    .get();
  for (const doc of qsExpired.docs) {
    const uid = doc.id;
    const v = doc.data() || {};
  if (v.listingsPurged === true) continue; // ทำไปแล้ว ข้ามได้
    try {
      const listings = await db
        .collection('parking_slots')
        .where('ownerId', '==', uid)
        .limit(500)
        .get();
      for (const d of listings.docs) {
        const data = d.data() || {};
        await deleteImagesForDocData(data);
        await d.ref.delete();
        await logAdminAction('auto.deleteListingOnExpiry.backfill', null, { uid, slotId: d.id });
      }
      await doc.ref.set({ listingsPurged: true }, { merge: true });
    } catch (e) {
      await logAdminAction('auto.deleteListingOnExpiry.backfill.error', null, { uid, error: String(e) });
    }
  }
});

// จุดตรวจสอบ (debug): เช็กว่ามีการตั้งค่า Stripe ไว้หรือไม่ (ไม่แสดงค่าจริง)
exports.stripeEnv = onRequest({ secrets: [STRIPE_SECRET, STRIPE_WEBHOOK_SECRET] }, async (req, res) => {
  const env = process.env;
  res.json({
    has_secret_manager_STRIPE_SECRET: Boolean(STRIPE_SECRET.value()),
    has_secret_manager_STRIPE_WEBHOOK_SECRET: Boolean(STRIPE_WEBHOOK_SECRET.value()),
    has_STRIPE_SECRET: Boolean(env.STRIPE_SECRET),
    has_STRIPE_SECRET_KEY: Boolean(env.STRIPE_SECRET_KEY),
    has_stripe_secret: Boolean(env.stripe_secret),
    legacy_config: {
      has_config: legacyConfig && Object.keys(legacyConfig).length > 0,
      has_stripe: Boolean(legacyConfig?.stripe),
      has_stripe_secret: Boolean(legacyConfig?.stripe?.secret),
    },
  });
});

// ฝั่งแอดมิน: ลบรูปใน Storage โดยระบุ path หรือ URL
// data: { path?: string, url?: string }
exports.adminDeleteImage = onCall(async (request) => {
  assertAdmin(request);
  const data = request.data || {};
  let { path, url } = data;
  if (!path && !url) {
    throw new HttpsError('invalid-argument', 'ต้องระบุ path หรือ url');
  }
  try {
    if (!path && url) {
      path = extractPathFromImageUrl(url);
    }
    if (!path) {
      throw new HttpsError('invalid-argument', 'url ไม่ถูกต้อง หรือไม่สามารถแปลงเป็น path ได้');
    }
    const bucket = getDefaultBucket();
    await bucket.file(path).delete({ ignoreNotFound: true });
    await logAdminAction('adminDeleteImage', request, { path });
    return { ok: true, path };
  } catch (e) {
    throw new HttpsError('internal', String(e?.message || e));
  }
});

// คำนวณระยะทางตามเส้นทาง (Driving/Walking ฯลฯ) ด้วย Google Distance Matrix API
// callable: routeMatrix
// data: {
//   origin: { lat: number, lng: number },
//   destinations: Array<{ lat: number, lng: number }>,
//   mode?: 'driving' | 'walking' | 'bicycling' | 'transit'
// }
// ส่งกลับ: { distances: Array<{ meters: number|null, seconds: number|null }>, status: string }
exports.routeMatrix = onCall({ secrets: [GOOGLE_MAPS_API_KEY] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  }
  const data = request.data || {};
  const origin = data.origin;
  const destinations = Array.isArray(data.destinations) ? data.destinations : [];
  const mode = (data.mode || 'driving');

  if (!origin || typeof origin.lat !== 'number' || typeof origin.lng !== 'number') {
    throw new HttpsError('invalid-argument', 'origin ไม่ถูกต้อง');
  }
  if (destinations.length === 0) {
    return { distances: [], status: 'ok' };
  }
  // จำกัดทีละ 25 จุดหมาย ต่อ 1 คำขอ ตามข้อจำกัดของ API
  const capped = destinations.slice(0, 25);

  const key = GOOGLE_MAPS_API_KEY.value() || process.env.GOOGLE_MAPS_API_KEY || legacyConfig?.google?.maps_api_key;
  if (!key) {
    throw new HttpsError('failed-precondition', 'ยังไม่ตั้งค่า GOOGLE_MAPS_API_KEY บน Functions Secrets');
  }

  const originsParam = `${origin.lat},${origin.lng}`;
  const destParam = capped.map((d) => `${d.lat},${d.lng}`).join('|');
  const url = `https://maps.googleapis.com/maps/api/distancematrix/json?origins=${encodeURIComponent(originsParam)}&destinations=${encodeURIComponent(destParam)}&mode=${encodeURIComponent(mode)}&units=metric&key=${encodeURIComponent(key)}`;

  let json;
  try {
    const resp = await fetch(url);
    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`HTTP ${resp.status}: ${text}`);
    }
    json = await resp.json();
  } catch (e) {
    throw new HttpsError('internal', `fetch_error: ${String(e?.message || e)}`);
  }

  if (json.status !== 'OK') {
    throw new HttpsError('internal', `distance_matrix_error: ${json.status}`);
  }

  const row = Array.isArray(json.rows) && json.rows[0];
  const elements = Array.isArray(row?.elements) ? row.elements : [];
  const out = elements.map((el) => {
    if (!el || el.status !== 'OK') return { meters: null, seconds: null };
    const meters = el.distance?.value ?? null;
    const seconds = el.duration?.value ?? null;
    return { meters, seconds };
  });

  return { distances: out, status: 'ok' };
});
