import { PAPERS, PRESETS, UNITS, paperById, fromUnit, fmtInput, fmtSize } from './units.js';
import { buildSheet, buildPoster } from './layout.js';
import { loadPhoto, releasePhoto } from './images.js';
import { drawPage, drawPoster, sizeCanvas } from './render.js';
import { makePdf, makeTestPage, testRulers } from './output.js';
import { initEditor, openEditor, isEditorOpen, redrawEditor } from './editor.js';

const $ = (id) => document.getElementById(id);
const STORE = 'print-sizing:settings:v1';

const DEFAULTS = {
  mode: 'sheet',
  unit: 'in',
  dpi: 300,
  calibration: {},
  sheet: {
    paper: 'a4',
    customW: 210,
    customH: 297,
    orientation: 'auto',
    sizing: 'count',
    perPage: 6,
    pieceW: 50.8,
    pieceH: 76.2,
    fitCount: 'fit',
    fitExact: 'fill',
    autoRotate: true,
    matchOrientation: true,
    margin: 5,
    gap: 3,
    guidesCount: 'none',
    guidesExact: 'outline',
    fillPage: false,
  },
  poster: {
    paper: 'a4',
    customW: 210,
    customH: 297,
    orientation: 'auto',
    sizeBy: 'grid',
    cols: 2,
    rows: 2,
    width: 600,
    height: 800,
    fill: false,
    margin: 6,
    overlap: 0,
    guides: true,
  },
};

// ---------- Settings ----------

function loadSettings() {
  const d = structuredClone(DEFAULTS);
  if (/^en-(US|CA)$/i.test(navigator.language || '')) d.sheet.paper = d.poster.paper = 'letter';
  let saved = {};
  try {
    saved = JSON.parse(localStorage.getItem(STORE)) || {};
  } catch {
    /* private mode or corrupt: use defaults */
  }
  return {
    ...d,
    ...saved,
    sheet: { ...d.sheet, ...saved.sheet },
    poster: { ...d.poster, ...saved.poster },
    calibration: { ...saved.calibration },
  };
}

const S = loadSettings();
const state = { photos: [], poster: null, plan: null, pdf: null, pdfUrl: null, shareFile: null };

function save() {
  try {
    localStorage.setItem(STORE, JSON.stringify(S));
  } catch {
    /* storage unavailable */
  }
}

const getPath = (path) => path.split('.').reduce((o, k) => (o == null ? o : o[k]), S);

function setPath(path, v) {
  const ks = path.split('.');
  const last = ks.pop();
  ks.reduce((o, k) => o[k], S)[last] = v;
}

function setSetting(path, value) {
  if (getPath(path) === value) return;
  setPath(path, value);
  save();
  changed();
}

function changed() {
  state.pdf = null;
  refreshControls();
  scheduleRender();
}

// ---------- Layout ----------

const sheetPaper = () => paperById(S.sheet.paper, S.sheet.customW, S.sheet.customH);
const posterPaper = () => paperById(S.poster.paper, S.poster.customW, S.poster.customH);
const currentPaper = () => (S.mode === 'sheet' ? sheetPaper() : posterPaper());
const exactMode = () => S.sheet.sizing === 'size';
const sheetFit = () => (exactMode() ? S.sheet.fitExact : S.sheet.fitCount);

function paperLabel(paper, orientation) {
  const name = paper.name === 'custom' ? fmtSize(paper.w, paper.h, S.unit) : paper.name;
  return orientation ? `${name} ${orientation}` : name;
}

function computePlan() {
  if (S.mode === 'sheet') {
    const s = S.sheet;
    state.plan = buildSheet({
      paper: sheetPaper(),
      orientation: s.orientation,
      margin: s.margin,
      gap: s.gap,
      sizing: s.sizing,
      perPage: s.perPage,
      pieceW: s.pieceW,
      pieceH: s.pieceH,
      fit: sheetFit(),
      autoRotate: s.autoRotate,
      matchOrientation: s.matchOrientation,
      guides: exactMode() ? s.guidesExact : s.guidesCount,
      fillPage: s.fillPage,
      photos: state.photos,
    });
  } else {
    state.plan = buildPoster({ ...S.poster, paper: posterPaper(), photo: state.poster });
  }
  return state.plan;
}

// ---------- Preview ----------

const pagesEl = $('pages');
let raf = 0;

