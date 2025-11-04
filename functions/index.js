"use strict";

const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const Stripe = require("stripe");
let legacyConfig = {};
try { legacyConfig = require("firebase-functions").config(); } catch (_) { legacyConfig = {}; }

// Secrets (recommended for Gen2)
const STRIPE_SECRET = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");

try {
  admin.app();
} catch (_) {
  admin.initializeApp();
}

// Gen2: set global defaults
setGlobalOptions({ region: "us-central1" });

/**
 * Helper: ensure caller is an admin (v2 request)
 */
function assertAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ต้องเข้าสู่ระบบก่อน");
  }
  const claims = request.auth.token || {};
  if (!claims.isAdmin) {
    throw new HttpsError("permission-denied", "ต้องเป็นผู้ดูแลระบบเท่านั้น");
  }
}

/**
 * Helper: write admin audit log
 */
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
    // do not block main flow if logging fails
  }
}

/**
 * List users with pagination.
 * data: { pageToken?: string, maxResults?: number }
 */
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

/**
 * List users and enrich with Firestore host fields.
 * data: { pageToken?: string, maxResults?: number }
 */
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

  // Fetch Firestore docs in batch
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

/**
 * Set or remove admin role.
 * data: { uid: string, isAdmin: boolean }
 */
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

/**
 * Enable/Disable user account
 * data: { uid: string, disabled: boolean }
 */
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

/**
 * Bootstrap: allow the first admin to grant themselves admin if no admin exists.
 */
exports.grantSelfAdminIfNone = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ต้องเข้าสู่ระบบก่อน");
  }
  // Check if any current admin exists
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

/**
 * Set a temporary password for a user (admin only).
 * data: { uid: string, password: string }
 */
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

/**
 * User requests host permission to publish parking listings.
 * Creates/updates users/{uid} with hostStatus='requested'.
 */
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
  // For convenience store email/name for admin view
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

/**
 * Admin: list host requests (users with hostStatus='requested')
 * data: { limit?: number }
 */
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

/**
 * Admin: approve or reject a host request.
 * data: { uid: string, approve: boolean, note?: string }
 */
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
    // revoke claim if existed
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

  /**
   * Admin: directly set or revoke user's host permission.
   * data: { uid: string, canHost: boolean, note?: string }
   */
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

/**
 * Admin: extend host permission to now + 5 minutes (resets window)
 * data: { uid: string, minutes?: number }
 */
exports.extendHostPermission = onCall(async (request) => {
  assertAdmin(request);
  const uid = request.data?.uid;
  const minutes = Number(request.data?.minutes || 5);
  if (!uid) throw new HttpsError("invalid-argument", "ต้องระบุ uid");

  const db = admin.firestore();
  const ref = db.collection("users").doc(uid);
  const newUntil = new Date(Date.now() + minutes * 60 * 1000);

  // Ensure claim true
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

// -------------------- Stripe based host registration --------------------

function getStripe() {
  // Prefer Secret Manager, then various env/config fallbacks
  const key =
    STRIPE_SECRET.value() ||
    process.env.STRIPE_SECRET ||
    process.env.STRIPE_SECRET_KEY ||
    process.env.stripe_secret ||
    legacyConfig?.stripe?.secret;
  if (!key) return null;
  // Use account's default API version to avoid mismatch issues
  return new Stripe(key);
}

/**
 * Create a Stripe Checkout session for host registration (THB 1.00)
 * Returns { url }
 */
exports.createHostRegistration = onCall({ secrets: [STRIPE_SECRET] }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "ต้องเข้าสู่ระบบก่อน");
  const stripe = getStripe();
  if (!stripe) throw new HttpsError("failed-precondition", "ยังไม่ตั้งค่า stripe.secret (STRIPE_SECRET) บน Functions env");

  const uid = request.auth.uid;
  const db = admin.firestore();
  const FieldValue = admin.firestore.FieldValue;
  const ref = db.collection("users").doc(uid);

  // Create Checkout Session
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

/**
 * Stripe webhook: Activate host after successful payment, set 5-minute window.
 */
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

      const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // now + 5 minutes
      // set claim and status
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

// -------------------- Helpers: Storage cleanup --------------------
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
  // Works for https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?...
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
    } catch (_) { /* continue */ }
  }
}

/**
 * Scheduled job: revoke expired host permissions every minute.
 */
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

    // Also remove all listings for this user and their images
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
      // mark as purged to skip repeated work later
      await doc.ref.set({ listingsPurged: true }, { merge: true });
    } catch (e) {
      await logAdminAction('auto.deleteListingOnExpiry.error', null, { uid, error: String(e) });
    }
  }

  // Also backfill: users already 'expired' but not yet purged
  const qsExpired = await db
    .collection('users')
    .where('hostStatus', '==', 'expired')
    .where('hostActiveUntil', '<=', admin.firestore.Timestamp.fromDate(now))
    .limit(300)
    .get();
  for (const doc of qsExpired.docs) {
    const uid = doc.id;
    const v = doc.data() || {};
    if (v.listingsPurged === true) continue; // already done
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

// Debug endpoint: show presence (not values) of Stripe env/config for troubleshooting
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
