// functions/index.js (CommonJS, Gen2)

const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {
  onDocumentWritten,
  onDocumentWrittenWithAuthContext,
} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const {FieldValue} = require("firebase-admin/firestore");
const path = require("path");
const os = require("os");
const fs = require("fs").promises;

const {
  initializeApp,
} = require(
    "firebase-admin/app",
);

// admin.initializeApp();
initializeApp();

const db = admin.firestore();
const storage = admin.storage();

const {
  initiateAqsPayment,
} = require("./src/functions/initiate-aqs-payment");
const {
  receiveQuickLipaWebhook,
} = require(
    "./src/functions/receive-quicklipa-webhook",
);
const {
  analyseSlabRebarMarks,
} = require("./src/functions/analyse-slab-rebar-marks");
const {
  extractExternalQuotationItems,
} = require("./src/functions/extract-external-quotation-items");

exports.initiateAqsPayment =
    initiateAqsPayment;
exports.receiveQuickLipaWebhook =
    receiveQuickLipaWebhook;
exports.analyseSlabRebarMarks = analyseSlabRebarMarks;
exports.extractExternalQuotationItems = extractExternalQuotationItems;

/**
 * Convert first page of a PDF file to PNG.
 *
 * @param {string} pdfPath - Local filesystem path to the source PDF file.
 * @param {string} pngPath - Local filesystem path where the PNG should be written.
 * @return {Promise<void>} A promise that resolves when conversion is complete.
 */
const MEAS_PATH =
  "projects/{projectId}/buildings/{buildingId}/measurements/{docId}";

function asStr(v) {
  return (v === null || v === undefined) ? "" : String(v);
}
function asNum(v) {
  if (typeof v === "number") return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}
function makeSumKey(projectId, buildingId, boqCode, unit) {
  return `${projectId}|${buildingId}|${boqCode}|${unit}`;
}

function snapData(snap) {
  return snap && snap.exists ? (snap.data() || {}) : null;
}

function changeAction(before, after) {
  if (!before && after) return "added";
  if (before && !after) return "deleted";
  return "edited";
}

function changedFields(before, after) {
  const keys = new Set([
    ...Object.keys(before || {}),
    ...Object.keys(after || {}),
  ]);
  const ignored = new Set(["updatedAt", "takeoffUpdatedAt"]);
  return Array.from(keys)
      .filter((key) => !ignored.has(key))
      .filter((key) => {
        return JSON.stringify((before || {})[key]) !==
          JSON.stringify((after || {})[key]);
      })
      .slice(0, 20);
}

function bestLabel(data, keys, fallback) {
  for (const key of keys) {
    const value = asStr(data && data[key]).trim();
    if (value) return value;
  }
  return fallback;
}

function quantityLabel(data) {
  const value = data && data.value;
  const unit = asStr(data && data.unit).trim();
  if (value === undefined || value === null || value === "") return "";
  return `${asNum(value).toFixed(3)}${unit ? ` ${unit}` : ""}`;
}

function shouldSkipUserActivity(event) {
  return !event.authId ||
    event.authType === "service_account" ||
    event.authType === "system" ||
    event.authType === "unauthenticated";
}

async function actorInfo(event) {
  const uid = asStr(event.authId);
  if (!uid) {
    return {
      uid: "",
      name: "Unknown user",
      email: "",
      authType: asStr(event.authType),
    };
  }

  try {
    const userSnap = await db.collection("users").doc(uid).get();
    const user = userSnap.exists ? (userSnap.data() || {}) : {};
    const email = asStr(user.email).trim();
    const name = bestLabel(user, ["name", "displayName"], "");
    return {
      uid,
      name: name || (email ? email.split("@")[0] : uid),
      email,
      authType: asStr(event.authType),
    };
  } catch (e) {
    logger.warn("Could not load activity actor profile", {uid, error: e.message});
    return {
      uid,
      name: uid,
      email: "",
      authType: asStr(event.authType),
    };
  }
}

async function projectContext(projectId, fallbackData) {
  let data = fallbackData || null;
  if (!data || (!data.ownerId && !data.name)) {
    const projectSnap = await db.collection("projects").doc(projectId).get();
    if (projectSnap.exists) data = projectSnap.data() || {};
  }
  if (!data) return null;
  return {
    ownerId: asStr(data.ownerId),
    projectName: bestLabel(data, ["name", "projectName"], "Project"),
  };
}

async function buildingContext(projectId, buildingId) {
  if (!buildingId) return {buildingName: ""};
  try {
    const buildingSnap = await db
        .collection("projects").doc(projectId)
        .collection("buildings").doc(buildingId)
        .get();
    const data = buildingSnap.exists ? (buildingSnap.data() || {}) : {};
    return {
      buildingName: bestLabel(data, ["name", "code"], "Building"),
    };
  } catch (e) {
    logger.warn("Could not load activity building context", {
      projectId,
      buildingId,
      error: e.message,
    });
    return {buildingName: "Building"};
  }
}

function actionTitle(action, resourceType) {
  const resource = resourceType
      .split("_")
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join(" ");
  return `${action.charAt(0).toUpperCase() + action.slice(1)} ${resource}`;
}

function actorRole(actor, context) {
  if (!actor.uid || !context.ownerId) return "user";
  return actor.uid === context.ownerId ? "owner" : "member";
}