function scheduleRender() {
  if (!raf)
    raf = requestAnimationFrame(() => {
      raf = 0;
      render();
    });
}

function render() {
  const plan = computePlan();
  renderPreview(plan);
  renderInfo(plan);
  if (isEditorOpen()) redrawEditor();
}

function pageCanvases(n) {
  while (pagesEl.children.length > n) pagesEl.lastChild.remove();
  while (pagesEl.children.length < n) {
    const wrap = document.createElement('div');
    wrap.className = 'page-wrap';
    wrap.appendChild(document.createElement('canvas'));
    pagesEl.appendChild(wrap);
  }
  return [...pagesEl.querySelectorAll('canvas')];
}

function renderPreview(plan) {
  const availW = pagesEl.clientWidth - 32;
  const availH = pagesEl.clientHeight - 16;
  if (availW <= 10 || availH <= 10) return;

  if (S.mode === 'poster') {
    if (plan.error) return void pageCanvases(0);
    const [canvas] = pageCanvases(1);
    const { cols, rows, sx, sy, tw, th } = plan.info;
    const gw = (cols - 1) * sx + tw;
    const gh = (rows - 1) * sy + th;
    const k = Math.min(availW / gw, availH / gh);
    const ctx = sizeCanvas(canvas, gw * k, gh * k);
    drawPoster(ctx, plan, state.poster, (k * canvas.width) / (gw * k));
    canvas._page = null;
    canvas._k = k;
    pagesEl.classList.add('single');
    $('pager').hidden = true;
    return;
  }

  const pages = plan.pages.slice(0, 40);
  const canvases = pageCanvases(pages.length);
  const several = pages.length > 1;
  pages.forEach((page, i) => {
    const k = Math.min((several ? availW * 0.86 : availW) / page.w, availH / page.h);
    const canvas = canvases[i];
    const ctx = sizeCanvas(canvas, page.w * k, page.h * k);
    drawPage(ctx, page, canvas.width / page.w);
    canvas._page = page;
    canvas._k = k;
  });
  pagesEl.classList.toggle('single', !several);
  updatePager();
}

function updatePager() {
  const n = state.plan?.pages?.length || 0;
  const pager = $('pager');
  if (S.mode !== 'sheet' || n < 2) {
    pager.hidden = true;
    return;
  }
  const mid = pagesEl.scrollLeft + pagesEl.clientWidth / 2;
  let idx = 0;
  let best = Infinity;
  [...pagesEl.children].forEach((el, i) => {
    const d = Math.abs(el.offsetLeft + el.offsetWidth / 2 - mid);
    if (d < best) [best, idx] = [d, i];
  });
  pager.hidden = false;
  pager.textContent = `Page ${idx + 1} of ${n}${n > 40 ? ' (first 40 shown)' : ''}`;
}

pagesEl.addEventListener('scroll', () => requestAnimationFrame(updatePager), { passive: true });

pagesEl.addEventListener('click', (e) => {
  const canvas = e.target.closest('canvas');
  if (!canvas) return;
  if (S.mode === 'poster') {
    if (state.poster) editPoster();
    else $('filePoster').click();
    return;
  }
  const page = canvas._page;
  if (!page) return;
  const r = canvas.getBoundingClientRect();
  const x = (e.clientX - r.left) / canvas._k;
  const y = (e.clientY - r.top) / canvas._k;
  const hit = page.items.find((it) => x >= it.x && x <= it.x + it.w && y >= it.y && y <= it.y + it.h);
  if (hit) editPhoto(hit.photo);
  else if (!state.photos.length) $('fileSheet').click();
});

