const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const MAX_PDF_BYTES = 20 * 1024 * 1024;

function fail(code, firebaseCode, message, details = {}) {
  console.error("External quotation extraction failed", {code, ...details});
  throw new HttpsError(firebaseCode, message, {diagnosticCode: code});
}

function asNumber(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const cleaned = String(value == null ? "" : value)
      .replace(/[^0-9.-]/g, "")
      .trim();
  const parsed = Number(cleaned);
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

function normalizeItems(raw) {
  const source = raw && Array.isArray(raw.items) ? raw.items : [];
  const items = [];
  for (let i = 0; i < source.length; i++) {
    const row = source[i] || {};
    const description = String(row.description || "").replace(/\s+/g, " ").trim();
    if (!description) continue;
    const quantity = asNumber(row.quantity);
    const rate = asNumber(row.rate);
    let amount = asNumber(row.amount);
    if (!amount && quantity && rate) amount = quantity * rate;
    items.push({
      itemNo: String(row.itemNo || i + 1).trim(),
      description,
      unit: String(row.unit || "").trim(),
      quantity,
      rate,
      amount,
      page: Math.max(1, Math.round(asNumber(row.page) || 1)),
      needsReview: row.needsReview === true || !amount,
    });
  }
  return items.slice(0, 1000);
}

async function callGemini(apiKey, pdfBytes, prompt) {
  const body = JSON.stringify({
    contents: [{parts: [
      {text: prompt},
      {inlineData: {mimeType: "application/pdf", data: pdfBytes.toString("base64")}},
    ]}],
    generationConfig: {responseMimeType: "application/json", temperature: 0},
  });
  const models = ["gemini-2.5-flash", "gemini-2.0-flash"];
  let lastError = "";
  for (const model of models) {
    const url = "https://generativelanguage.googleapis.com/v1beta/models/" +
      encodeURIComponent(model) + ":generateContent?key=" + encodeURIComponent(apiKey);
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {"content-type": "application/json"},
        body,
        signal: AbortSignal.timeout(110000),
      });
      const text = await response.text();
      if (!response.ok) {
        lastError = `${model}: HTTP ${response.status} ${text.slice(0, 400)}`;
        continue;
      }
      const payload = JSON.parse(text);
      const output = payload && payload.candidates && payload.candidates[0] &&
        payload.candidates[0].content && payload.candidates[0].content.parts &&
        payload.candidates[0].content.parts
            .map((part) => part.text || "").join("\n");
      if (!output) {
        lastError = `${model}: empty model response`;
        continue;
      }
      return {json: cleanJson(output), model};
    } catch (error) {
      lastError = `${model}: ${error && error.message || "unknown error"}`;
    }
  }
  throw new Error(lastError || "Gemini did not return a usable response");
}

exports.extractExternalQuotationItems = onCall(
    {
      region: "us-central1",
      timeoutSeconds: 120,
      memory: "1GiB",
      secrets: [GEMINI_API_KEY],
    },
    async (request) => {
      if (!request.auth) {
        fail("AUTH_REQUIRED", "unauthenticated", "Sign in to import quotation PDFs.");
      }

      const pdfUrl = String(request.data && request.data.pdfUrl || "").trim();
      if (!/^https:\/\//i.test(pdfUrl)) {
        fail("PDF_URL_INVALID", "invalid-argument", "The quotation does not have a valid HTTPS PDF URL.");
      }

      let response;
      try {
        response = await fetch(pdfUrl, {signal: AbortSignal.timeout(30000)});
      } catch (error) {
        fail("PDF_FETCH_FAILED", "unavailable", "The quotation PDF could not be downloaded.", {
          reason: error && error.message || "unknown",
        });
      }
      if (!response.ok) {
        fail("PDF_HTTP_ERROR", "unavailable", "The quotation PDF server refused the download.", {
          httpStatus: response.status,
        });
      }
      const pdfBytes = Buffer.from(await response.arrayBuffer());
      if (!pdfBytes.length) fail("PDF_EMPTY", "invalid-argument", "The quotation PDF is empty.");
      if (pdfBytes.length > MAX_PDF_BYTES) {
        fail("PDF_TOO_LARGE", "invalid-argument", "The quotation PDF is too large for automatic extraction.", {
          pdfBytes: pdfBytes.length,
          maximumBytes: MAX_PDF_BYTES,
        });
      }

      let apiKey = "";
      try {
        apiKey = GEMINI_API_KEY.value();
      } catch (error) {
        fail("GEMINI_SECRET_UNAVAILABLE", "failed-precondition", "The Gemini API secret is not available.");
      }
      if (!apiKey) fail("GEMINI_SECRET_EMPTY", "failed-precondition", "The Gemini API secret is empty.");

      const prompt = [
        "You are extracting a contractor or specialist quotation into editable QS line items for AQS AUTOBoq.",
        "Read the entire attached PDF, including all schedules/tables on all pages.",
        "Extract ONLY genuine priced detail rows that contribute to the quotation total.",
        "Do NOT create rows for headings, section titles, SUB TOTAL, TOTAL, GRAND TOTAL, VAT, carried-forward totals, letters, signatures, or summary rows that duplicate detailed schedules.",
        "If the document contains multiple detailed schedules (for example CBD MARKET and INALA BUS TERMINAL), include the priced detail rows from every schedule.",
        "Preserve the contractor's item number, description, unit, quantity, rate, and amount exactly in meaning.",
        "Convert formatted numbers such as 1,404,000.00 to JSON numbers without commas.",
        "For each detail row, amount should normally equal quantity x rate. Preserve the printed amount if present.",
        "Set needsReview=true when any item number, unit, quantity, rate, amount, or row boundary is uncertain.",
        "Set page to the 1-based PDF page where the priced row appears.",
        "quotedTotal must be the final amount payable/quoted by the contractor from the final summary, after VAT if VAT is actually charged. If VAT is zero, use the stated final total amount.",
        "Also return currency when clearly stated or infer TZS only when the document explicitly indicates Tanzanian shillings/TZS.",
        "Return JSON only in this exact shape:",
        "{\"items\":[{\"itemNo\":\"1\",\"description\":\"...\",\"unit\":\"No\",\"quantity\":1,\"rate\":1000,\"amount\":1000,\"page\":2,\"needsReview\":false}],\"quotedTotal\":1000,\"currency\":\"TZS\",\"documentTitle\":\"...\"}",
      ].join("\n");

      let result;
      try {
        result = await callGemini(apiKey, pdfBytes, prompt);
      } catch (error) {
        fail("AI_EXTRACTION_FAILED", "internal", "The PDF was downloaded, but its quotation items could not be extracted.", {
          reason: error && error.message || "unknown",
        });
      }

      const items = normalizeItems(result.json);
      if (!items.length) {
        fail("NO_ITEMS_FOUND", "not-found", "No priced quotation line items were detected in the PDF.");
      }
      const itemizedTotal = items.reduce((sum, item) => sum + asNumber(item.amount), 0);
      const quotedTotal = asNumber(result.json.quotedTotal) || itemizedTotal;

      console.log("External quotation extracted", {
        projectId: String(request.data && request.data.projectId || ""),
        quotationId: String(request.data && request.data.quotationId || ""),
        pdfName: String(request.data && request.data.pdfName || ""),
        itemCount: items.length,
        itemizedTotal,
        quotedTotal,
        model: result.model,
      });

      return {
        items,
        quotedTotal,
        itemizedTotal,
        currency: String(result.json.currency || "").trim(),
        documentTitle: String(result.json.documentTitle || "").trim(),
        model: result.model,
      };
    },
);
