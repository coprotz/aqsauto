const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const MAX_IMAGE_BYTES = 15 * 1024 * 1024;

function diagnosticError(code, firebaseCode, message, logDetails = {}) {
  console.error("Slab rebar AI failed", {
    diagnosticCode: code,
    ...logDetails,
  });
  return new HttpsError(firebaseCode, message, {diagnosticCode: code});
}

function asNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function cleanJson(text) {
  const value = String(text || "").trim()
      .replace(/^```(?:json)?\s*/i, "")
      .replace(/\s*```$/, "");
  const first = value.indexOf("{");
  const last = value.lastIndexOf("}");
  if (first < 0 || last <= first) throw new Error("No JSON object returned");
  return JSON.parse(value.slice(first, last + 1));
}

function normalizeMarks(raw) {
  const source = raw && Array.isArray(raw.marks) ? raw.marks : [];
  const seen = new Set();
  const marks = [];
  for (const item of source) {
    const rawMark = String(item && item.rawMark || "")
        .toUpperCase()
        .replace(/\s+/g, "")
        .trim();
    if (!/^\d+[A-Z]\d+(?:-[A-Z0-9]+){0,3}$/.test(rawMark)) continue;
    const direction = item.direction === "vertical" ? "vertical" : "horizontal";
    const key = `${rawMark}|${direction}`;
    if (seen.has(key)) continue;
    seen.add(key);
    marks.push({
      rawMark,
      direction,
      occurrences: Math.max(1, Math.round(asNumber(item.occurrences) || 1)),
      confidence: Math.max(0, Math.min(1, asNumber(item.confidence) || 0.5)),
    });
  }
  return marks.slice(0, 60);
}