function renderInfo(plan) {
  const cap = $('caption');
  const info = $('actionInfo');
  const btn = $('btnPrint');
  cap.classList.toggle('error', !!plan.error);

  if (plan.error) {
    cap.textContent = errorText(plan.error);
    info.textContent = '';
    btn.disabled = true;
    return;
  }

  const i = plan.info;
  const paper = paperLabel(currentPaper(), i.orientation);
  const n = plan.pages.length;

  if (S.mode === 'sheet') {
    const turned = plan.pages.some((p) => p.items.some((it) => it.rot));
    if (exactMode()) {
      cap.textContent = `${i.perPage} per page · each ${fmtSize(S.sheet.pieceW, S.sheet.pieceH, S.unit)}${turned ? ' · some turned to fit more' : ''}`;
    } else {
      const each = sheetFit() === 'fill' ? 'each' : 'each up to';
      cap.textContent = `${i.perPage} per page (${i.cols} × ${i.rows}) · ${each} ${fmtSize(i.slotW, i.slotH, S.unit)}`;
    }
    if (!state.photos.length) {
      info.innerHTML = 'Add photos to get started';
      btn.disabled = true;
      return;
    }
    info.innerHTML = `<b>${n} page${n === 1 ? '' : 's'}</b> · ${esc(paper)}<br>${i.photos} photo${i.photos === 1 ? '' : 's'}`;
  } else {
    cap.textContent = `Finished size ${fmtSize(i.posterW, i.posterH, S.unit)} · ${i.cols} across × ${i.rows} down`;
    if (!state.poster) {
      info.innerHTML = 'Choose an image to get started';
      btn.disabled = true;
      return;
    }
    info.innerHTML = `<b>${n} page${n === 1 ? '' : 's'}</b> · ${esc(paper)}`;
  }
  btn.disabled = false;
}

function errorText(err) {
  const paper = paperLabel(currentPaper());
  if (err.code === 'too-big')
    return `${fmtSize(S.sheet.pieceW, S.sheet.pieceH, S.unit)} won't fit on ${paper} with these margins (room for ${fmtSize(err.cw, err.ch, S.unit)}).`;
  if (err.code === 'too-many') return `That needs ${err.n} pages. Try a smaller size or bigger paper.`;
  return `The margins${S.mode === 'poster' && S.poster.overlap ? ' and overlap' : ''} are too big for ${paper}.`;
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

// ---------- Controls ----------

function matchShow(expr) {
  const [k, v] = expr.split('=');
  return String(getPath(k)) === v;
}

function refreshControls() {
  const active = document.activeElement;
  document.querySelectorAll('.seg[data-setting]').forEach((seg) => {
    const v = String(getPath(seg.dataset.setting));
    seg.querySelectorAll('button[data-value]').forEach((b) => {
      const on = b.dataset.value === v;
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', on);
    });
  });
  document.querySelectorAll('select[data-setting]').forEach((sel) => (sel.value = getPath(sel.dataset.setting)));
  document.querySelectorAll('input.switch[data-setting]').forEach((cb) => (cb.checked = !!getPath(cb.dataset.setting)));
  document.querySelectorAll('input[data-kind="length"]').forEach((inp) => {
    if (inp !== active) inp.value = fmtInput(getPath(inp.dataset.setting), S.unit);
  });
  document.querySelectorAll('.stepper[data-setting]').forEach((st) => {
    const inp = st.querySelector('input');
    if (inp !== active) inp.value = getPath(st.dataset.setting);
  });
  document.querySelectorAll('[data-chips]').forEach((box) => {
    const v = String(getPath(box.dataset.chips));
    box.querySelectorAll('.chip').forEach((c) => c.classList.toggle('on', c.dataset.value === v));
  });
  document.querySelectorAll('#presetChips .chip').forEach((c) => {
    const p = PRESETS[c.dataset.i];
    const same = (a, b) => Math.abs(a - b) < 0.05;
    const { pieceW: w, pieceH: h } = S.sheet;
    c.classList.toggle('on', (same(p.w, w) && same(p.h, h)) || (same(p.w, h) && same(p.h, w)));
  });
  document.querySelectorAll('.u').forEach((u) => (u.textContent = UNITS[S.unit].label));
  document.querySelectorAll('[data-show]').forEach((el) => (el.hidden = !matchShow(el.dataset.show)));

  $('btnClear').hidden = !state.photos.length;
  $('fitHint').textContent =
    sheetFit() === 'fill' ? 'Fills the space; edges may be cropped' : 'Keeps the whole photo; may leave white space';

  const pt = $('posterThumb');
  pt.hidden = !state.poster;
  $('btnPosterEdit').hidden = !state.poster;
  if (state.poster) pt.querySelector('img').src = state.poster.url;
  $('posterPickLabel').textContent = state.poster ? 'Choose a different image' : 'Choose image';
  refreshCalibration();
}

function stepper(el, get, set) {
  const input = el.querySelector('input');
  const min = Number(el.dataset.min || 1);
  const max = Number(el.dataset.max || 999);
  const apply = (v) => {
    const n = Math.min(max, Math.max(min, Math.round(v)));
    if (Number.isFinite(n)) set(n);
    input.value = get();
  };
  el.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-step]');
    if (b) apply(get() + Number(b.dataset.step));
  });
  input.addEventListener('change', () => apply(Number(input.value)));
}

