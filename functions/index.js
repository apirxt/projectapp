"use strict";

const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
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
      fullName: v.registration?.fullName || null,
      phone: v.registration?.phone || null,
      slipUrl: v.registration?.slipUrl || null,
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
    // อนุมัติแล้ว เปิดสิทธิ์ทันทีเป็นเวลา 10 นาที จากตอนนี้
    const newUntil = new Date(Date.now() + 10 * 60 * 1000);
    claims.canHostParking = true;
    await admin.auth().setCustomUserClaims(uid, claims);
    await ref.set(
      {
        hostStatus: "active",
        hostActiveUntil: admin.firestore.Timestamp.fromDate(newUntil),
        approvedAt: FieldValue.serverTimestamp(),
        approvedBy: {
          uid: request.auth.uid,
          email: request.auth.token?.email || null,
        },
        decisionNote: note,
      },
      { merge: true }
    );
    await logAdminAction("approveHost.active10min", request, { targetUid: uid });
    return { uid, status: "active", hostActiveUntil: newUntil.getTime() };
  } else {
  // ถ้ามีสิทธิ์ค้างอยู่ ให้ลบสิทธิ์ก่อน และลบประกาศทั้งหมดของผู้ใช้นี้
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
    // พยายามลบประกาศเดิม (ถ้ามี)
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
        await logAdminAction('decideHostRequest.deleteListingOnReject', request, { uid, slotId: d.id });
      }
    } catch (e) {
      await logAdminAction('decideHostRequest.deleteListingOnReject.error', request, { uid, error: String(e) });
    }
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
      // เมื่อยกเลิกสิทธิ์ ให้ลบประกาศทั้งหมดของผู้ใช้นี้เพื่อไม่ให้แสดงในแอป
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
          await logAdminAction('setUserHostPermission.revoke.deleteListing', request, { uid, slotId: d.id });
        }
      } catch (e) {
        await logAdminAction('setUserHostPermission.revoke.deleteListing.error', request, { uid, error: String(e) });
      }
      await logAdminAction("setUserHostPermission.revoke", request, { targetUid: uid, note });
      return { uid, canHost: false };
    }
  });

// ผู้ใช้ส่งคำขอลงทะเบียนแบบใหม่: ระบุชื่อ-นามสกุล, เบอร์โทร และลิงก์รูปสลิป
// data: { fullName: string, phone: string, slipUrl: string }
exports.submitHostRegistration = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  }
  const uid = request.auth.uid;
  const data = request.data || {};
  const fullName = String(data.fullName || '').trim();
  const phone = String(data.phone || '').trim();
  const slipUrl = String(data.slipUrl || '').trim();
  if (!fullName || !phone || !slipUrl) {
    throw new HttpsError('invalid-argument', 'ต้องระบุชื่อ-นามสกุล เบอร์โทร และรูปสลิป');
  }

  // บันทึกลง users/{uid}
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const ref = db.collection('users').doc(uid);

  // เก็บอีเมล/ชื่อเพื่อความสะดวกของแอดมิน
  let email = request.auth.token?.email || null;
  let displayName = request.auth.token?.name || null;
  try {
    const u = await admin.auth().getUser(uid);
    email = u.email || email;
    displayName = u.displayName || displayName;
  } catch (_) {}

  await ref.set({
    uid,
    email: email || null,
    displayName: displayName || null,
    hostStatus: 'requested',
    requestedAt: FieldValue.serverTimestamp(),
    registration: {
      fullName,
      phone,
      slipUrl,
      provider: 'manual',
      createdAt: FieldValue.serverTimestamp(),
    },
  }, { merge: true });

  await logAdminAction('submitHostRegistration', request, { uid });
  return { status: 'requested' };
});

