function decodeBase64Pdf(base64Pdf) {
  const raw = atob(base64Pdf);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

async function pdfPageCount(base64Pdf) {
  const pdfjs = window.pdfjsLib;
  if (!pdfjs) throw new Error("pdf.js is not loaded yet");
  const loadingTask = pdfjs.getDocument({ data: decodeBase64Pdf(base64Pdf) });
  const pdf = await loadingTask.promise;
  return String(pdf.numPages || 1);
}

async function pdfPageToPngDataUrl(base64Pdf, pageNumber, scale) {
  const pdfjs = window.pdfjsLib;
  if (!pdfjs) throw new Error("pdf.js is not loaded yet");
  const loadingTask = pdfjs.getDocument({ data: decodeBase64Pdf(base64Pdf) });
  const pdf = await loadingTask.promise;

  const requestedPage = Number(pageNumber || 1);
  const safePage = Math.max(1, Math.min(pdf.numPages || 1, requestedPage));
  const page = await pdf.getPage(safePage);
  const baseViewport = page.getViewport({ scale: 1 });
  const requestedScale = scale || 3.5;

  // Engineering sheets need substantially more detail than a thumbnail.
  // Keep the longest edge around 7,500 px while avoiding oversized canvases.
  const maxCanvasEdge = 7500;
  const longestBaseEdge = Math.max(baseViewport.width, baseViewport.height);
  const safeScale = Math.min(
    requestedScale,
    maxCanvasEdge / Math.max(longestBaseEdge, 1),
  );
  const viewport = page.getViewport({ scale: Math.max(safeScale, 0.2) });

  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d", { alpha: false });

  canvas.width = Math.floor(viewport.width);
  canvas.height = Math.floor(viewport.height);

  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  await page.render({
    canvasContext: ctx,
    viewport,
    background: "rgb(255,255,255)",
  }).promise;

  return canvas.toDataURL("image/png");
}

async function pdfFirstPageToPngDataUrl(base64Pdf, scale) {
  return pdfPageToPngDataUrl(base64Pdf, 1, scale);
}
