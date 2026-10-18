export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // ---- CORS preflight ----
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(request) });
    }

    // Health
    if (url.pathname === "/" || url.pathname === "/health") {
      return withCors(new Response("OK"), request);
    }

    // -------- routes --------
    // GET/HEAD /files/<key>  -> public read
    if (url.pathname.startsWith("/files/")) {
      return handleFiles(request, env, url);
    }

    // PUT/DELETE /upload/<key> -> protected write
    if (url.pathname.startsWith("/upload/")) {
      return handleUpload(request, env, url);
    }

    return withCors(new Response("Not Found", { status: 404 }), request);
  },
};

// ====================== handlers ======================

async function handleFiles(request, env, url) {
  const bucket = env.FILES;
  if (!bucket) return withCors(new Response("R2 binding FILES not configured", { status: 500 }), request);

  const key = decodeKey(url.pathname, "/files/");
  if (!key) return withCors(new Response("Missing key", { status: 400 }), request);

  if (request.method !== "GET" && request.method !== "HEAD") {
    return withCors(new Response("Method Not Allowed", { status: 405 }), request);
  }

  const obj = await bucket.get(key);
  if (!obj) return withCors(new Response("Not Found", { status: 404 }), request);

  const headers = new Headers();
  // Let R2 write httpMetadata (content-type etc.) if present
  obj.writeHttpMetadata(headers);

  // Set safe defaults
  if (!headers.get("content-type")) {
    headers.set("content-type", guessContentType(key) || "application/octet-stream");
  }

  headers.set("etag", obj.httpEtag || obj.etag || "");
  headers.set("cache-control", "public, max-age=31536000, immutable");

  const ct = headers.get("content-type") || "";
  if (ct === "application/pdf" || ct.startsWith("image/")) {
    headers.set("content-disposition", "inline");
  }

  // HEAD -> no body
  if (request.method === "HEAD") {
    return withCors(new Response(null, { status: 200, headers }), request);
  }

  return withCors(new Response(obj.body, { status: 200, headers }), request);
}

async function handleUpload(request, env, url) {
  const bucket = env.FILES;
  if (!bucket) return withCors(new Response("R2 binding FILES not configured", { status: 500 }), request);

  // only PUT/DELETE
  if (request.method !== "PUT" && request.method !== "DELETE") {
    return withCors(new Response("Method Not Allowed", { status: 405 }), request);
  }

  // auth
  if (!(await isAuthorized(request, env))) {
    return withCors(new Response("Unauthorized", { status: 401 }), request);
  }

  const key = decodeKey(url.pathname, "/upload/");
  if (!key) return withCors(new Response("Missing key", { status: 400 }), request);

  if (request.method === "DELETE") {
    await bucket.delete(key);
    return withCors(json({ ok: true, deleted: key }), request);
  }

  // PUT upload
  const contentType =
    request.headers.get("content-type") || guessContentType(key) || "application/octet-stream";

  // optional size limit (50MB)
  const len = parseInt(request.headers.get("content-length") || "0", 10);
  const MAX = 50 * 1024 * 1024;
  if (len && len > MAX) {
    return withCors(new Response("File too large", { status: 413 }), request);
  }

  await bucket.put(key, request.body, {
    httpMetadata: { contentType },
    customMetadata: {
      uploadedAt: new Date().toISOString(),
    },
  });

  // IMPORTANT: don't encode slashes; build URL by encoding each path segment
  const publicUrl = `${url.origin}/files/${encodeKeyForUrl(key)}`;

  return withCors(
    json({
      ok: true,
      key,
      url: publicUrl,
      contentType,
    }),
    request
  );
}

// ====================== helpers ======================

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function corsHeaders(request) {
  const origin = request.headers.get("Origin") || "*";
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "GET,HEAD,PUT,DELETE,OPTIONS",
    "access-control-allow-headers": "Authorization, Content-Type, Range",
    "access-control-expose-headers": "etag, last-modified, content-length, content-type",
    "access-control-max-age": "86400",
    vary: "Origin",
  };
}

function withCors(response, request) {
  const headers = new Headers(response.headers);
  const ch = corsHeaders(request);
  for (const [k, v] of Object.entries(ch)) headers.set(k, v);
  return new Response(response.body, { status: response.status, headers });
}

async function isAuthorized(request, env) {
  const auth = request.headers.get("authorization") || request.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice("Bearer ".length).trim() : "";

  // Use UPLOAD_TOKEN (your secret)
  const secret = (env.UPLOAD_TOKEN || "").trim();
  if (!secret) return false;

  return token.length > 0 && token === secret;
}

function decodeKey(pathname, prefix) {
  const raw = pathname.slice(prefix.length);
  // remove leading slashes
  const cleaned = raw.replace(/^\/+/, "");
  if (!cleaned) return "";
  return decodeURIComponent(cleaned);
}

// Encode each segment so we keep "/" folders working
function encodeKeyForUrl(key) {
  return key
    .split("/")
    .map((seg) => encodeURIComponent(seg))
    .join("/");
}

function guessContentType(key) {
  const k = key.toLowerCase();
  if (k.endsWith(".pdf")) return "application/pdf";
  if (k.endsWith(".png")) return "image/png";
  if (k.endsWith(".jpg") || k.endsWith(".jpeg")) return "image/jpeg";
  if (k.endsWith(".webp")) return "image/webp";
  if (k.endsWith(".gif")) return "image/gif";
  return null;
}