// ผู้ใช้ส่งคำขอต่ออายุสิทธิ์ (แนบสลิปเหมือนลงทะเบียนครั้งแรก)
// data: { fullName: string, phone: string, slipUrl: string }
exports.submitHostExtension = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  const uid = request.auth.uid;
  const data = request.data || {};
  const fullName = String(data.fullName || '').trim();
  const phone = String(data.phone || '').trim();
  const slipUrl = String(data.slipUrl || '').trim();
  if (!fullName || !phone || !slipUrl) {
    throw new HttpsError('invalid-argument', 'ต้องระบุชื่อ-นามสกุล เบอร์โทร และรูปสลิป');
  }

  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const udata = userSnap.exists ? (userSnap.data() || {}) : {};
  // อนุญาตเฉพาะผู้ที่เคยลงทะเบียนแบบ manual เท่านั้น (ไม่ใช่เปิดสิทธิ์ตรงโดยแอดมิน)
  const provider = udata?.registration?.provider || null;
  if (provider !== 'manual') {
    throw new HttpsError('failed-precondition', 'บัญชีนี้ไม่ได้ลงทะเบียนผ่านระบบสลิป');
  }

  // สร้างคำขอในคอลเลกชัน host_extension_requests
  await db.collection('host_extension_requests').add({
    uid,
    email: udata.email || request.auth.token?.email || null,
    displayName: udata.displayName || request.auth.token?.name || null,
    fullName,
    phone,
    slipUrl,
    status: 'pending',
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

// แอดมิน: ดึงรายการคำขอต่ออายุ
// data: { limit?: number }
exports.listExtensionRequests = onCall(async (request) => {
  assertAdmin(request);
  const db = admin.firestore();
  const limit = Math.min(Number(request.data?.limit || 100), 300);
  const qs = await db.collection('host_extension_requests').orderBy('createdAt', 'desc').limit(limit).get();
  const items = [];
  for (const d of qs.docs) {
    const v = d.data() || {};
    const status = v.status || 'pending';
    if (status !== 'pending') continue; // แสดงเฉพาะที่ยังรอดำเนินการ
    items.push({
      id: d.id,
      uid: v.uid || null,
      email: v.email || null,
      displayName: v.displayName || null,
      fullName: v.fullName || null,
      phone: v.phone || null,
      slipUrl: v.slipUrl || null,
      status,
      createdAt: v.createdAt && typeof v.createdAt.toMillis === 'function' ? v.createdAt.toMillis() : null,
    });
  }
  return { requests: items };
});

// แอดมิน: อนุมัติ/ปฏิเสธคำขอต่ออายุ
// data: { reqId: string, approve: boolean, minutes?: number }
exports.decideExtensionRequest = onCall(async (request) => {
  assertAdmin(request);
  const { reqId, approve } = request.data || {};
  const minutes = Number(request.data?.minutes || 10);
  if (!reqId || typeof approve !== 'boolean') {
    throw new HttpsError('invalid-argument', 'ต้องระบุ reqId และ approve');
  }
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const reqRef = db.collection('host_extension_requests').doc(String(reqId));
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) throw new HttpsError('not-found', 'ไม่พบคำขอ');
  const r = reqSnap.data() || {};
  const uid = r.uid;
  if (!uid) throw new HttpsError('invalid-argument', 'คำขอไม่มี uid');

  if (!approve) {
    await reqRef.set({ decidedAt: FieldValue.serverTimestamp(), status: 'rejected', decidedBy: { uid: request.auth.uid, email: request.auth.token?.email || null } }, { merge: true });
    return { ok: true, status: 'rejected' };
  }

  const userRef = db.collection('users').doc(String(uid));
  const userSnap = await userRef.get();
  const v = userSnap.exists ? (userSnap.data() || {}) : {};
  const now = Date.now();
  let base = now;
  const curUntil = v.hostActiveUntil?.toDate?.()?.getTime?.() || null;
  if (typeof curUntil === 'number' && curUntil > now) base = curUntil;
  const newUntil = new Date(base + minutes * 60 * 1000);

  // ยืนยัน claim
  try {
    const user = await admin.auth().getUser(uid);
    const claims = user.customClaims || {};
    claims.canHostParking = true;
    await admin.auth().setCustomUserClaims(uid, claims);
  } catch (_) {}

  await userRef.set({ hostStatus: 'active', hostActiveUntil: admin.firestore.Timestamp.fromDate(newUntil) }, { merge: true });
  await reqRef.set({ decidedAt: FieldValue.serverTimestamp(), status: 'approved', decidedBy: { uid: request.auth.uid, email: request.auth.token?.email || null } }, { merge: true });
  return { ok: true, status: 'approved', hostActiveUntil: newUntil.getTime() };
});
// แอดมิน: ย้ายคำขอรุ่นเก่าใน host_rights_requests ไปเก็บใน users/{uid}
// data: { deleteAfter?: boolean, limit?: number }
exports.backfillLegacyHostRequests = onCall(async (request) => {
  assertAdmin(request);
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;

  const del = Boolean(request.data?.deleteAfter || false);
  const lim = Math.min(Number(request.data?.limit || 500), 2000);

  const snap = await db.collection('host_rights_requests').limit(lim).get();
  let migrated = 0;
  for (const d of snap.docs) {
    try {
      const v = d.data() || {};
      const uid = v.userId || null;
      if (!uid) continue;
      const fullName = v.name || v.fullName || null;
      const phone = v.phone || null;
      const slipUrl = v.imageUrl || v.slipUrl || null;
      const createdAt = v.createdAt || null;

      // ดึงอีเมล/ชื่อผู้ใช้จาก Auth เพื่อเก็บในเอกสาร users
      let email = null, displayName = null;
      try {
        const u = await admin.auth().getUser(uid);
        email = u.email || null;
        displayName = u.displayName || null;
      } catch (_) {}

      const ref = db.collection('users').doc(String(uid));
      const cur = await ref.get();
      const curData = cur.exists ? (cur.data() || {}) : {};
      const curStatus = curData.hostStatus || 'none';

      // ไม่ override สถานะที่สูงกว่า (approved/active/rejected)
      if (['approved', 'active'].includes(String(curStatus))) {
        if (del) await d.ref.delete().catch(()=>{});
        continue;
      }

      await ref.set({
        uid,
        email: email ?? curData.email ?? null,
        displayName: displayName ?? curData.displayName ?? null,
        hostStatus: 'requested',
        requestedAt: createdAt || FieldValue.serverTimestamp(),
        registration: {
          ...(curData.registration || {}),
          fullName: fullName ?? curData.registration?.fullName ?? null,
          phone: phone ?? curData.registration?.phone ?? null,
          slipUrl: slipUrl ?? curData.registration?.slipUrl ?? null,
          provider: curData.registration?.provider || 'legacy',
          createdAt: curData.registration?.createdAt || FieldValue.serverTimestamp(),
        },
      }, { merge: true });

      if (del) await d.ref.delete().catch(()=>{});
      migrated++;
    } catch (e) {
      // ข้ามอันที่ผิดพลาดเพื่อให้กระบวนการหลักเดินต่อ
    }
  }
  return { migrated, scanned: snap.size, deleted: del ? migrated : 0 };
});

// ฝั่งแอดมิน: ต่ออายุสิทธิ์ Host โดยบวกต่อจากเวลาที่เหลืออยู่ (ถ้ามี)
// data: { uid: string, minutes?: number }
exports.extendHostPermission = onCall(async (request) => {
  assertAdmin(request);
  const uid = request.data?.uid;
  const minutes = Number(request.data?.minutes || 5);
  if (!uid) throw new HttpsError("invalid-argument", "ต้องระบุ uid");

  const db = admin.firestore();
  const ref = db.collection("users").doc(uid);
  const now = Date.now();
  let base = now;
  try {
    const snap = await ref.get();
    const v = snap.exists ? (snap.data() || {}) : {};
    const currentUntil = v.hostActiveUntil?.toDate?.()?.getTime?.() || null;
    if (typeof currentUntil === 'number' && currentUntil > now) {
      base = currentUntil; // ต่อจากเวลาที่ยังเหลืออยู่
    }
  } catch (_) {}
  const newUntil = new Date(base + minutes * 60 * 1000);

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

// ผู้ใช้ต่ออายุสิทธิ์ปล่อยเช่าด้วยตัวเอง (สำหรับผู้ที่มีสิทธิ์อยู่แล้ว)
// data: { minutes?: number }
exports.selfExtendHostPermission = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  const uid = request.auth.uid;
  const minutes = Number(request.data?.minutes || 10);
  const db = admin.firestore();
  const ref = db.collection('users').doc(uid);

  // ตรวจว่ามีสิทธิ์หรืออยู่ในสถานะที่อนุญาตให้ต่ออายุได้
  const snap = await ref.get();
  const v = snap.exists ? (snap.data() || {}) : {};
  const status = String(v.hostStatus || 'none');
  if (!['approved', 'active'].includes(status)) {
    throw new HttpsError('failed-precondition', 'ยังไม่มีสิทธิ์ปล่อยเช่า');
  }

  // ต่ออายุจากเวลาที่เหลือ ถ้ายังไม่หมดอายุ
  const now = Date.now();
  let base = now;
  const curUntil = v.hostActiveUntil?.toDate?.()?.getTime?.() || null;
  if (typeof curUntil === 'number' && curUntil > now) base = curUntil;

  const newUntil = new Date(base + minutes * 60 * 1000);

  // ยืนยัน claim
  try {
    const user = await admin.auth().getUser(uid);
    const claims = user.customClaims || {};
    claims.canHostParking = true;
    await admin.auth().setCustomUserClaims(uid, claims);
  } catch (_) {}

  await ref.set({
    hostStatus: 'active',
    hostActiveUntil: admin.firestore.Timestamp.fromDate(newUntil),
  }, { merge: true });
  return { hostActiveUntil: newUntil.getTime() };
});

// เจ้าของ: ดึงรายการจองของตนเอง (กล่องขาเข้า)
// data: { status?: string, limit?: number, cursor?: number }
exports.listOwnerBookings = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบ');
  const ownerUid = request.auth.uid;
  const { status, limit, cursor } = request.data || {};
  const lim = Math.min(Number(limit || 50), 100);
  const db = admin.firestore();
  let q = db.collection('user_bookings')
    .where('ownerId', '==', ownerUid)
    .orderBy('createdAt', 'desc')
    .limit(lim);
  if (status && typeof status === 'string' && status !== 'all') {
    q = db.collection('user_bookings')
      .where('ownerId', '==', ownerUid)
      .where('status', '==', status)
      .orderBy('createdAt', 'desc')
      .limit(lim);
  }
  if (cursor && typeof cursor === 'number') {
    q = q.startAfter(admin.firestore.Timestamp.fromMillis(cursor));
  }
  const snap = await q.get();
  const items = snap.docs.map(d => {
    const v = d.data() || {};
    return {
      id: d.id,
      userId: v.userId || null,
      ownerId: v.ownerId || null,
      slotId: v.slotId || null,
      slotName: v.slotName || null,
      name: v.name || null,
      phone: v.phone || null,
      imageUrl: v.imageUrl || null,
      vehicleType: v.vehicleType || null,
      bookingDate: v.bookingDate ? v.bookingDate.toMillis() : null,
      status: v.status || 'pending',
      createdAt: v.createdAt ? v.createdAt.toMillis() : null,
      approvedAt: v.approvedAt ? v.approvedAt.toMillis() : null,
      rejectedAt: v.rejectedAt ? v.rejectedAt.toMillis() : null,
    };
  });
  // คืน nextCursor เฉพาะกรณีที่ยังมีหน้าถัดไป (ได้ครบ lim และมี createdAt ของแถวสุดท้าย)
  let nextCursor = null;
  if (snap.size === lim && snap.docs.length > 0) {
    const last = snap.docs[snap.docs.length - 1];
    const lc = last.data()?.createdAt;
    if (lc && typeof lc.toMillis === 'function') {
      nextCursor = lc.toMillis();
    }
  }
  return { bookings: items, nextCursor };
});