exports.analyseSlabRebarMarks = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 120,
      memory: "512MiB",
      secrets: [GEMINI_API_KEY],
    },
    async (request) => {
      if (!request.auth) {
        throw diagnosticError(
            "AUTH_REQUIRED",
            "unauthenticated",
            "Sign in to use AI drawing reading.",
        );
      }
      const imageUrl = String(request.data && request.data.imageUrl || "").trim();
      if (!imageUrl.startsWith("https://")) {
        throw diagnosticError(
            "IMAGE_URL_INVALID",
            "invalid-argument",
            "The drawing does not have a downloadable HTTPS image URL.",
            {urlScheme: imageUrl.split(":")[0] || "missing"},
        );
      }

      let imageResponse;
      try {
        imageResponse = await fetch(imageUrl, {signal: AbortSignal.timeout(30000)});
      } catch (error) {
        throw diagnosticError(
            "IMAGE_FETCH_FAILED",
            "unavailable",
            "The drawing image could not be downloaded by the AI service.",
            {reason: error && error.name || "unknown"},
        );
      }
      if (!imageResponse.ok) {
        throw diagnosticError(
            "IMAGE_HTTP_ERROR",
            "unavailable",
            "The drawing image server refused the AI download.",
            {httpStatus: imageResponse.status},
        );
      }
      const bytes = Buffer.from(await imageResponse.arrayBuffer());

      // Load canvas lazily so Firebase function discovery stays lightweight.
      const {createCanvas, loadImage} = require("canvas");
      if (!bytes.length) {
        throw diagnosticError(
            "IMAGE_EMPTY",
            "invalid-argument",
            "The downloaded drawing image is empty.",
        );
      }
      if (bytes.length > MAX_IMAGE_BYTES) {
        throw diagnosticError(
            "IMAGE_TOO_LARGE",
            "invalid-argument",
            "The drawing image is too large for AI reading.",
            {imageBytes: bytes.length, maximumBytes: MAX_IMAGE_BYTES},
        );
      }

      const polygon = Array.isArray(request.data.polygon) ? request.data.polygon : [];
      const bounds = polygon.reduce((acc, point) => ({
        minX: Math.min(acc.minX, asNumber(point.x)),
        maxX: Math.max(acc.maxX, asNumber(point.x)),
        minY: Math.min(acc.minY, asNumber(point.y)),
        maxY: Math.max(acc.maxY, asNumber(point.y)),
      }), {minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity});

      let analysisBytes = bytes;
      let analysisMimeType = (imageResponse.headers.get("content-type") || "image/png")
          .split(";")[0];
      try {
        const image = await loadImage(bytes);
        const margin = 30;
        const left = Math.max(0, Math.floor(bounds.minX - margin));
        const top = Math.max(0, Math.floor(bounds.minY - margin));
        const right = Math.min(image.width, Math.ceil(bounds.maxX + margin));
        const bottom = Math.min(image.height, Math.ceil(bounds.maxY + margin));
        const width = right - left;
        const height = bottom - top;
        if (width > 20 && height > 20) {
          const canvas = createCanvas(width, height);
          canvas.getContext("2d").drawImage(
              image,
              left,
              top,
              width,
              height,
              0,
              0,
              width,
              height,
          );
          analysisBytes = canvas.toBuffer("image/png");
          analysisMimeType = "image/png";
        }
      } catch (error) {
        console.warn("Slab rebar AI could not crop the selected panel", {
          diagnosticCode: "IMAGE_CROP_SKIPPED",
          reason: error && error.message || "unknown",
        });
        // Keep the original image when the server cannot decode/crop it.
      }

      const prompt = [
        "You are reading a structural slab reinforcement drawing for quantity take-off.",
        "The supplied image is the selected slab panel (with a small context margin).",
        "Read only reinforcement callouts whose leader or text belongs to this panel.",
        "Typical marks include 36Y12-08-150T1, 9Y12-14-150T2, or 11Y12-16-150T2.",
        "Preserve the exact quantity, bar letter/diameter, bar number, spacing, and layer.",
        "Infer direction from the leader/rebar line: horizontal or vertical.",
        "If the same exact callout is repeated for separate groups, set occurrences to that count.",
        "Do not invent obscured text. Return JSON only:",
        "{\"marks\":[{\"rawMark\":\"36Y12-08-150T1\",\"direction\":\"horizontal\",\"occurrences\":1,\"confidence\":0.95}]}",
      ].join("\n");

      let geminiApiKey;
      try {
        geminiApiKey = GEMINI_API_KEY.value();
      } catch (error) {
        throw diagnosticError(
            "GEMINI_SECRET_UNAVAILABLE",
            "failed-precondition",
            "The Gemini API secret is not available to the deployed function.",
            {reason: error && error.message || "unknown"},
        );
      }
      if (!geminiApiKey) {
        throw diagnosticError(
            "GEMINI_SECRET_EMPTY",
            "failed-precondition",
            "The Gemini API secret is empty.",
        );
      }

      const requestBody = JSON.stringify({
        contents: [{parts: [
          {text: prompt},
          {inlineData: {
            mimeType: analysisMimeType,
            data: analysisBytes.toString("base64"),
          }},
        ]}],
        generationConfig: {responseMimeType: "application/json", temperature: 0},
      });

      const generateWithModel = (modelId) => {
        const cleanModelId = String(modelId).replace(/^models\//, "");
        const endpoint = "https://generativelanguage.googleapis.com/v1beta/models/" +
          encodeURIComponent(cleanModelId) + ":generateContent?key=" +
          encodeURIComponent(geminiApiKey);
        return fetch(endpoint, {
          method: "POST",
          headers: {"content-type": "application/json"},
          body: requestBody,
          signal: AbortSignal.timeout(90000),
        });
      };

      const wait = (milliseconds) => new Promise((resolve) => {
        setTimeout(resolve, milliseconds);
      });
      const generateWithRetry = async (modelId) => {
        const fallbackDelays = [2000, 5000, 10000];
        let response = await generateWithModel(modelId);
        for (let attempt = 0;
          response.status === 429 && attempt < fallbackDelays.length;
          attempt += 1) {
          const retryAfter = Number(response.headers.get("retry-after"));
          const delay = Number.isFinite(retryAfter) && retryAfter > 0 ?
            Math.min(retryAfter * 1000, 20000) : fallbackDelays[attempt];
          console.warn("Gemini rate limited slab rebar AI; retrying", {
            diagnosticCode: "GEMINI_RATE_LIMIT_RETRY",
            selectedModel: modelId,
            attempt: attempt + 1,
            delayMilliseconds: delay,
          });
          await wait(delay);
          response = await generateWithModel(modelId);
        }
        return response;
      };

      let aiResponse;
      let selectedModel = "gemini-2.5-flash";
      try {
        aiResponse = await generateWithRetry(selectedModel);

        if (aiResponse.status === 404) {
          const modelsEndpoint =
            "https://generativelanguage.googleapis.com/v1beta/models?key=" +
            encodeURIComponent(geminiApiKey);
          const modelsResponse = await fetch(modelsEndpoint, {
            signal: AbortSignal.timeout(30000),
          });
          if (!modelsResponse.ok) {
            throw diagnosticError(
                `GEMINI_MODELS_HTTP_${modelsResponse.status}`,
                "failed-precondition",
                "Gemini models could not be resolved for this API key.",
                {httpStatus: modelsResponse.status},
            );
          }

          const modelsPayload = await modelsResponse.json();
          const availableModels = Array.isArray(modelsPayload.models) ?
            modelsPayload.models.filter((model) =>
              Array.isArray(model.supportedGenerationMethods) &&
              model.supportedGenerationMethods.includes("generateContent") &&
              String(model.name || "").toLowerCase().includes("flash"),
            ) : [];
          const preferredIds = [
            "gemini-2.5-flash",
            "gemini-2.0-flash",
            "gemini-1.5-flash",
          ];
          const availableIds = availableModels.map((model) =>
            String(model.name || "").replace(/^models\//, ""),
          );
          const fallbackIds = [
            ...preferredIds.filter((id) => availableIds.includes(id)),
            ...availableIds,
          ].filter((id, index, values) =>
            id !== selectedModel && values.indexOf(id) === index,
          );

          if (!fallbackIds.length) {
            throw diagnosticError(
                "GEMINI_NO_FLASH_MODEL",
                "failed-precondition",
                "No alternative Gemini Flash model is available for this API key.",
            );
          }

          const attemptedModels = [selectedModel];
          for (const fallbackId of fallbackIds) {
            selectedModel = fallbackId;
            attemptedModels.push(selectedModel);
            console.info("Slab rebar AI trying an available fallback model", {
              selectedModel,
            });
            aiResponse = await generateWithRetry(selectedModel);
            if (aiResponse.status !== 404) break;
          }

          if (aiResponse.status === 404) {
            throw diagnosticError(
                "GEMINI_MODELS_NOT_CALLABLE",
                "failed-precondition",
                "The listed Gemini Flash models are not callable by this API key.",
                {attemptedModels},
            );
          }
        }
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        throw diagnosticError(
            "GEMINI_FETCH_FAILED",
            "unavailable",
            "The deployed function could not reach Gemini.",
            {reason: error && error.name || "unknown"},
        );
      }
      if (aiResponse.status === 429) {
        const responseText = await aiResponse.text();
        throw diagnosticError(
            "GEMINI_QUOTA_EXCEEDED",
            "resource-exhausted",
            "Gemini is busy or this project's AI quota is exhausted. " +
              "Please try again shortly.",
            {
              httpStatus: aiResponse.status,
              selectedModel,
              response: responseText.slice(0, 500),
            },
        );
      }
      if (!aiResponse.ok) {
        const responseText = await aiResponse.text();
        throw diagnosticError(
            `GEMINI_HTTP_${aiResponse.status}`,
            "internal",
            "Gemini could not process the selected drawing panel.",
            {
              httpStatus: aiResponse.status,
              selectedModel,
              response: responseText.slice(0, 500),
            },
        );
      }
      const payload = await aiResponse.json();
      const text = payload.candidates && payload.candidates[0] &&
        payload.candidates[0].content && payload.candidates[0].content.parts &&
        payload.candidates[0].content.parts.map((part) => part.text || "").join("");

      try {
        return {marks: normalizeMarks(cleanJson(text))};
      } catch (error) {
        throw diagnosticError(
            "GEMINI_RESPONSE_INVALID",
            "internal",
            "Gemini returned an unreadable result. Please try again.",
            {reason: error && error.message || "unknown"},
        );
      }
    },
);
