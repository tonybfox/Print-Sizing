// Minimal PDF writer: pages with JPEG images, lines, rectangles and
// Helvetica text. Coordinates passed in are millimetres from the top-left.

const enc = new TextEncoder();
const PT = 72 / 25.4;
const n = (v) => (Math.abs(v) < 1e-9 ? '0' : String(Number(v.toFixed(3))));
const pdfString = (s) =>
  '(' +
  String(s)
    .replace(/[^\x20-\x7e]/g, '?')
    .replace(/[\\()]/g, (c) => '\\' + c) +
  ')';

export class PdfBuilder {
  constructor() {
    this.objs = [null];
    this.pageIds = [];
    this.catalogId = this.reserve();
    this.pagesId = this.reserve();
    this.fontId = this.reserve();
    this.set(this.fontId, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  }

  reserve() {
    this.objs.push(null);
    return this.objs.length - 1;
  }

  set(id, dict, stream = null) {
    this.objs[id] = { dict, stream };
  }

  /** Add a baseline JPEG (as produced by canvas.toBlob) and return its object id. */
  addJpeg(bytes, width, height) {
    const id = this.reserve();
    this.set(
      id,
      `<< /Type /XObject /Subtype /Image /Width ${width} /Height ${height} /ColorSpace /DeviceRGB ` +
        `/BitsPerComponent 8 /Filter /DCTDecode /Length ${bytes.length} >>`,
      bytes,
    );
    return id;
  }

  /** Start a page `w` × `h` mm. Draw on the returned PageWriter, then call end(). */
  page(w, h) {
    return new PageWriter(this, w, h);
  }

  build({ title = 'Print Sizing' } = {}) {
    this.set(this.catalogId, `<< /Type /Catalog /Pages ${this.pagesId} 0 R >>`);
    this.set(this.pagesId, `<< /Type /Pages /Kids [${this.pageIds.map((i) => `${i} 0 R`).join(' ')}] /Count ${this.pageIds.length} >>`);
    const infoId = this.reserve();
    this.set(infoId, `<< /Title ${pdfString(title)} /Producer (Print Sizing) /Creator (Print Sizing) >>`);

    const parts = [];
    let offset = 0;
    const push = (p) => {
      const bytes = typeof p === 'string' ? enc.encode(p) : p;
      parts.push(bytes);
      offset += bytes.length;
    };
    push('%PDF-1.4\n');
    push(new Uint8Array([0x25, 0xe2, 0xe3, 0xcf, 0xd3, 0x0a]));
    const offsets = [];
    for (let id = 1; id < this.objs.length; id++) {
      const o = this.objs[id];
      offsets[id] = offset;
      push(`${id} 0 obj\n${o.dict}\n`);
      if (o.stream) {
        push('stream\n');
        push(o.stream);
        push('\nendstream\n');
      }
      push('endobj\n');
    }
    const xref = offset;
    let table = `xref\n0 ${this.objs.length}\n0000000000 65535 f \n`;
    for (let id = 1; id < this.objs.length; id++) table += `${String(offsets[id]).padStart(10, '0')} 00000 n \n`;
    push(table);
    push(`trailer\n<< /Size ${this.objs.length} /Root ${this.catalogId} 0 R /Info ${infoId} 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
    return parts;
  }
}

class PageWriter {
  constructor(doc, w, h) {
    this.doc = doc;
    this.w = w;
    this.h = h;
    this.ops = [];
    this.images = new Map();
  }

  /** Scale everything about the page centre (printer size correction). */
  scaleAboutCentre(k) {
    if (Math.abs(k - 1) < 1e-6) return;
    const tx = ((1 - k) * this.w * PT) / 2;
    const ty = ((1 - k) * this.h * PT) / 2;
    this.ops.push(`${n(k)} 0 0 ${n(k)} ${n(tx)} ${n(ty)} cm`);
  }

  image(id, x, y, w, h) {
    const name = `Im${id}`;
    this.images.set(name, id);
    this.ops.push(`q ${n(w * PT)} 0 0 ${n(h * PT)} ${n(x * PT)} ${n((this.h - y - h) * PT)} cm /${name} Do Q`);
  }

  line(x1, y1, x2, y2, { lw = 0.2, gray = 0, dash = null } = {}) {
    const d = dash ? `[${dash.map((v) => n(v * PT)).join(' ')}] 0 d` : '[] 0 d';
    this.ops.push(
      `${n(gray)} G ${n(lw * PT)} w ${d} ${n(x1 * PT)} ${n((this.h - y1) * PT)} m ${n(x2 * PT)} ${n((this.h - y2) * PT)} l S`,
    );
  }

  rect(x, y, w, h, { lw = 0.2, gray = 0, fill } = {}) {
    const box = `${n(x * PT)} ${n((this.h - y - h) * PT)} ${n(w * PT)} ${n(h * PT)} re`;
    if (fill !== undefined) this.ops.push(`${n(fill)} g ${box} f`);
    this.ops.push(`${n(gray)} G ${n(lw * PT)} w [] 0 d ${box} S`);
  }

  /** Left-aligned text; y is the baseline. size in points. */
  text(x, y, str, { size = 8, gray = 0 } = {}) {
    this.ops.push(`BT /F1 ${n(size)} Tf ${n(gray)} g 1 0 0 1 ${n(x * PT)} ${n((this.h - y) * PT)} Tm ${pdfString(str)} Tj ET`);
  }

  end() {
    const content = enc.encode(`q\n${this.ops.join('\n')}\nQ\n`);
    const doc = this.doc;
    const cid = doc.reserve();
    doc.set(cid, `<< /Length ${content.length} >>`, content);
    const xo = [...this.images].map(([nm, id]) => `/${nm} ${id} 0 R`).join(' ');
    const pid = doc.reserve();
    doc.set(
      pid,
      `<< /Type /Page /Parent ${doc.pagesId} 0 R /MediaBox [0 0 ${n(this.w * PT)} ${n(this.h * PT)}] ` +
        `/Resources << /Font << /F1 ${doc.fontId} 0 R >> /XObject << ${xo} >> >> /Contents ${cid} 0 R >>`,
    );
    doc.pageIds.push(pid);
  }
}