// เจ้าของ: อนุมัติ/ปฏิเสธการจอง
// data: { bookingId: string, approve: boolean, reason?: string }
exports.decideBooking = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบ');
  const ownerUid = request.auth.uid;
  const { bookingId, approve, reason } = request.data || {};
  if (!bookingId || typeof approve !== 'boolean') {
    throw new HttpsError('invalid-argument', 'ต้องระบุ bookingId และ approve');
  }
  const db = admin.firestore();
  const ref = db.collection('user_bookings').doc(String(bookingId));
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'ไม่พบบุ๊กกิ้ง');
  const v = snap.data() || {};
  if (v.ownerId !== ownerUid) throw new HttpsError('permission-denied', 'ไม่ใช่เจ้าของบุ๊กกิ้งนี้');
  if (v.status !== 'pending') throw new HttpsError('failed-precondition', 'สถานะไม่ใช่ pending');

  //ตรวจชนกันแบบเต็มวัน: slot เดียวกัน วันที่เดียวกัน ที่อนุมัติแล้ว
  if (approve) {
    const slotId = v.slotId;
    const bookingDate = v.bookingDate; // Timestamp
    if (slotId && bookingDate) {
      const qs = await db.collection('user_bookings')
        .where('slotId', '==', slotId)
        .where('status', '==', 'approved')
        .where('bookingDate', '==', bookingDate)
        .limit(1)
        .get();
      if (!qs.empty) {
        throw new HttpsError('failed-precondition', 'มีการอนุมัติซ้ำวันสำหรับช่องนี้แล้ว');
      }
    }
  }

  const FieldValue = admin.firestore.FieldValue;
  if (approve) {
    await ref.set({
      status: 'approved',
      approvedAt: FieldValue.serverTimestamp(),
      decidedBy: { uid: ownerUid, email: request.auth.token?.email || null },
      decisionNote: reason || null,
    }, { merge: true });
    return { ok: true, status: 'approved' };
  } else {
    await ref.set({
      status: 'rejected',
      rejectedAt: FieldValue.serverTimestamp(),
      decidedBy: { uid: ownerUid, email: request.auth.token?.email || null },
      decisionNote: reason || null,
    }, { merge: true });
    return { ok: true, status: 'rejected' };
  }
});

