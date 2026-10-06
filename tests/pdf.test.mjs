import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { PdfBuilder } from '../js/pdf.js';

const concat = (parts) => Buffer.concat(parts.map((p) => Buffer.from(p)));

test('xref offsets point at their objects', () => {
  const doc = new PdfBuilder();
  const jpg = new Uint8Array(readFileSync(new URL('./fixture.jpg', import.meta.url)));
  const img = doc.addJpeg(jpg, 40, 20);
  const p = doc.page(210, 297);
  p.image(img, 10, 10, 80, 40);
  p.line(0, 0, 210, 297, { dash: [1, 1] });
  p.rect(5, 5, 20, 20, { fill: 0.5 });
  p.text(10, 200, 'Hello (world) \\ ok', { size: 9 });
  p.end();
  const buf = concat(doc.build({ title: 'Test' }));
  const s = buf.toString('latin1');
  const start = Number(s.match(/startxref\n(\d+)/)[1]);
  assert.ok(s.slice(start).startsWith('xref'));
  const entries = [...s.slice(start).matchAll(/(\d{10}) 00000 n /g)].map((m) => Number(m[1]));
  entries.forEach((off, i) => assert.ok(s.slice(off).startsWith(`${i + 1} 0 obj`), `object ${i + 1}`));

  // Cross-check with poppler when available.
  try {
    const dir = mkdtempSync(join(tmpdir(), 'pdft-'));
    const f = join(dir, 't.pdf');
    writeFileSync(f, buf);
    const info = execFileSync('pdfinfo', [f], { encoding: 'utf8' });
    assert.match(info, /Pages:\s+1/);
    assert.match(info, /Page size:\s+595\.2\d* x 841\.\d+ pts \(A4\)/);
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
});
