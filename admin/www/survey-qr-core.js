import { qrcodegen } from './qrcodegen-v1.8.0.js';

export const SURVEY_URL = 'https://investigadoresloyola.eu.qualtrics.com/jfe/form/SV_cw4cVf23LI4rJzg';
export const QR_BORDER = 4;

// Rejection sampling keeps all six-digit codes equally likely. These are group
// labels, not passwords or globally unique identifiers.
export function generateClassCode(previous = '', random = (values) => globalThis.crypto.getRandomValues(values)) {
  const range = 900000;
  const limit = Math.floor(2 ** 32 / range) * range;
  const values = new Uint32Array(1);
  for (let attempt = 0; attempt < 128; attempt++) {
    random(values);
    if (values[0] >= limit) continue;
    const code = String(100000 + values[0] % range);
    if (code !== previous) return code;
  }
  throw new Error('Could not generate a new class code.');
}

export function createSurveyInvite(previous = '', random) {
  const code = generateClassCode(previous, random);
  const url = new URL(SURVEY_URL);
  url.searchParams.set('Treatment_choice', code);
  return Object.freeze({ code, url: url.href,
    qr: qrcodegen.QrCode.encodeText(url.href, qrcodegen.QrCode.Ecc.QUARTILE) });
}

export function qrSvgMarkup(qr) {
  const side = qr.size + QR_BORDER * 2;
  const cells = [];
  for (let y = 0; y < qr.size; y++) {
    for (let x = 0; x < qr.size; x++) {
      if (qr.getModule(x, y)) cells.push(`M${x + QR_BORDER},${y + QR_BORDER}h1v1h-1z`);
    }
  }
  // Only numeric module coordinates enter this SVG; no URL or input is inserted.
  return `<svg xmlns="http://www.w3.org/2000/svg" role="img" aria-label="QR code for the class survey" viewBox="0 0 ${side} ${side}" shape-rendering="crispEdges"><rect width="${side}" height="${side}" fill="#fff"/><path d="${cells.join('')}" fill="#000"/></svg>`;
}