function bindControls() {
  document.querySelectorAll('select.paper-select').forEach((sel) => {
    sel.innerHTML = PAPERS.map((p) => `<option value="${p.id}">${esc(p.name)}</option>`).join('');
  });

  document.querySelectorAll('.seg[data-setting]').forEach((seg) =>
    seg.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-value]');
      if (!b) return;
      const v = seg.dataset.kind === 'int' ? parseInt(b.dataset.value, 10) : b.dataset.value;
      setSetting(seg.dataset.setting, v);
    }),
  );
  document.querySelectorAll('select[data-setting]').forEach((sel) =>
    sel.addEventListener('change', () => setSetting(sel.dataset.setting, sel.value)),
  );
  document.querySelectorAll('input.switch[data-setting]').forEach((cb) =>
    cb.addEventListener('change', () => setSetting(cb.dataset.setting, cb.checked)),
  );
  document.querySelectorAll('input[data-kind="length"]').forEach((inp) => {
    const min = Number(inp.dataset.min || 0);
    inp.addEventListener('input', () => {
      const v = parseFloat(inp.value.replace(',', '.'));
      if (!Number.isFinite(v)) return;
      const mm = fromUnit(v, S.unit);
      if (mm >= min && mm <= 5000) setSetting(inp.dataset.setting, mm);
    });
    inp.addEventListener('blur', refreshControls);
    inp.addEventListener('keydown', (e) => e.key === 'Enter' && inp.blur());
  });
  document.querySelectorAll('.stepper[data-setting]').forEach((el) =>
    stepper(
      el,
      () => getPath(el.dataset.setting),
      (v) => setSetting(el.dataset.setting, v),
    ),
  );
  document.querySelectorAll('[data-chips]').forEach((box) => {
    box.innerHTML = box.dataset.values
      .split(',')
      .map((v) => `<button type="button" class="chip" data-value="${v}">${v}</button>`)
      .join('');
    box.addEventListener('click', (e) => {
      const c = e.target.closest('.chip');
      if (c) setSetting(box.dataset.chips, Number(c.dataset.value));
    });
  });

  const presets = $('presetChips');
  presets.innerHTML = PRESETS.map((p, i) => `<button type="button" class="chip" data-i="${i}">${esc(p.label)}</button>`).join('');
  presets.addEventListener('click', (e) => {
    const c = e.target.closest('.chip');
    if (!c) return;
    const p = PRESETS[c.dataset.i];
    S.sheet.pieceW = p.w;
    S.sheet.pieceH = p.h;
    save();
    changed();
  });
  $('btnSwap').addEventListener('click', () => {
    [S.sheet.pieceW, S.sheet.pieceH] = [S.sheet.pieceH, S.sheet.pieceW];
    save();
    changed();
  });
}

// ---------- Photos ----------

function renderThumbs() {
  const box = $('thumbs');
  box.querySelectorAll('.thumb:not(.add)').forEach((el) => el.remove());
  for (const p of state.photos) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'thumb';
    b.setAttribute('aria-label', `Edit ${p.name}`);
    const img = document.createElement('img');
    img.src = p.url;
    img.alt = '';
    img.style.transform = p.rot ? `rotate(${p.rot}deg)` : '';
    b.appendChild(img);
    if (p.copies > 1) {
      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = `×${p.copies}`;
      b.appendChild(badge);
    }
    b.addEventListener('click', () => editPhoto(p));
    box.appendChild(b);
  }
}

function photosChanged() {
  renderThumbs();
  changed();
}

async function addFiles(files, onEach) {
  let failed = 0;
  showBusy('Adding photos…');
  try {
    for (const [i, f] of files.entries()) {
      setBusy(files.length > 1 ? `Adding photo ${i + 1} of ${files.length}…` : 'Adding photo…');
      try {
        onEach(await loadPhoto(f, S.mode === 'poster' ? 1600 : 1024));
      } catch (err) {
        console.warn(err);
        failed++;
      }
    }
  } finally {
    hideBusy();
  }
  if (failed) toast(`${failed === files.length && failed === 1 ? 'That file' : `${failed} file${failed > 1 ? 's' : ''}`} couldn't be opened.`);
}