// งานตามเวลา: หมดอายุคำขอที่ค้างนานเกินกำหนด
exports.expireStaleBookings = onSchedule("every 30 minutes", async () => {
  const db = admin.firestore();
  const cutoff = new Date(Date.now() - 60 * 60 * 1000); // 60 นาทีที่ผ่านมา
  const qs = await db.collection('user_bookings')
    .where('status', '==', 'pending')
    .where('createdAt', '<=', admin.firestore.Timestamp.fromDate(cutoff))
    .limit(500)
    .get();
  const FieldValue = admin.firestore.FieldValue;
  for (const d of qs.docs) {
    try {
      await d.ref.set({ status: 'expired', expiredAt: FieldValue.serverTimestamp() }, { merge: true });
    } catch (_) {}
  }
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

// ฝั่งแอดมิน: ลบที่จอด (เอกสาร) พร้อม subcollection ทั้งหมดแบบ recursive
// data: { slotId: string }
exports.deleteParkingSlot = onCall(async (request) => {
  assertAdmin(request);
  const slotId = request.data?.slotId;
  if (!slotId || typeof slotId !== 'string') {
    throw new HttpsError('invalid-argument', 'ต้องระบุ slotId เป็นสตริง');
  }

  const db = admin.firestore();
  const rootRef = db.collection('parking_slots').doc(slotId);

  // ส่วนตัวช่วยลบแบบ recursive (เดินลบลูกทั้งหมดก่อน แล้วค่อยลบตัวเอง)
  async function deleteRecursively(ref) {
    const subcols = await ref.listCollections();
    for (const col of subcols) {
      const snap = await col.get();
      for (const doc of snap.docs) {
        await deleteRecursively(doc.ref);
        await doc.ref.delete();
      }
    }
  }

  try {
    // ลบรูปที่ผูกอยู่กับเอกสารนี้ (ถ้ามี)
    const snap = await rootRef.get();
    if (snap.exists) {
      const data = snap.data() || {};
      await deleteImagesForDocData(data);
    }

    // ลบลูกทั้งหมด
    await deleteRecursively(rootRef);
    // ลบตัวเอกสารแม่ (ไม่ว่าจะมีอยู่จริงหรือไม่ การลบจะผ่านได้)
    await rootRef.delete().catch(() => {});

    await logAdminAction('deleteParkingSlot', request, { slotId });
    // ลบ bookings ที่อ้างอิง slotId นี้ออกด้วย
    try {
      const qs = await db.collection('user_bookings').where('slotId', '==', slotId).limit(500).get();
      for (const b of qs.docs) {
        await b.ref.delete();
      }
      await logAdminAction('deleteParkingSlot.cascadeBookings', request, { slotId, deleted: qs.size });
    } catch (e) {
      await logAdminAction('deleteParkingSlot.cascadeBookings.error', request, { slotId, error: String(e) });
    }
    return { ok: true, slotId };
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

// รวมคะแนนรีวิวลงในเอกสารแม่ parking_slots
// เก็บค่า: rating_sum, rating_count, rating_avg เพื่อให้แอปอ่านได้เร็วและไม่ต้องเปิดสตรีมย่อย
// Firestore trigger v2: ใช้รูปแบบ 'documents/<path>'
exports.aggregateSlotRatings = onDocumentWritten(
  "documents/parking_slots/{slotId}/reviews/{reviewId}",
  async (event) => {
    try {
      const before = event.data?.before?.data() || null;
      const after = event.data?.after?.data() || null;
      const slotId = event.params.slotId;
      if (!slotId) return;

      const db = admin.firestore();
      const slotRef = db.collection('parking_slots').doc(String(slotId));
      const snap = await slotRef.get();
      const cur = snap.exists ? (snap.data() || {}) : {};
      let sum = Number(cur.rating_sum || 0);
      let count = Number(cur.rating_count || 0);

      const oldRating = before && typeof before.rating === 'number' ? Number(before.rating) : null;
      const newRating = after && typeof after.rating === 'number' ? Number(after.rating) : null;

      // กรณีสร้างใหม่
      if (oldRating == null && newRating != null) {
        sum += newRating;
        count += 1;
      }
      // กรณีอัปเดตค่า
      else if (oldRating != null && newRating != null) {
        sum += (newRating - oldRating);
      }
      // กรณีลบออก
      else if (oldRating != null && newRating == null) {
        sum -= oldRating;
        count -= 1;
      }

      if (count < 0) count = 0;
      if (sum < 0) sum = 0;
      const avg = count > 0 ? sum / count : 0;

      await slotRef.set({
        rating_sum: sum,
        rating_count: count,
        rating_avg: avg,
      }, { merge: true });
    } catch (e) {
      console.error('aggregateSlotRatings error', e);
    }
  }
);

// ลบการจองทุกอันที่อ้างอิง slot ที่ถูกลบ (กันกรณีลบเอกสารด้วยวิธีอื่น)
const { onDocumentDeleted } = require("firebase-functions/v2/firestore");
exports.cascadeDeleteBookingsOnSlotDelete = onDocumentDeleted(
  "documents/parking_slots/{slotId}",
  async (event) => {
    const slotId = String(event.params.slotId);
    try {
      const db = admin.firestore();
      const qs = await db.collection('user_bookings').where('slotId', '==', slotId).limit(1000).get();
      for (const d of qs.docs) {
        await d.ref.delete();
      }
      await logAdminAction('slotDeleted.cascadeBookings', null, { slotId, deleted: qs.size });
    } catch (e) {
      await logAdminAction('slotDeleted.cascadeBookings.error', null, { slotId, error: String(e) });
    }
  }
);

// เรียกแบบแอดมิน: คำนวณค่า rating_sum/rating_count/rating_avg ใหม่ให้ทุก slot (backfill)
exports.backfillSlotRatings = onCall(async (request) => {
  assertAdmin(request);
  const db = admin.firestore();
  const slots = await db.collection('parking_slots').limit(1000).get();
  for (const doc of slots.docs) {
    try {
      const reviews = await doc.ref.collection('reviews').get();
      let sum = 0; let count = 0;
      for (const r of reviews.docs) {
        const val = r.data()?.rating;
        if (typeof val === 'number') { sum += Number(val); count += 1; }
      }
      const avg = count > 0 ? sum / count : 0;
      await doc.ref.set({ rating_sum: sum, rating_count: count, rating_avg: avg }, { merge: true });
    } catch (e) {
      console.error('backfillSlotRatings for', doc.id, e);
    }
  }
  return { ok: true, updated: slots.size };
});

// ล้างรายการจองที่ชี้ไปยัง slot ที่ไม่มีอยู่แล้ว (admin เท่านั้น)
exports.cleanupOrphanBookings = onCall(async (request) => {
  assertAdmin(request);
  const db = admin.firestore();
  const qs = await db.collection('user_bookings').limit(500).get();
  let deleted = 0;
  for (const b of qs.docs) {
    try {
      const v = b.data() || {};
      const slotId = v.slotId;
      if (!slotId) continue;
      const snap = await db.collection('parking_slots').doc(String(slotId)).get();
      if (!snap.exists) {
        await b.ref.delete();
        deleted++;
      }
    } catch (_) {}
  }
  await logAdminAction('cleanupOrphanBookings', request, { deleted });
  return { ok: true, deleted };
});
