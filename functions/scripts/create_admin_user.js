"use strict";

const admin = require("firebase-admin");
const readline = require("readline");

const projectId = process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "aqssite-6aa5c";
const email = process.env.ADMIN_EMAIL || "admin@aqsauto.com";

function readPassword() {
  if (process.env.ADMIN_PASSWORD) return Promise.resolve(process.env.ADMIN_PASSWORD);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false,
  });

  return new Promise((resolve) => {
    rl.question("Admin password: ", (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

async function main() {
  const password = await readPassword();
  if (!password || password.length < 8) {
    throw new Error("Admin password must be at least 8 characters.");
  }

  admin.initializeApp({projectId});
  const auth = admin.auth();
  const db = admin.firestore();

  let user;
  try {
    user = await auth.getUserByEmail(email);
    user = await auth.updateUser(user.uid, {
      password,
      emailVerified: true,
      disabled: false,
      displayName: "AQS Admin",
    });
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    user = await auth.createUser({
      email,
      password,
      emailVerified: true,
      disabled: false,
      displayName: "AQS Admin",
    });
  }

  const existingClaims = user.customClaims || {};
  await auth.setCustomUserClaims(user.uid, {
    ...existingClaims,
    admin: true,
    role: "admin",
  });

  await db.collection("users").doc(user.uid).set({
    uid: user.uid,
    name: "AQS Admin",
    email,
    role: "admin",
    status: "active",
    provider: "password",
    adminClaim: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  const profileRef = db.collection("users").doc(user.uid);
  const profileSnap = await profileRef.get();
  if (!profileSnap.exists || !profileSnap.data().createdAt) {
    await profileRef.set({
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  console.log(`Admin user ready: ${email}`);
  console.log(`UID: ${user.uid}`);
  console.log("Custom claims set: admin=true, role=admin");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