$('fileSheet').addEventListener('change', async (e) => {
  const files = [...e.target.files];
  e.target.value = '';
  if (!files.length) return;
  await addFiles(files, (p) => state.photos.push(p));
  photosChanged();
});

$('filePoster').addEventListener('change', async (e) => {
  const files = [...e.target.files].slice(0, 1);
  e.target.value = '';
  if (!files.length) return;
  await addFiles(files, (p) => {
    releasePhoto(state.poster);
    state.poster = p;
  });
  changed();
});

$('btnClear').addEventListener('click', () => {
  if (!confirm('Remove all photos?')) return;
  state.photos.forEach(releasePhoto);
  state.photos = [];
  photosChanged();
});

function layoutChanged() {
  state.pdf = null;
  computePlan();
  scheduleRender();
}

function editPhoto(photo) {
  openEditor({
    photo,
    title: 'Photo',
    allowCopies: true,
    getAspect: () => {
      if (sheetFit() !== 'fill') return null;
      for (const page of state.plan?.pages || [])
        for (const it of page.items) if (it.photo === photo) return it.rot ? it.h / it.w : it.w / it.h;
      return null;
    },
    noCropHint: 'The whole photo is printed. Choose “Fill & crop” under Layout to fill the space and pick the crop.',
    onChange: layoutChanged,
    onClose: renderThumbs,
    onRemove: () => {
      state.photos = state.photos.filter((p) => p !== photo);
      releasePhoto(photo);
      photosChanged();
    },
  });
}

function editPoster() {
  if (!state.poster) return;
  openEditor({
    photo: state.poster,
    title: 'Poster image',
    allowCopies: false,
    getAspect: () => {
      const i = state.plan?.info;
      return S.mode === 'poster' && S.poster.sizeBy === 'grid' && S.poster.fill && i ? i.posterW / i.posterH : null;
    },
    noCropHint: 'The whole image is printed. To crop, choose Pages and turn on “Fill every page”.',
    onChange: layoutChanged,
    onClose: refreshControls,
  });
}

$('posterThumb').addEventListener('click', editPoster);
$('btnPosterEdit').addEventListener('click', editPoster);

// ---------- Printing ----------

function pdfName(plan) {
  const paper = currentPaper();
  const p = paper.name === 'custom' ? 'custom' : paper.name.replace(/[^A-Za-z0-9]+/g, '');
  const stamp = new Date().toISOString().slice(0, 10);
  return S.mode === 'sheet' ? `photos-${p}-${stamp}.pdf` : `poster-${plan.info.cols}x${plan.info.rows}-${p}-${stamp}.pdf`;
}

$('btnPrint').addEventListener('click', async () => {
  const plan = state.plan || computePlan();
  if (plan.error || !plan.pages.length || !plan.pages[0].items.length) return;
  if (!state.pdf) {
    showBusy('Preparing PDF…');
    try {
      const paper = currentPaper();
      const blob = await makePdf(plan.pages, {
        dpi: S.dpi,
        correction: S.calibration[paper.id] || 1,
        title: S.mode === 'sheet' ? 'Photos' : 'Poster',
        onProgress: (d, t) => setBusy(t > 1 ? `Preparing images ${Math.min(d + 1, t)} of ${t}…` : 'Preparing PDF…'),
      });
      state.pdf = { blob, name: pdfName(plan), pages: plan.pages.length, paper: paperLabel(paper, plan.info.orientation) };
    } catch (err) {
      console.error(err);
      toast(`Couldn't make the PDF: ${err.message || err}`);
      return;
    } finally {
      hideBusy();
    }
  }
  showReady(state.pdf);
});

function fmtBytes(n) {
  return n > 1e6 ? `${(n / 1e6).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1e3))} KB`;
}

