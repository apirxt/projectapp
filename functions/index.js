"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

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