async function writeProjectActivity(event, options) {
  if (shouldSkipUserActivity(event)) return;

  const {
    projectId,
    buildingId = "",
    resourceId,
    resourceType,
    action,
    resourceLabel,
    details = {},
    fallbackProjectData = null,
  } = options;

  const context = await projectContext(projectId, fallbackProjectData);
  if (!context || !context.ownerId) return;

  const actor = await actorInfo(event);
  const building = await buildingContext(projectId, buildingId);
  const place = building.buildingName ? ` in ${building.buildingName}` : "";
  const label = resourceLabel ? ` "${resourceLabel}"` : "";
  const title = actionTitle(action, resourceType);
  const message = `${actor.name} ${action} ${resourceType.replace(/_/g, " ")}${label}${place}.`;

  await db.collection("projects").doc(projectId).collection("activityLogs").add({
    action,
    title,
    message,
    resourceType,
    resourceId: asStr(resourceId),
    resourceLabel: asStr(resourceLabel),
    projectId,
    projectName: context.projectName,
    ownerId: context.ownerId,
    actorId: actor.uid,
    actorName: actor.name,
    actorEmail: actor.email,
    actorRole: actorRole(actor, context),
    authType: actor.authType,
    buildingId: asStr(buildingId),
    buildingName: building.buildingName,
    details,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function measurementLabel(data) {
  return bestLabel(data, [
    "label",
    "memberTypeLabel",
    "boqDescription",
    "measureType",
    "type",
  ], "measurement");
}

function boqLabel(data) {
  const code = bestLabel(data, [
    "resolvedBoqCode",
    "displayCode",
    "boqCode",
    "itemCode",
    "code",
  ], "");
  const desc = bestLabel(data, [
    "description",
    "boqDescription",
    "itemDescription",
  ], "");
  if (code && desc) return `${code} ${desc}`;
  return code || desc || "BOQ item";
}

function drawingLabel(data) {
  return bestLabel(data, [
    "title",
    "name",
    "drawingTitle",
    "fileName",
    "pdfName",
  ], "drawing");
}

exports.logProjectDocumentActivity = onDocumentWrittenWithAuthContext(
    {document: "projects/{projectId}", region: "us-central1"},
    async (event) => {
      const before = snapData(event.data && event.data.before);
      const after = snapData(event.data && event.data.after);
      if (!before && !after) return;

      const action = changeAction(before, after);
      if (action === "deleted") return;

      const fields = changedFields(before, after);
      await writeProjectActivity(event, {
        projectId: event.params.projectId,
        resourceId: event.params.projectId,
        resourceType: "project",
        action,
        resourceLabel: bestLabel(after || before, ["name", "projectName"], "Project"),
        fallbackProjectData: after || before,
        details: {changedFields: fields},
      });
    },
);

exports.logBuildingActivity = onDocumentWrittenWithAuthContext(
    {
      document: "projects/{projectId}/buildings/{buildingId}",
      region: "us-central1",
    },
    async (event) => {
      const before = snapData(event.data && event.data.before);
      const after = snapData(event.data && event.data.after);
      if (!before && !after) return;

      const action = changeAction(before, after);
      const data = after || before;
      await writeProjectActivity(event, {
        projectId: event.params.projectId,
        buildingId: event.params.buildingId,
        resourceId: event.params.buildingId,
        resourceType: "building",
        action,
        resourceLabel: bestLabel(data, ["name", "code"], "Building"),
        details: {changedFields: changedFields(before, after)},
      });
    },
);

exports.logDrawingActivity = onDocumentWrittenWithAuthContext(
    {
      document: "projects/{projectId}/buildings/{buildingId}/drawings/{drawingId}",
      region: "us-central1",
    },
    async (event) => {
      const before = snapData(event.data && event.data.before);
      const after = snapData(event.data && event.data.after);
      if (!before && !after) return;

      const action = changeAction(before, after);
      const data = after || before;
      await writeProjectActivity(event, {
        projectId: event.params.projectId,
        buildingId: event.params.buildingId,
        resourceId: event.params.drawingId,
        resourceType: "drawing",
        action,
        resourceLabel: drawingLabel(data),
        details: {
          status: asStr(data.processingStatus),
          changedFields: changedFields(before, after),
        },
      });
    },
);

exports.logBoqActivity = onDocumentWrittenWithAuthContext(
    {
      document: "projects/{projectId}/buildings/{buildingId}/boq/{boqId}",
      region: "us-central1",
    },
    async (event) => {
      const before = snapData(event.data && event.data.before);
      const after = snapData(event.data && event.data.after);
      if (!before && !after) return;

      const action = changeAction(before, after);
      const data = after || before;
      await writeProjectActivity(event, {
        projectId: event.params.projectId,
        buildingId: event.params.buildingId,
        resourceId: event.params.boqId,
        resourceType: "boq_item",
        action,
        resourceLabel: boqLabel(data),
        details: {
          unit: asStr(data.unit),
          changedFields: changedFields(before, after),
        },
      });
    },
);

exports.logBoqItemsActivity = onDocumentWrittenWithAuthContext(
    {
      document: "projects/{projectId}/buildings/{buildingId}/boqItems/{boqId}",
      region: "us-central1",
    },
    async (event) => {
      const before = snapData(event.data && event.data.before);
      const after = snapData(event.data && event.data.after);
      if (!before && !after) return;

      const action = changeAction(before, after);
      const data = after || before;
      await writeProjectActivity(event, {
        projectId: event.params.projectId,
        buildingId: event.params.buildingId,
        resourceId: event.params.boqId,
        resourceType: "boq_item",
        action,
        resourceLabel: boqLabel(data),
        details: {
          unit: asStr(data.unit),
          changedFields: changedFields(before, after),
        },
      });
    },
);

exports.logMeasurementActivity = onDocumentWrittenWithAuthContext(
    {document: MEAS_PATH, region: "us-central1"},
    async (event) => {
      const before = snapData(event.data && event.data.before);
      const after = snapData(event.data && event.data.after);
      if (!before && !after) return;

      const data = after || before;
      if (data.isDerived === true) return;

      const action = changeAction(before, after);
      if (after && !shouldSkipUserActivity(event)) {
        const actor = await actorInfo(event);
        const actorPatch = {
          lastActorUid: actor.uid,
          lastActorName: actor.name,
          lastActorEmail: actor.email,
          lastActorAt: FieldValue.serverTimestamp(),
        };
        if (action === "added") {
          actorPatch.createdByUid = actor.uid;
          actorPatch.createdByName = actor.name;
          actorPatch.createdByEmail = actor.email;
        } else {
          actorPatch.updatedByUid = actor.uid;
          actorPatch.updatedByName = actor.name;
          actorPatch.updatedByEmail = actor.email;
        }
        await event.data.after.ref.update(actorPatch);
      }

      await writeProjectActivity(event, {
        projectId: event.params.projectId,
        buildingId: event.params.buildingId,
        resourceId: event.params.docId,
        resourceType: "measurement",
        action,
        resourceLabel: measurementLabel(data),
        details: {
          boqCode: asStr(data.boqCode || data.resolvedBoqCode),
          quantity: quantityLabel(data),
          unit: asStr(data.unit),
          changedFields: changedFields(before, after),
        },
      });
    },
);

exports.logTeamInviteActivity = onDocumentWrittenWithAuthContext(
    {document: "teamInvites/{inviteId}", region: "us-central1"},
    async (event) => {
      const before = snapData(event.data && event.data.before);
      const after = snapData(event.data && event.data.after);
      if (!before && !after) return;

      const beforeStatus = asStr(before && before.status).toLowerCase();
      const afterStatus = asStr(after && after.status).toLowerCase();
      const data = after || before;
      const projectIds = ((data.projectIds || []) || [])
          .map((id) => asStr(id))
          .filter((id) => id);
      const projectNames = ((data.projectNames || []) || [])
          .map((projectName) => asStr(projectName));
      if (!projectIds.length) return;

      let action = changeAction(before, after);
      if (!before && after) {
        action = afterStatus === "accepted" ? "added" : "invited";
      } else if (before && after && beforeStatus !== afterStatus) {
        action = afterStatus === "accepted" ? "accepted" : afterStatus || "edited";
      }

      const inviteLabel = bestLabel(data, ["name", "email"], "team member");
      await Promise.all(projectIds.map((projectId, index) => {
        return writeProjectActivity(event, {
          projectId,
          resourceId: event.params.inviteId,
          resourceType: "team_member",
          action,
          resourceLabel: inviteLabel,
          details: {
            email: asStr(data.email),
            role: asStr(data.role),
            status: afterStatus || beforeStatus,
            projectName: projectNames[index] || "",
          },
        });
      }));
    },
);

async function listAllDocs(query, pageSize = 450) {
  let last = null;
  let done = false;
  const out = [];

  while (!done) {
    let q = query.orderBy("__name__").limit(pageSize);
    if (last) q = q.startAfter(last);

    const snap = await q.get();
    if (snap.empty) break;

    out.push(...snap.docs);
    last = snap.docs[snap.docs.length - 1];

    if (snap.size < pageSize) done = true;
  }
  return out;
}

async function recomputeBoqSum(measurementsCol, boqCode, unit) {
  // ⚠️ Firestore can’t do "isDerived != true" so we filter in memory
  const q = measurementsCol
      .where("boqCode", "==", boqCode)
      .where("unit", "==", unit);

  const docs = await listAllDocs(q, 450);

  let sum = 0;
  for (const d of docs) {
    const m = d.data() || {};
    if (m.isDerived === true) continue;
    sum += asNum(m.value);
  }
  return sum;
}

async function updateDerivedDocs(measurementsCol, docs, computeValueFn) {
  // batched updates (<= 450 safe)
  const chunkSize = 400;
  for (let i = 0; i < docs.length; i += chunkSize) {
    const batch = db.batch();
    const slice = docs.slice(i, i + chunkSize);

    for (const d of slice) {
      const m = d.data() || {};
      const factor = asNum(m.factor || 1);
      const offset = asNum(m.offset || 0);
      const newValue = computeValueFn(factor, offset);

      batch.update(d.ref, {
        value: newValue,
        sourceValue: computeValueFn(1, 0), // store raw source (no factor/offset)
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }
}

async function convertPdfFirstPageToPng(pdfFilePath) {
  // Heavy native/PDF modules are intentionally loaded lazily.
  // Firebase CLI loads index.js during deploy to discover function specs,
  // so top-level canvas/pdfjs imports can exceed the 10s discovery timeout.
  const canvasModule = require("canvas");
  const {createCanvas} = canvasModule;
  if (typeof global.DOMMatrix === "undefined" && canvasModule.DOMMatrix) {
    global.DOMMatrix = canvasModule.DOMMatrix;
  }
  const pdfjsLib = require("pdfjs-dist/legacy/build/pdf.js");

  const buffer = await fs.readFile(pdfFilePath);
  const data = new Uint8Array(buffer);
  const loadingTask = pdfjsLib.getDocument({data});

  const pdf = await loadingTask.promise;
  const page = await pdf.getPage(1); // first page only

  const scale = 3.5; // adjust if you want higher/lower resolution
  const viewport = page.getViewport({scale});

  const canvas = createCanvas(viewport.width, viewport.height);
  const context = canvas.getContext("2d");

  // pdfjs canvasFactory for node-canvas
  const canvasFactory = {
    create: (width, height) => {
      const c = createCanvas(width, height);
      return {
        canvas: c,
        context: c.getContext("2d"),
      };
    },
    reset: (canvasAndContext, width, height) => {
      canvasAndContext.canvas.width = width;
      canvasAndContext.canvas.height = height;
    },
    destroy: (canvasAndContext) => {
      canvasAndContext.canvas.width = 0;
      canvasAndContext.canvas.height = 0;
    },
  };

  await page.render({
    canvasContext: context,
    viewport,
    canvasFactory,
  }).promise;

  return canvas.toBuffer("image/png");
  // return pngBuffer;
}


exports.onDrawingPdfUploaded = onObjectFinalized(
    {
      bucket: "aqssite-6aa5c.firebasestorage.app",
      region: "us-central1", // change to your region
      memory: "1GiB",
      timeoutSeconds: 540,
    },
    async (event) => {
      const object = event.data;
      const contentType = object.contentType || "";
      const filePath = object.name || "";
      // const bucketName = object.bucket;

      console.log("onDrawingPdfUploaded triggered for", filePath, "ct:", contentType);

      // Only process PDFs
      if (!contentType.startsWith("application/pdf")) {
        console.log("Not a PDF, skipping:", filePath);
        return;
      }

      // Only paths like: projects/{projectId}/drawings/{fileName}.pdf
      if (!filePath.startsWith("projects/") || !filePath.endsWith(".pdf")) {
        console.log("Not a drawing path, skipping:", filePath);
        return;
      }
      const bucket = storage.bucket(object.bucket);
      const pdfFile = bucket.file(filePath);

      const pdfFileName = path.basename(filePath); // inala first floor.pdf
      const pngFileName =
        pdfFileName.replace(/\.pdf$/i, ".png") || (pdfFileName + ".png");
      const pngStoragePath = path.join(path.dirname(filePath), pngFileName);

      // 1) Download PDF to temp
      const tempPdfPath = path.join(os.tmpdir(), pdfFileName);
      const tempPngPath = path.join(os.tmpdir(), pngFileName);

      // find drawing doc
      const parts = filePath.split("/");
      if (parts.length !== 6 || parts[2] !== "buildings" || parts[4] !== "drawings") {
        console.warn("Unexpected drawing path structure:", filePath, parts);
        return;
      }
      const projectId = parts[1];
      const buildingId = parts[3];
      const fileName = parts[5];
      const drawingId = fileName.replace(/\.pdf$/, "");

      const drawingRef = db
          .collection("projects")
          .doc(projectId)
          .collection("buildings")
          .doc(buildingId)
          .collection("drawings")
          .doc(drawingId);

      const drawingSnap = await drawingRef.get();

      //   const snap = await drawingsRef.where("filePath", "==", filePath).limit(1).get();
      if (!drawingSnap.exists) {
        console.warn("No drawing doc found at", drawingRef.path, "for filePath", filePath);
        return;
      }
      const drawingDocRef = drawingRef;
      const drawingData = drawingSnap.data() || {};
      if (
        drawingData.clientRenderedImage === true ||
        drawingData.packageUpload === true ||
        Number(drawingData.sourcePageNumber || 1) > 1
      ) {
        console.log(
            "Drawing already has a client-rendered selected-page image; skipping first-page converter:",
            drawingRef.path,
        );
        return;
      }

      // 🔹 set status = processing
      await drawingDocRef.update({
        processingStatus: "processing",
        processingError: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      try {
        // 1) download pdf
        console.log("Downloading PDF to", tempPdfPath);
        await pdfFile.download({destination: tempPdfPath});

        // 2) convert to PNG
        console.log("Converting first page to PNG...");
        const pngBuffer = await convertPdfFirstPageToPng(tempPdfPath);

        // 3) upload PNG
        await fs.writeFile(tempPngPath, pngBuffer);
        console.log("Uploading PNG to", pngStoragePath);
        await bucket.upload(tempPngPath, {
          destination: pngStoragePath,
          contentType: "image/png",
        });

        await drawingDocRef.update({
          imagePath: pngStoragePath, // e.g. "projects/.../drawings/file.png"
          // imageUrl: will be resolved on the client
          processingStatus: "ready",
          updatedAt: FieldValue.serverTimestamp(),
        });

        console.log("Done processing PDF → PNG for", filePath);
      } catch (err) {
        console.error("Error converting drawing:", err);

        // 🔴 set status = error + message
        const msg = (err && err.message ? err.message : String(err)).slice(0, 500);
        await drawingDocRef.update({
          processingStatus: "error",
          processingError: msg,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } finally {
        // cleanup temp files
        try {
          await fs.unlink(tempPdfPath);
        } catch (e) {
          console.error("Error tempPdfPath:", e);
        }
        try {
          await fs.unlink(tempPngPath);
        } catch (e) {
          console.error("Error tempPngPath:", e);
        }
      }
    },
);

exports.syncBoqTotals = onDocumentWritten(
    "projects/{projectId}/buildings/{buildingId}/measurements/{mid}",
    async (event) => {
      const projectId = event.params.projectId;
      const buildingId = event.params.buildingId;

      const db = admin.firestore();

      // v2 event gives you before/after snapshots:
      const beforeSnap = event.data && event.data.before;
      const afterSnap = event.data && event.data.after;

      const before = (beforeSnap && beforeSnap.exists) ? beforeSnap.data() : null;
      const after = (afterSnap && afterSnap.exists) ? afterSnap.data() : null;

      const beforeBoqId = before && before.boqItemId ? String(before.boqItemId) : null;
      const afterBoqId = after && after.boqItemId ? String(after.boqItemId) : null;

      // Only sync when measurement is linked to BOQ
      if (!beforeBoqId && !afterBoqId) return;

      const num = (v) => {
        if (typeof v === "number") return v;
        const n = parseFloat(String(v || "0"));
        return Number.isFinite(n) ? n : 0;
      };

      const normalizeUnit = (u) => {
        const x = String(u || "").trim().toLowerCase();
        if (!x) return "unknown";
        if (x === "m2" || x === "m²" || x.indexOf("square") >= 0) return "m2";
        if (x === "m3" || x === "m³" || x.indexOf("cubic") >= 0) return "m3";
        if (x === "m" || x.indexOf("meter") >= 0) return "m";
        if (x.indexOf("kg") >= 0) return "kg";
        if (x.indexOf("ton") >= 0) return "tonne";
        if (x.indexOf("item") >= 0 || x.indexOf("no") >= 0) return "item";
        return x.replace(/\s+/g, "");
      };

      const beforeVal = num(before && before.value);
      const afterVal = num(after && after.value);

      const beforeUnit = normalizeUnit(before && before.unit);
      const afterUnit = normalizeUnit(after && after.unit);

      const boqDoc = (boqId) =>
        db.collection("projects").doc(projectId)
            .collection("buildings").doc(buildingId)
            .collection("boq").doc(boqId);

      const incUnit = (unitKey, delta) => {
        const out = {};
        out["takeoffQtyByUnit." + unitKey] = admin.firestore.FieldValue.increment(delta);
        out.takeoffUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
        return out;
      };

      try {
        await db.runTransaction(async (tx) => {
          // DELETE (was linked, now unlinked)
          if (beforeBoqId && !afterBoqId) {
            tx.set(boqDoc(beforeBoqId), incUnit(beforeUnit, -beforeVal), {merge: true});
            return;
          }

          // CREATE (was unlinked, now linked)
          if (!beforeBoqId && afterBoqId) {
            tx.set(boqDoc(afterBoqId), incUnit(afterUnit, afterVal), {merge: true});
            return;
          }

          // UPDATE same BOQ
          if (beforeBoqId === afterBoqId) {
            // Unit changed: move between buckets
            if (beforeUnit !== afterUnit) {
              tx.set(boqDoc(afterBoqId), incUnit(beforeUnit, -beforeVal), {merge: true});
              tx.set(boqDoc(afterBoqId), incUnit(afterUnit, afterVal), {merge: true});
              return;
            }

            // Same unit: only apply delta
            const delta = afterVal - beforeVal;
            if (delta !== 0) {
              tx.set(boqDoc(afterBoqId), incUnit(afterUnit, delta), {merge: true});
            }
            return;
          }

          // MOVED BOQ (✅ your “shift figure to new BOQ code” requirement)
          tx.set(boqDoc(beforeBoqId), incUnit(beforeUnit, -beforeVal), {merge: true});
          tx.set(boqDoc(afterBoqId), incUnit(afterUnit, afterVal), {merge: true});
        });
      } catch (e) {
        logger.error("syncBoqTotals failed", e);
        throw e;
      }
    },
);

exports.syncLinkedDerivedMeasurements = onDocumentWritten(
    {document: MEAS_PATH, region: "us-central1"}, // change region if needed
    async (event) => {
      const params = event.params || {};
      const projectId = asStr(params.projectId);
      const buildingId = asStr(params.buildingId);
      const sourceDocId = asStr(params.docId);

      const before = event.data && event.data.before ? event.data.before.data() : null;
      const after = event.data && event.data.after ? event.data.after.data() : null;

      // If the changed doc is itself derived, ignore (prevents recursion)
      if (after && after.isDerived === true) return;

      const measurementsCol = db
          .collection("projects").doc(projectId)
          .collection("buildings").doc(buildingId)
          .collection("measurements");

      // ------- 1) DOC-LINKED derived docs (derivedFromKind="doc") -------
      // If deleted, treat source value as 0 (or you can mark as broken)
      const sourceValue = after ? asNum(after.value) : 0;

      const docDerivedQuery = measurementsCol
          .where("derivedFromKind", "==", "doc")
          .where("derivedFromDocId", "==", sourceDocId);

      const docDerivedDocs = await listAllDocs(docDerivedQuery, 450);

      if (docDerivedDocs.length) {
        await updateDerivedDocs(measurementsCol, docDerivedDocs, (factor, offset) => {
          return (sourceValue * factor) + offset;
        });
      }

      // ------- 2) SUM-LINKED derived docs (derivedFromKind="boqCodeSum") -------
      // We recompute sums for:
      //  - current boqCode+unit (after)
      //  - previous boqCode+unit (before) if changed or deleted
      const afterBoq = after ? asStr(after.boqCode).trim() : "";
      const afterUnit = after ? asStr(after.unit).trim() : "";

      const beforeBoq = before ? asStr(before.boqCode).trim() : "";
      const beforeUnit = before ? asStr(before.unit).trim() : "";

      const keysToRecompute = [];

      if (afterBoq && afterUnit) {
        keysToRecompute.push({boqCode: afterBoq, unit: afterUnit});
      }
      // if doc deleted or code/unit changed, recompute old key too
      const changed =
        (beforeBoq && beforeUnit) &&
        (beforeBoq !== afterBoq || beforeUnit !== afterUnit);

      if ((beforeBoq && beforeUnit) && (changed || !after)) {
        keysToRecompute.push({boqCode: beforeBoq, unit: beforeUnit});
      }

      // de-dup keys
      const uniq = new Map();
      for (const k of keysToRecompute) {
        uniq.set(`${k.boqCode}||${k.unit}`, k);
      }

      for (const k of uniq.values()) {
        const sumKey = makeSumKey(projectId, buildingId, k.boqCode, k.unit);
        const sumVal = await recomputeBoqSum(measurementsCol, k.boqCode, k.unit);

        const sumDerivedQuery = measurementsCol
            .where("derivedFromKind", "==", "boqCodeSum")
            .where("derivedFromSumKey", "==", sumKey);

        const sumDerivedDocs = await listAllDocs(sumDerivedQuery, 450);

        if (sumDerivedDocs.length) {
          await updateDerivedDocs(measurementsCol, sumDerivedDocs, (factor, offset) => {
            return (sumVal * factor) + offset;
          });
        }
      }

      // ------- 3) OPTIONAL: best-effort backfill for missing boqItemId -------
      // This function does NOT rely on boqItemId for syncing.
      // If you want to backfill old docs, implement separately with your BOQ path.
    },
);

// const AZAMPAY_AUTH_URL =
//   process.env.AZAMPAY_AUTH_URL ||
//   "https://authenticator.azampay.co.tz/AppRegistration/GenerateToken";
// const AZAMPAY_CHECKOUT_URL_OVERRIDE =
//   process.env.AZAMPAY_CHECKOUT_URL ||
//   "";
// const AZAMPAY_CALLBACK_URL = process.env.AZAMPAY_CALLBACK_URL || "https://us-central1-aqssite-6aa5c.cloudfunctions.net/azamPayCallback";
// const azamPayAppName = defineSecret("AZAMPAY_APP_NAME");
// const azamPayClientId = defineSecret("AZAMPAY_CLIENT_ID");
// const azamPayClientSecret = defineSecret("AZAMPAY_CLIENT_SECRET");
// const azamPayApiKey = defineSecret("AZAMPAY_API_KEY");
// const AZAMPAY_ENV = defineSecret("AZAMPAY_ENV");

// const PLAN_PRICES_TZS = {
//   starter: 25000,
//   professional: 75000,
//   team: 200000,
// };

// function normalizedPlan(value) {
//   const v = asStr(value).trim().toLowerCase();
//   if (v === "starter" || v === "professional" || v === "team") return v;
//   return "";
// }

// function normalizedProvider(value) {
//   const v = asStr(value).trim().toLowerCase();
//   if (v === "airtel") return "Airtel";
//   if (v === "tigo" || v === "yas") return "Tigo";
//   if (v === "halopesa" || v === "halo pesa") return "Halopesa";
//   if (v === "azampesa" || v === "azam pesa") return "Azampesa";
//   if (v === "mpesa" || v === "m-pesa" || v === "vodacom") return "Mpesa";
//   return "";
// }

// function normalizeMsisdn(value) {
//   let raw = asStr(value).trim().replace(/[^\d+]/g, "");
//   if (raw.startsWith("+")) raw = raw.slice(1);
//   if (raw.startsWith("0")) raw = `255${raw.slice(1)}`;
//   if (raw.startsWith("7")) raw = `255${raw}`;
//   if (!/^255\d{9}$/.test(raw)) return "";
//   return raw;
// }

// function firstNonEmpty(...values) {
//   for (const value of values) {
//     const text = asStr(value).trim();
//     if (text) return text;
//   }
//   return "";
// }

// function lowerStatus(value) {
//   return asStr(value).trim().toLowerCase();
// }

// function isSuccessfulAzamPayStatus(value) {
//   const status = lowerStatus(value);
//   return [
//     "success",
//     "successful",
//     "completed",
//     "complete",
//     "paid",
//     "approved",
//     "accepted",
//   ].includes(status);
// }

// function isFailedAzamPayStatus(value) {
//   const status = lowerStatus(value);
//   return [
//     "failed",
//     "failure",
//     "cancelled",
//     "canceled",
//     "rejected",
//     "declined",
//     "expired",
//     "timeout",
//     "timedout",
//   ].includes(status);
// }

// function extractAzamPayCallbackPayload(body) {
//   const data = (body && typeof body === "object") ? body : {};
//   const nested = (data.data && typeof data.data === "object") ? data.data : {};
//   const result = (data.result && typeof data.result === "object") ? data.result : {};
//   const payload = {...data, ...nested, ...result};

//   return {
//     externalId: firstNonEmpty(
//         payload.externalId,
//         payload.externalID,
//         payload.reference,
//         payload.referenceId,
//         payload.merchantReference,
//         payload.orderId,
//         payload.utilityRef,
//     ),
//     transactionId: firstNonEmpty(
//         payload.transactionId,
//         payload.transactionID,
//         payload.transId,
//         payload.transID,
//         payload.azamPayTransactionId,
//         payload.azamTransactionId,
//     ),
//     status: firstNonEmpty(
//         payload.status,
//         payload.transactionStatus,
//         payload.paymentStatus,
//         payload.resultStatus,
//         payload.state,
//     ),
//     message: firstNonEmpty(
//         payload.message,
//         payload.description,
//         payload.statusMessage,
//         payload.resultMessage,
//     ),
//     raw: data,
//   };
// }

// function shortPublicPayment(paymentId) {
//   return paymentId.replace(/[^a-zA-Z0-9]/g, "").slice(0, 20);
// }

// function maskPhone(phone) {
//   const cleaned = String(phone || "").replace(/\s+/g, "");

//   if (cleaned.length <= 6) return cleaned;

//   const firstFour = cleaned.substring(0, 4);
//   const lastThree = cleaned.substring(cleaned.length - 3);

//   return `${firstFour} XXX ${lastThree}`;
// }
// function normalizeAzamPayEnv(value) {
//   const raw = String(value || "SANDBOX").trim().toLowerCase();

//   if (raw === "sandbox" || raw === "test" || raw === "testing") {
//     return "SANDBOX";
//   }

//   if (raw === "live" || raw === "production" || raw === "prod") {
//     return "LIVE";
//   }

//   return "SANDBOX";
// }

// function azamPayCheckoutUrl(env) {
//   if (AZAMPAY_CHECKOUT_URL_OVERRIDE) {
//     return AZAMPAY_CHECKOUT_URL_OVERRIDE;
//   }
//   const base =
//     env === "LIVE" ?
//       "https://checkout.azampay.co.tz" :
//       "https://sandbox.azampay.co.tz";
//   return `${base}/azampay/mno/checkout`;
// }
// function makeFirestoreSafe(value) {
//   if (value === null || value === undefined) return null;

//   if (
//     typeof value === "string" ||
//     typeof value === "number" ||
//     typeof value === "boolean"
//   ) {
//     return value;
//   }

//   if (value instanceof Date) {
//     return value.toISOString();
//   }

//   if (Array.isArray(value)) {
//     return value.map((item) => makeFirestoreSafe(item));
//   }

//   if (typeof value === "object") {
//     const plain = {};

//     Object.keys(value).forEach((key) => {
//       const item = value[key];

//       // Avoid saving sensitive or problematic SDK internals
//       if (
//         key === "config" ||
//         key === "request" ||
//         key === "headers" ||
//         key === "rawHeaders"
//       ) {
//         return;
//       }

//       plain[key] = makeFirestoreSafe(item);
//     });

//     return plain;
//   }

//   return String(value);
// }

// function compactGatewayMessage(value) {
//   const safe = makeFirestoreSafe(value);
//   if (!safe || typeof safe !== "object") return "";

//   const candidates = [
//     safe.message,
//     safe.error,
//     safe.detail,
//     safe.description,
//     safe.statusMessage,
//     safe.resultMessage,
//     safe.title,
//     safe.raw,
//     safe.data && safe.data.message,
//     safe.data && safe.data.error,
//     safe.data && safe.data.detail,
//     safe.result && safe.result.message,
//     safe.result && safe.result.error,
//   ];

//   for (const candidate of candidates) {
//     const text = String(candidate || "").trim();
//     if (text) return text.slice(0, 240);
//   }

//   return "";
// }
/*
  Remove accidental wrong role flags if they exist.
  Do not remove other claims like admin-created flags unless needed.
*/
/* eslint-disable indent */

// exports.azamPayMnoCheckout = onCall(
//   {
//     region: "us-central1",
//     timeoutSeconds: 60,
//     memory: "256MiB",
//     secrets: [
//       AZAMPAY_ENV,
//       azamPayAppName,
//       azamPayClientId,
//       azamPayClientSecret,
//       azamPayApiKey,
//     ],
//   },
//   async (request) => {
//     if (!request.auth) {
//       throw new HttpsError("unauthenticated", "Sign in first.");
//     }

//     const uid = request.auth.uid;
//     const data = request.data || {};

//     let stage = "start";
//     let paymentRef = null;
//     let paymentId = "";
//     let externalId = "";
//     let plan = "";
//     let provider = "";
//     let accountNumber = "";
//     let amount = 0;
//     let env = "";

//     try {
//       stage = "validate_input";

//       plan = normalizedPlan(data.plan);
//       provider = normalizedProvider(data.provider);
//       accountNumber = normalizeMsisdn(data.phone);
//       amount = PLAN_PRICES_TZS[plan] || 0;

//       if (!plan) {
//         throw new HttpsError("invalid-argument", "Invalid subscription plan.");
//       }

//       if (!provider) {
//         throw new HttpsError("invalid-argument", "Invalid mobile money provider.");
//       }

//       if (!accountNumber) {
//         throw new HttpsError(
//           "invalid-argument",
//           "Enter a valid Tanzania phone number.",
//         );
//       }

//       if (amount <= 0) {
//         throw new HttpsError("invalid-argument", "Invalid subscription amount.");
//       }

//       stage = "create_payment";

//       paymentRef = db.collection("subscriptionPayments").doc();
//       paymentId = paymentRef.id;
//       externalId = shortPublicPayment(paymentId);

//       await paymentRef.set({
//         uid,
//         plan,
//         amount,
//         currency: "TZS",
//         provider,
//         accountNumber,
//         maskedAccountNumber: maskPhone(accountNumber),
//         externalId,
//         status: "initiated",
//         paymentStatus: "pending",
//         gateway: "azamPay",
//         stage,
//         createdAt: FieldValue.serverTimestamp(),
//         updatedAt: FieldValue.serverTimestamp(),
//       });

//       stage = "save_user_pending";

//       await db.collection("users").doc(uid).set(
//         {
//           subscriptionPlan: plan,
//           subscriptionStatus: "payment_initiating",
//           pendingSubscriptionPaymentId: paymentId,
//           updatedAt: FieldValue.serverTimestamp(),
//         },
//         {merge: true},
//       );

//       stage = "validate_secrets";

//       env = normalizeAzamPayEnv(AZAMPAY_ENV.value());

//       const appName = String(azamPayAppName.value() || "").trim();
//       const clientId = String(azamPayClientId.value() || "").trim();
//       const clientSecret = String(azamPayClientSecret.value() || "").trim();
//       const apiKey = String(azamPayApiKey.value() || "").trim();

//       const missingSecrets = [];

//       if (!env) missingSecrets.push("AZAMPAY_ENV");
//       if (!appName) missingSecrets.push("AZAMPAY_APP_NAME");
//       if (!clientId) missingSecrets.push("AZAMPAY_CLIENT_ID");
//       if (!clientSecret) missingSecrets.push("AZAMPAY_CLIENT_SECRET");
//       if (!apiKey) missingSecrets.push("AZAMPAY_API_KEY");

//       if (missingSecrets.length > 0) {
//         throw new Error(
//           `Missing AzamPay secrets: ${missingSecrets.join(", ")}`,
//         );
//       }

//       stage = "get_token";

//       const token = await azampay.getToken({
//         env,
//         clientId,
//         clientSecret,
//         appName,
//         apiKey,
//       });

//       logger.info("AZAMPAY TOKEN DEBUG", {
//         paymentId,
//         externalId,
//         success: token && token.success,
//         message: token && token.message,
//         statusCode: token && token.statusCode,
//         hasAccessToken: !!(token && token.data && token.data.accessToken),
//         hasMnoCheckout: !!(token && typeof token.mnoCheckout === "function"),
//         env,
//       });

//       if (!token || !token.data || !token.data.accessToken) {
//         throw new Error(
//           "AzamPay access token missing. Message: " +
//             ((token && token.message) || "No message"),
//         );
//       }

//       if (typeof token.mnoCheckout !== "function") {
//         throw new Error("AzamPay mnoCheckout function is missing.");
//       }

//       stage = "mno_checkout";

//       const checkoutPayload = {
//         accountNumber: String(accountNumber),
//         amount: String(amount),
//         currency: "TZS",
//         externalId,
//         provider: String(provider),
//         additionalProperties: {
//           source: "aqsautoboq",
//           uid,
//           plan,
//           paymentId,
//         },
//       };

//       if (AZAMPAY_CALLBACK_URL) {
//         checkoutPayload.callbackUrl = AZAMPAY_CALLBACK_URL;
//       }

//       logger.info("AZAMPAY SUBSCRIPTION CHECKOUT REQUEST", {
//         uid,
//         paymentId,
//         externalId,
//         plan,
//         provider,
//         amount,
//         accountNumber: maskPhone(accountNumber),
//         env,
//       });

//       const checkoutJson = await token.mnoCheckout(checkoutPayload, {
//         apiKey,
//         accessToken: token.data.accessToken,
//         env,
//       });

//       const safeCheckoutResponse = makeFirestoreSafe(checkoutJson);
//       const checkoutAccepted =
//         safeCheckoutResponse &&
//         safeCheckoutResponse.success === true &&
//         Number(safeCheckoutResponse.statusCode || 0) >= 200 &&
//         Number(safeCheckoutResponse.statusCode || 0) < 300;

//       if (!checkoutAccepted) {
//         const errorMessage = String(
//           safeCheckoutResponse.message ||
//           safeCheckoutResponse.error ||
//           safeCheckoutResponse.code ||
//           "AzamPay checkout failed.",
//         );

//         await paymentRef.set(
//           {
//             status: "checkout_failed",
//             paymentStatus: "failed",
//             checkoutResponse: safeCheckoutResponse,
//             error: errorMessage,
//             stage: "checkout_failed",
//             checkoutUpdatedAt: FieldValue.serverTimestamp(),
//             updatedAt: FieldValue.serverTimestamp(),
//           },
//           {merge: true},
//         );

//         await db.collection("users").doc(uid).set(
//           {
//             subscriptionStatus: "failed",
//             pendingSubscriptionPaymentId: FieldValue.delete(),
//             updatedAt: FieldValue.serverTimestamp(),
//           },
//           {merge: true},
//         );

//         throw new HttpsError(
//           "internal",
//           "AzamPay checkout failed. Please try again.",
//         );
//       }

//       logger.info("AZAMPAY SUBSCRIPTION CHECKOUT RESPONSE", {
//         paymentId,
//         externalId,
//         response: safeCheckoutResponse,
//       });

//       stage = "save_attempt_success";

//       await paymentRef.collection("attempts").add({
//         gateway: "azamPay",
//         environment: env,
//         provider,
//         amount,
//         accountNumber: maskPhone(accountNumber),
//         checkoutPayload: makeFirestoreSafe({
//           ...checkoutPayload,
//           accountNumber: maskPhone(accountNumber),
//         }),
//         checkoutResponse: safeCheckoutResponse,
//         success: true,
//         stage,
//         createdAt: FieldValue.serverTimestamp(),
//       });

//       stage = "save_checkout_response";

//       await db.runTransaction(async (firestoreTx) => {
//         const latestSnap = await firestoreTx.get(paymentRef);

//         if (!latestSnap.exists) return;

//         const latest = latestSnap.data() || {};
//         const latestStatus = String(latest.status || "").toLowerCase();
//         const latestPaymentStatus = String(latest.paymentStatus || "").toLowerCase();

//         const alreadyPaid =
//           latestStatus === "paid" ||
//           latestPaymentStatus === "paid" ||
//           latestStatus === "completed" ||
//           latestPaymentStatus === "completed" ||
//           latestStatus === "success" ||
//           latestPaymentStatus === "success";

//         const updateData = {
//           checkoutResponse: safeCheckoutResponse,
//           checkoutUpdatedAt: FieldValue.serverTimestamp(),
//           stage,
//           updatedAt: FieldValue.serverTimestamp(),
//         };

//         if (!alreadyPaid) {
//           updateData.status = "pending";
//           updateData.paymentStatus = "pending";
//         } else {
//           updateData.checkoutCompletedAfterCallback = true;
//         }

//         firestoreTx.set(paymentRef, updateData, {merge: true});
//       });

//       await db.runTransaction(async (firestoreTx) => {
//         const userRef = db.collection("users").doc(uid);
//         const userSnap = await firestoreTx.get(userRef);
//         const user = userSnap.exists ? userSnap.data() || {} : {};

//         const currentSubStatus = String(user.subscriptionStatus || "").toLowerCase();

//         const alreadyActive =
//           currentSubStatus === "active" ||
//           currentSubStatus === "paid";

//         const userUpdate = {
//           subscriptionPlan: plan,
//           pendingSubscriptionPaymentId: paymentId,
//           updatedAt: FieldValue.serverTimestamp(),
//         };

//         if (!alreadyActive) {
//           userUpdate.subscriptionStatus = "pending";
//         }

//         firestoreTx.set(userRef, userUpdate, {merge: true});
//       });

//       return {
//         ok: true,
//         paymentId,
//         externalId,
//         plan,
//         amount,
//         currency: "TZS",
//         provider,
//         response: safeCheckoutResponse,
//       };
//     } catch (error) {
//       logger.error("AZAMPAY SUBSCRIPTION CHECKOUT ERROR", {
//         stage,
//         uid,
//         paymentId,
//         externalId,
//         plan,
//         provider,
//         amount,
//         errorCode: error && error.code,
//         errorMessage: error && error.message,
//         errorDetails: error && error.details,
//       });

//       if (paymentRef) {
//         try {
//           const responseData = error && error.response ? error.response.data : null;
//           const statusCode = error && error.response ? error.response.status : null;

//           const errorMessage = String(
//             (responseData &&
//               (responseData.message ||
//                 responseData.error ||
//                 responseData.detail)) ||
//               (error && error.message) ||
//               "AzamPay subscription checkout failed.",
//           );

//           await paymentRef.collection("attempts").add({
//             gateway: "azamPay",
//             environment: env || null,
//             provider: provider || null,
//             amount: amount || 0,
//             accountNumber: accountNumber ? maskPhone(accountNumber) : null,
//             success: false,
//             stage,
//             error: errorMessage,
//             statusCode: statusCode || null,
//             responseData: responseData ? makeFirestoreSafe(responseData) : null,
//             failedAt: FieldValue.serverTimestamp(),
//           });

//           await paymentRef.set(
//             {
//               status: "failed",
//               paymentStatus: "failed",
//               error: errorMessage,
//               stage,
//               updatedAt: FieldValue.serverTimestamp(),
//             },
//             {merge: true},
//           );

//           await db.collection("users").doc(uid).set(
//             {
//               subscriptionStatus: "failed",
//               pendingSubscriptionPaymentId: paymentId || null,
//               updatedAt: FieldValue.serverTimestamp(),
//             },
//             {merge: true},
//           );
//         } catch (logError) {
//           logger.error("AZAMPAY SUBSCRIPTION ERROR LOGGING FAILED", {
//             paymentId,
//             message: String(
//               logError && logError.message ? logError.message : logError,
//             ),
//           });
//         }
//       }

//       if (error instanceof HttpsError) {
//         throw error;
//       }

//       throw new HttpsError(
//         "internal",
//         "Failed to initiate subscription payment. Please try again.",
//       );
//     }
//   },
// );
// function isSuccessfulAzamPayStatus(status) {
//   const s = String(status || "").trim().toLowerCase();

//   return [
//     "success",
//     "successful",
//     "paid",
//     "completed",
//     "complete",
//     "approved",
//   ].includes(s);
// }

// exports.azamPayCallback = onRequest(
//   {region: "us-central1", timeoutSeconds: 60, memory: "256MiB"},
//   async (req, res) => {
//     try {
//       if (req.method !== "POST") {
//         res.status(405).json({ok: false, message: "Method not allowed"});
//         return;
//       }

//       const parsed = extractAzamPayCallbackPayload(req.body || {});

//       const externalId = asStr(
//         parsed.externalId ||
//           req.body.externalreference ||
//           req.body.reference ||
//           req.body.transid,
//       );

//       const callbackStatus = asStr(
//         parsed.status ||
//           req.body.transactionstatus ||
//           req.body.status ||
//           req.body.message,
//       ).toLowerCase();

//       const body = req.body || {};
//       const bodyAdditional = body.additionalProperties || {};
//       const parsedRaw = parsed.raw || {};
//       const parsedRawAdditional = parsedRaw.additionalProperties || {};

//       const paymentIdFromBody = asStr(
//         bodyAdditional.paymentId ||
//         body.utilityref ||
//         parsedRawAdditional.paymentId ||
//         parsedRaw.utilityref ||
//         "",
//       );

//       logger.info("AzamPay callback received", {
//         externalId,
//         paymentIdFromBody,
//         transactionId: parsed.transactionId || req.body.transid || "",
//         status: callbackStatus,
//         raw: req.body,
//       });

//       if (!externalId && !paymentIdFromBody) {
//         res.status(400).json({
//           ok: false,
//           message: "Missing payment reference",
//         });
//         return;
//       }

//       let paymentDoc = null;

//       if (paymentIdFromBody) {
//         const byPaymentId = await db
//           .collection("subscriptionPayments")
//           .doc(paymentIdFromBody)
//           .get();

//         if (byPaymentId.exists) {
//           paymentDoc = byPaymentId;
//         }
//       }

//       if (!paymentDoc && externalId) {
//         const byExternalIdDoc = await db
//           .collection("subscriptionPayments")
//           .doc(externalId)
//           .get();

//         if (byExternalIdDoc.exists) {
//           paymentDoc = byExternalIdDoc;
//         }
//       }

//       if (!paymentDoc && externalId) {
//         const snap = await db
//           .collection("subscriptionPayments")
//           .where("externalId", "==", externalId)
//           .limit(1)
//           .get();

//         if (!snap.empty) {
//           paymentDoc = snap.docs[0];
//         }
//       }

//       if (!paymentDoc) {
//         logger.warn("AzamPay callback payment not found", {
//           externalId,
//           paymentIdFromBody,
//           body: req.body,
//         });

//         res.status(404).json({
//           ok: false,
//           message: "Payment not found",
//           externalId,
//           paymentIdFromBody,
//         });
//         return;
//       }

//       const paymentRef = paymentDoc.ref;
//       const payment = paymentDoc.data() || {};

//       // const body = req.body || {};
//       const additionalProperties = body.additionalProperties || {};

//       const uid = asStr(
//         payment.uid ||
//         additionalProperties.uid ||
//         "",
//       );

//       const plan = normalizedPlan(
//         payment.plan ||
//         additionalProperties.plan ||
//         "",
//       );

//       const success = isSuccessfulAzamPayStatus(callbackStatus);
//       const failed = isFailedAzamPayStatus(callbackStatus);

//       logger.info("AzamPay status resolved", {
//         callbackStatus,
//         success,
//         failed,
//       });

//       const nextPaymentStatus = success ? "paid" : failed ? "failed" : "pending";
//       const nextSubscriptionStatus = success ? "active" : failed ? "failed" : "pending";

//       const periodEnd = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

//       const batch = db.batch();

//       batch.set(
//         paymentRef,
//         {
//           status: nextPaymentStatus,
//           paymentStatus: nextPaymentStatus,
//           callbackStatus,
//           callbackMessage: req.body.message || parsed.message || null,
//           transactionId: req.body.transid || parsed.transactionId || null,
//           mnoReference: req.body.mnoreference || null,
//           operator: req.body.operator || null,
//           msisdn: req.body.msisdn || null,
//           callbackPayload: makeFirestoreSafe(req.body || {}),
//           callbackReceivedAt: FieldValue.serverTimestamp(),
//           updatedAt: FieldValue.serverTimestamp(),
//         },
//         {merge: true},
//       );

//       if (uid && plan) {
//         const userUpdate = {
//           subscriptionPlan: plan,
//           subscriptionStatus: nextSubscriptionStatus,
//           lastSubscriptionPaymentId: paymentRef.id,
//           updatedAt: FieldValue.serverTimestamp(),
//         };

//         if (success) {
//           userUpdate.subscriptionStartedAt = FieldValue.serverTimestamp();
//           userUpdate.subscriptionCurrentPeriodEnd =
//             admin.firestore.Timestamp.fromDate(periodEnd);
//           userUpdate.pendingSubscriptionPaymentId = FieldValue.delete();
//         }

//         if (failed) {
//           userUpdate.pendingSubscriptionPaymentId = FieldValue.delete();
//         }

//         batch.set(db.collection("users").doc(uid), userUpdate, {merge: true});
//       }

//       await batch.commit();

//       logger.info("AzamPay callback processed", {
//         paymentId: paymentRef.id,
//         externalId,
//         paymentIdFromBody,
//         uid,
//         plan,
//         paymentStatus: nextPaymentStatus,
//         subscriptionStatus: nextSubscriptionStatus,
//       });

//       res.status(200).json({
//         ok: true,
//         paymentId: paymentRef.id,
//         externalId,
//         status: nextPaymentStatus,
//         subscriptionStatus: nextSubscriptionStatus,
//       });
//     } catch (error) {
//       logger.error("AzamPay callback processing failed", {
//         message: error && error.message,
//         stack: error && error.stack,
//         body: req.body,
//       });

//       res.status(500).json({
//         ok: false,
//         message: "Callback processing failed",
//       });
//     }
//   },
// );
