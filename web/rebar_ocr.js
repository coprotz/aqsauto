(function () {
  function loadImage(url) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      image.crossOrigin = 'anonymous';
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error('The captured drawing could not be loaded for OCR.'));
      image.src = url;
    });
  }

  function normaliseRebarText(value) {
    return value
      .toUpperCase()
      .replace(/[\u2010-\u2015]/g, '-')
      .replace(/[OQD]/g, '0')
      .replace(/[IL|]/g, '1')
      .replace(/\s+/g, '')
      .replace(/[^0-9YRTB\-]/g, '')
      .replace(/^(\d+)T(\d+)/, '$1Y$2');
  }

  function validRebarMark(value) {
    const text = normaliseRebarText(value);
    const matches = text.match(/\d{1,3}[YR]\d{1,2}-\d{1,3}-\d{2,4}(?:[TB]\d+)?/g) || [];
    for (const candidate of matches) {
      const parsed = candidate.match(/^(\d+)[YR](\d+)-(\d+)-(\d+)(?:[TB]\d+)?$/);
      if (!parsed) continue;
      const quantity = Number(parsed[1]);
      const diameter = Number(parsed[2]);
      const spacing = Number(parsed[4]);
      if (
        quantity >= 1 && quantity <= 999 &&
        diameter >= 6 && diameter <= 50 &&
        spacing >= 50 && spacing <= 1000
      ) {
        return candidate;
      }
    }
    return '';
  }

  function copyCanvas(source) {
    const copy = document.createElement('canvas');
    copy.width = source.width;
    copy.height = source.height;
    copy.getContext('2d').drawImage(source, 0, 0);
    return copy;
  }

  function thresholdCanvas(source, threshold) {
    const copy = copyCanvas(source);
    const context = copy.getContext('2d', { willReadFrequently: true });
    const pixels = context.getImageData(0, 0, copy.width, copy.height);
    for (let index = 0; index < pixels.data.length; index += 4) {
      const value = pixels.data[index] < threshold ? 0 : 255;
      pixels.data[index] = value;
      pixels.data[index + 1] = value;
      pixels.data[index + 2] = value;
    }
    context.putImageData(pixels, 0, 0);
    return copy;
  }

  window.recognizeRebarMark = async function (
    imageUrl,
    minX,
    minY,
    maxX,
    maxY,
    drawingWidth,
    drawingHeight
  ) {
    if (!window.Tesseract) {
      throw new Error('Browser OCR is not available.');
    }

    const image = await loadImage(imageUrl);
    const coordinateWidth = drawingWidth > 0 ? drawingWidth : image.naturalWidth;
    const coordinateHeight = drawingHeight > 0 ? drawingHeight : image.naturalHeight;
    const sx = image.naturalWidth / coordinateWidth;
    const sy = image.naturalHeight / coordinateHeight;
    const cropWidth = Math.max(1, (maxX - minX) * sx);
    const cropHeight = Math.max(1, (maxY - minY) * sy);
    const paddingX = cropWidth * 0.08;
    const paddingY = cropHeight * 0.22;
    const sourceX = Math.max(0, minX * sx - paddingX);
    const sourceY = Math.max(0, minY * sy - paddingY);
    const sourceWidth = Math.min(image.naturalWidth - sourceX, cropWidth + paddingX * 2);
    const sourceHeight = Math.min(image.naturalHeight - sourceY, cropHeight + paddingY * 2);

    const upscale = 4;
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(320, Math.round(sourceWidth * upscale));
    canvas.height = Math.max(96, Math.round(sourceHeight * upscale));
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = 'high';
    context.filter = 'grayscale(1) contrast(2.4)';
    context.drawImage(
      image,
      sourceX,
      sourceY,
      sourceWidth,
      sourceHeight,
      0,
      0,
      canvas.width,
      canvas.height
    );

    // Keep an untouched enhanced crop. Engineering annotations are frequently
    // crossed by grid or rebar lines, and no single cleanup works for every
    // drawing. OCR several variants and accept only a complete, plausible mark.
    const enhancedCanvas = copyCanvas(canvas);

    // Bar marks often sit underneath grid/rebar lines. Remove only lines that
    // run through almost the full crop so character strokes remain intact.
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height);
    const data = pixels.data;
    const verticalLines = [];
    const horizontalLines = [];
    for (let x = 0; x < canvas.width; x += 1) {
      let dark = 0;
      for (let y = 0; y < canvas.height; y += 1) {
        if (data[(y * canvas.width + x) * 4] < 80) dark += 1;
      }
      if (dark / canvas.height > 0.82) verticalLines.push(x);
    }
    for (let y = 0; y < canvas.height; y += 1) {
      let dark = 0;
      for (let x = 0; x < canvas.width; x += 1) {
        if (data[(y * canvas.width + x) * 4] < 80) dark += 1;
      }
      if (dark / canvas.width > 0.82) horizontalLines.push(y);
    }
    function whiten(x, y) {
      if (x < 0 || y < 0 || x >= canvas.width || y >= canvas.height) return;
      const index = (y * canvas.width + x) * 4;
      data[index] = 255;
      data[index + 1] = 255;
      data[index + 2] = 255;
      data[index + 3] = 255;
    }
    verticalLines.forEach((lineX) => {
      for (let y = 0; y < canvas.height; y += 1) {
        for (let offset = -2; offset <= 2; offset += 1) whiten(lineX + offset, y);
      }
    });
    horizontalLines.forEach((lineY) => {
      for (let x = 0; x < canvas.width; x += 1) {
        for (let offset = -2; offset <= 2; offset += 1) whiten(x, lineY + offset);
      }
    });
    context.putImageData(pixels, 0, 0);

    const worker = await window.Tesseract.createWorker('eng', 1, {
      logger: function () {},
    });
    const variants = [
      { image: enhancedCanvas, mode: '7' },
      { image: thresholdCanvas(enhancedCanvas, 150), mode: '7' },
      { image: canvas, mode: '7' },
      { image: thresholdCanvas(canvas, 175), mode: '13' },
    ];
    const readings = [];
    try {
      for (const variant of variants) {
        await worker.setParameters({
          tessedit_pageseg_mode: variant.mode,
          tessedit_char_whitelist: '0123456789YRTB-',
          preserve_interword_spaces: '0',
        });
        const result = await worker.recognize(variant.image);
        const raw = result && result.data ? result.data.text || '' : '';
        readings.push(raw);
        const valid = validRebarMark(raw);
        if (valid) return valid;
      }
    } finally {
      await worker.terminate();
    }

    // Do not return a partial OCR fragment such as `12-201`: it can produce a
    // materially wrong take-off. The Flutter form remains editable for review.
    return '';
  };
})();
