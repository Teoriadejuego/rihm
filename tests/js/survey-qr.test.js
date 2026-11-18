import { describe, it, expect } from 'vitest';
import { createSurveyInvite, generateClassCode, qrSvgMarkup, SURVEY_URL } from '../../admin/www/survey-qr-core.js';

const sequence = (...values) => {
  let index = 0;
  return (buffer) => { buffer[0] = values[index++ % values.length]; };
};

describe('teacher survey invitations', () => {
  it('generates six digits without a leading zero at both range boundaries', () => {
    expect(generateClassCode('', sequence(0))).toBe('100000');
    expect(generateClassCode('', sequence(899999))).toBe('999999');
  });

  it('rejects biased samples and never reissues the current code', () => {
    expect(generateClassCode('100000', sequence(0xFFFFFFFF, 0, 1))).toBe('100001');
    expect(() => generateClassCode('100000', sequence(0))).toThrow('Could not generate');
  });

  it('encodes exactly the requested survey and case-sensitive embedded field', () => {
    const invite = createSurveyInvite('', sequence(234567));
    expect(invite.code).toBe('334567');
    expect(invite.url).toBe(`${SURVEY_URL}?Treatment_choice=334567`);
    const url = new URL(invite.url);
    expect([...url.searchParams.keys()]).toEqual(['Treatment_choice']);
    expect(invite.qr.size).toBeGreaterThanOrEqual(21);
    expect(invite.qr.errorCorrectionLevel.ordinal).toBeGreaterThanOrEqual(2);
  });

  it('renders a white four-module quiet zone with black modules and an accessible label', () => {
    const qr = { size: 21, getModule: (x, y) => x === 0 && y === 0 };
    const svg = qrSvgMarkup(qr);
    expect(svg).toContain('viewBox="0 0 29 29"');
    expect(svg).toContain('role="img"');
    expect(svg).toContain('fill="#fff"');
    expect(svg).toContain('d="M4,4h1v1h-1z" fill="#000"');
    expect(svg).not.toMatch(/https?:\/\/(?!www\.w3\.org)/);
  });

  it('produces real random codes rather than a fixed demonstration value', () => {
    const codes = Array.from({ length: 20 }, () => generateClassCode());
    expect(codes.every(code => /^[1-9][0-9]{5}$/.test(code))).toBe(true);
    expect(new Set(codes).size).toBeGreaterThan(1);
  });
});