function showReady(pdf) {
  $('readyInfo').textContent = `${pdf.pages} page${pdf.pages === 1 ? '' : 's'} · ${pdf.paper} · ${fmtBytes(pdf.blob.size)}`;
  $('tipPaper').textContent = pdf.paper.replace(/ (portrait|landscape)$/, '');
  if (state.pdfUrl) URL.revokeObjectURL(state.pdfUrl);
  state.pdfUrl = URL.createObjectURL(pdf.blob);
  const link = $('lnkSave');
  link.href = state.pdfUrl;
  link.download = pdf.name;
  let file = null;
  try {
    file = new File([pdf.blob], pdf.name, { type: 'application/pdf' });
    if (!(navigator.canShare && navigator.canShare({ files: [file] }))) file = null;
  } catch {
    file = null;
  }
  state.shareFile = file;
  $('btnShare').textContent = file ? 'Print or share…' : 'Open PDF';
  $('dlgReady').showModal();
}

$('btnShare').addEventListener('click', async () => {
  if (state.shareFile) {
    try {
      await navigator.share({ files: [state.shareFile] });
      return;
    } catch (err) {
      if (err.name === 'AbortError') return;
      console.warn(err);
    }
  }
  window.open(state.pdfUrl, '_blank');
});

// ---------- Settings & calibration ----------

function refreshCalibration() {
  const paper = currentPaper();
  const k = S.calibration[paper.id] || 1;
  $('calPaper').textContent = paperLabel(paper);
  $('calValue').textContent = `${(k * 100).toFixed(1)}%`;
  const r = testRulers(Math.min(paper.w, paper.h));
  const inch = S.unit === 'in';
  $('calLabel').textContent = inch ? `Measured length of the ${r.inch} in line` : `Measured length of the ${r.mm} mm line`;
  $('calUnit').textContent = inch ? 'in' : 'mm';
  $('calInput').placeholder = inch ? String(r.inch) : String(r.mm);
}

$('btnSettings').addEventListener('click', () => {
  refreshCalibration();
  $('dlgSettings').showModal();
});

$('btnTestPage').addEventListener('click', () => {
  const paper = currentPaper();
  $('dlgSettings').close();
  const { blob } = makeTestPage(paper, S.calibration[paper.id] || 1);
  showReady({ blob, name: 'printer-size-check.pdf', pages: 1, paper: paperLabel(paper) });
});

$('btnCalApply').addEventListener('click', () => {
  const paper = currentPaper();
  const r = testRulers(Math.min(paper.w, paper.h));
  const inch = S.unit === 'in';
  const expected = inch ? r.inch : r.mm;
  const measured = parseFloat($('calInput').value.replace(',', '.'));
  if (!(measured > 0)) return toast('Type the length you measured first.');
  const next = ((S.calibration[paper.id] || 1) * expected) / measured;
  if (next < 0.8 || next > 1.25) return toast('That is more than 20% out. Check you measured the right line.');
  S.calibration[paper.id] = next;
  $('calInput').value = '';
  save();
  changed();
  toast(`Sizes on ${paperLabel(paper)} will be printed at ${(next * 100).toFixed(1)}%.`);
});

$('btnCalReset').addEventListener('click', () => {
  delete S.calibration[currentPaper().id];
  save();
  changed();
});

// ---------- Busy, toast, dialogs ----------

function showBusy(text) {
  $('busyText').textContent = text;
  $('busy').hidden = false;
}
function setBusy(text) {
  $('busyText').textContent = text;
}
function hideBusy() {
  $('busy').hidden = true;
}

let toastTimer = 0;
function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 3500);
}

document.querySelectorAll('dialog').forEach((dlg) => {
  dlg.addEventListener('click', (e) => {
    if (e.target === dlg || e.target.closest('[data-close]')) dlg.close();
  });
});

function setupInstallTip() {
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const standalone = navigator.standalone || matchMedia('(display-mode: standalone)').matches;
  let dismissed = false;
  try {
    dismissed = localStorage.getItem('print-sizing:install-tip') === '1';
  } catch {
    /* ignore */
  }
  if (!ios || standalone || dismissed) return;
  $('installTip').hidden = false;
  $('btnInstallTipClose').addEventListener('click', () => {
    $('installTip').hidden = true;
    try {
      localStorage.setItem('print-sizing:install-tip', '1');
    } catch {
      /* ignore */
    }
  });
}

// ---------- Start ----------

bindControls();
initEditor();
refreshControls();
render();
setupInstallTip();
new ResizeObserver(scheduleRender).observe(pagesEl);

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('./sw.js').catch((err) => console.warn('Service worker not registered', err));
}

// For automated tests.
window.__printSizing = { S, state, computePlan };
