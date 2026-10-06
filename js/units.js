// Paper sizes and unit handling. Everything inside the app is millimetres.

export const MM_PER_IN = 25.4;
export const PT_PER_MM = 72 / MM_PER_IN;

// Stored portrait (w <= h); orientation is applied by the layout.
export const PAPERS = [
  { id: 'a4', name: 'A4', w: 210, h: 297 },
  { id: 'letter', name: 'US Letter', w: 215.9, h: 279.4 },
  { id: '4x6', name: '6 × 4 in photo', w: 101.6, h: 152.4 },
  { id: '5x7', name: '7 × 5 in photo', w: 127, h: 177.8 },
  { id: '10x15', name: '15 × 10 cm photo', w: 100, h: 150 },
  { id: '13x18', name: '18 × 13 cm photo', w: 130, h: 180 },
  { id: '8x10', name: '10 × 8 in', w: 203.2, h: 254 },
  { id: 'a5', name: 'A5', w: 148, h: 210 },
  { id: 'a6', name: 'A6', w: 105, h: 148 },
  { id: 'a3', name: 'A3', w: 297, h: 420 },
  { id: 'legal', name: 'US Legal', w: 215.9, h: 355.6 },
  { id: 'custom', name: 'Custom size…' },
];

export function paperById(id, customW = 210, customH = 297) {
  if (id === 'custom') {
    const w = Math.max(10, Math.min(customW, customH) || 10);
    const h = Math.max(10, Math.max(customW, customH) || 10);
    return { id: `custom-${w.toFixed(1)}x${h.toFixed(1)}`, name: 'custom', w, h };
  }
  return PAPERS.find((p) => p.id === id) || PAPERS[0];
}

export const UNITS = {
  in: { label: 'in', factor: MM_PER_IN, digits: 2 },
  cm: { label: 'cm', factor: 10, digits: 1 },
  mm: { label: 'mm', factor: 1, digits: 0 },
};

export const toUnit = (mm, u) => mm / UNITS[u].factor;
export const fromUnit = (v, u) => v * UNITS[u].factor;

/** Number with at most `digits` decimals and no trailing zeros. */
export const fmtNum = (v, digits) => String(Number(v.toFixed(digits)));

export const fmtLen = (mm, u, extraDigits = 0) => fmtNum(toUnit(mm, u), UNITS[u].digits + extraDigits);

export const fmtSize = (w, h, u) => `${fmtLen(w, u)} × ${fmtLen(h, u)} ${UNITS[u].label}`;

// Decimals shown in editable fields: enough to round-trip common sizes
// (5.08 cm, 50.8 mm, 1.38 in) without noise like 0.197 in.
const INPUT_DIGITS = { in: 2, cm: 2, mm: 1 };
export const fmtInput = (mm, u) => fmtNum(toUnit(mm, u), INPUT_DIGITS[u]);

// Common sizes for cut-out prints. w/h in mm.
export const PRESETS = [
  { label: '2 × 3 in', w: 50.8, h: 76.2 },
  { label: '2 × 2 in', w: 50.8, h: 50.8 },
  { label: '2.5 × 3.5 in', w: 63.5, h: 88.9 },
  { label: '3 × 4 in', w: 76.2, h: 101.6 },
  { label: '3.5 × 5 in', w: 88.9, h: 127 },
  { label: '4 × 6 in', w: 101.6, h: 152.4 },
  { label: '5 × 7 in', w: 127, h: 177.8 },
  { label: '35 × 45 mm (passport)', w: 35, h: 45 },
  { label: '5 × 5 cm', w: 50, h: 50 },
];
