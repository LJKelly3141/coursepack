// Renders build/mockup/course.json. No framework, no CDN: the page must work
// offline. The DOM is built from the model so that drag-to-reorder can later
// mutate the model and serialize it back, rather than parsing markup.

const ICON = {
  WikiPage: '▤', ExternalUrl: '\u{1F517}',
  Assignment: '\u{1F4DD}', 'Quizzes::Quiz': '❑'
};
const el = (tag, cls, txt) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (txt != null) n.textContent = txt;
  return n;
};

// ---- notes state --------------------------------------------------------
// Deliberately in memory only. The server is python3 -m http.server, which
// speaks GET and HEAD and cannot accept a write, and build/mockup/ is wiped
// by build_preview.R on every run so a file there would not survive anyway.
// The review leaves as a clipboard payload instead.
const notes = new Map();   // key -> { text, module, item }
let MODEL = null;

const moduleKey = m => `m${m.position}`;
const itemKey = (m, it) => `m${m.position}i${it.position}`;

function setNote(key, text, module, item) {
  const t = text.trim();
  if (t) notes.set(key, { text: t, module, item });
  else notes.delete(key);
  refreshToolbar();
}

fetch('course.json')
  .then(r => r.json())
  .then(render)
  .catch(e => {
    document.getElementById('app').textContent =
      'Could not load course.json: ' + e + '. Run: make mockup';
  });

function render(j) {
  MODEL = j;
  const c = j.course, s = j.stats;

  const hdr = document.getElementById('hdr');
  const text = el('div', 'hdr-text');
  const h1 = el('h1', null, `${c.code}${c.section ? '-' + c.section : ''} · ${c.title}`);
  h1.appendChild(el('span', 'badge', c.base_mode));
  text.appendChild(h1);
  const stats = el('div', 'stats');
  stats.innerHTML =
    `<b>${s.modules}</b> modules · <b>${s.items}</b> items · ` +
    `<b>${s.unpublished_items}</b> unpublished · <b>${s.todo}</b> todo · ` +
    `<b>${s.broken}</b> broken targets · generated ${c.generated}`;
  text.appendChild(stats);
  hdr.appendChild(text);
  hdr.appendChild(themeButton());

  // Gate on textbook_present, NOT on s.unchecked. unchecked also counts items
  // with no chapter to check, so it is never zero and this banner would show on
  // every healthy build.
  if (c.textbook_present === false) {
    document.getElementById('banner').textContent =
      `The textbook is not built locally, so link targets could not be checked ` +
      `and previews will be empty. Render it, or run ` +
      `"make mockup MOCKUP_BASE=live" to preview the published site instead.`;
  }

  const app = document.getElementById('app');
  j.modules.forEach(m => app.appendChild(moduleCard(m)));

  buildToolbar();
  window.addEventListener('beforeunload', ev => {
    if (!notes.size) return;
    ev.preventDefault();          // notes are in memory only; a reload loses them
    ev.returnValue = '';
  });
}

// ---- theme --------------------------------------------------------------
// Three states: explicit dark, explicit light, and unset, which follows the OS.
// Only the explicit choice is persisted, so an unset page keeps tracking the OS.
function themeButton() {
  const btn = el('button', 'themebtn');
  const saved = localStorage.getItem('mockup-theme');
  if (saved) document.documentElement.setAttribute('data-theme', saved);

  const dark = () => {
    const set = document.documentElement.getAttribute('data-theme');
    if (set) return set === 'dark';
    return window.matchMedia('(prefers-color-scheme: dark)').matches;
  };
  const label = () => { btn.textContent = dark() ? '☀ Light' : '☾ Dark'; };
  label();

  btn.addEventListener('click', () => {
    const next = dark() ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('mockup-theme', next);
    label();
  });
  return btn;
}

function moduleCard(m) {
  const card = el('div', 'module');
  const head = el('div', 'mhead');
  const caret = el('span', 'caret', '▾');
  head.appendChild(caret);
  head.appendChild(el('span', null, `${m.position}. ${m.title}`));
  if (!m.published) head.appendChild(el('span', 'flag unpub', '⊘ unpublished'));
  head.appendChild(el('span', 'count', `${m.items.length} items`));

  const nbtn = noteButton();
  head.appendChild(nbtn);
  card.appendChild(head);

  const noteHost = el('div');
  card.appendChild(noteHost);
  wireNote(nbtn, noteHost, moduleKey(m),
           `Note on module ${m.position}: ${m.title}`, m, null, 'module-note');

  const ul = el('ul', 'items');
  m.items.forEach(it => ul.appendChild(itemRow(m, it)));
  card.appendChild(ul);

  head.addEventListener('click', () => {
    ul.classList.toggle('hidden');
    caret.textContent = ul.classList.contains('hidden') ? '▸' : '▾';
  });
  return card;
}

function itemRow(m, it) {
  const li = el('li');
  const row = el('div', 'row' + (it.form === 'header' ? ' header-row' : ''));

  row.appendChild(el('span', 'grip', '≡'));
  row.appendChild(el('span', 'icon', ICON[it.content_type] || ''));

  const title = el('span', 'title', it.title);
  title.style.paddingLeft = (it.indent * 22) + 'px';
  row.appendChild(title);

  if (it.points != null) row.appendChild(el('span', 'meta', it.points + ' pts'));
  if (!it.published)     row.appendChild(el('span', 'flag unpub', '⊘'));
  if (it.todo) {
    const f = el('span', 'flag todo', '⚑ todo');
    f.title = it.todo;
    row.appendChild(f);
  }
  if (it.target.state === 'missing-chapter' || it.target.state === 'missing-anchor') {
    row.appendChild(el('span', 'flag bad', it.target.detail));
  }

  const nbtn = noteButton();
  row.appendChild(nbtn);
  li.appendChild(row);

  wireNote(nbtn, li, itemKey(m, it),
           `Note on item ${it.position}: ${it.title}`, m, it, '');

  if (it.url) {
    row.classList.add('clickable');
    row.addEventListener('click', () => togglePreview(li, row, it));
  }
  return li;
}

// ---- note editors -------------------------------------------------------
function noteButton() {
  const b = el('button', 'notebtn', '✎');
  b.title = 'Add a note';
  return b;
}

// host is the element the editor is appended to. The button lives inside a
// clickable parent (a row toggles a preview, a module head collapses), so every
// handler here stops propagation or the click does two things at once.
function wireNote(btn, host, key, labelText, module, item, extraClass) {
  btn.addEventListener('click', ev => {
    ev.stopPropagation();
    const open = host.querySelector(':scope > .notebox');
    if (open) { open.remove(); return; }

    const box = el('div', 'notebox' + (extraClass ? ' ' + extraClass : ''));
    box.addEventListener('click', e => e.stopPropagation());
    box.appendChild(el('label', null, labelText));

    const ta = el('textarea');
    ta.placeholder = 'What is wrong here, or what should change?';
    const existing = notes.get(key);
    if (existing) ta.value = existing.text;
    ta.addEventListener('input', () => {
      setNote(key, ta.value, module, item);
      btn.classList.toggle('has-note', notes.has(key));
      btn.title = notes.has(key) ? 'Edit note' : 'Add a note';
    });
    box.appendChild(ta);
    host.appendChild(box);
    ta.focus();
  });
}

// ---- preview ------------------------------------------------------------
let openRow = null;
function togglePreview(li, row, it) {
  const existing = li.querySelector('.preview');
  if (existing) { existing.remove(); row.classList.remove('open'); openRow = null; return; }
  if (openRow) {
    const p = openRow.parentNode.querySelector('.preview');
    if (p) p.remove();
    openRow.classList.remove('open');
  }
  const box = el('div', 'preview');
  box.appendChild(el('div', 'src', it.url));
  const f = el('iframe');
  f.src = it.url;
  f.style.height = (it.frame && it.frame.height) ? it.frame.height : '720px';
  if (it.frame && it.frame.width && it.frame.width !== '100%') f.style.width = it.frame.width;
  box.appendChild(f);
  li.appendChild(box);
  row.classList.add('open');
  openRow = row;
}

// ---- the prompt ---------------------------------------------------------
// Walks the model in course order rather than the Map's insertion order, so the
// prompt reads top to bottom like the page regardless of the order notes were
// written in.
function composePrompt() {
  const c = MODEL.course, s = MODEL.stats;
  const out = [];
  out.push(`Fix these issues in the ${c.code}${c.section ? '-' + c.section : ''} course mockup.`);
  out.push('');
  out.push('Structure lives in modules.yml; content lives in the textbook repo.');
  out.push(`Snapshot: ${s.modules} modules, ${s.items} items, ${s.broken} broken ` +
           `targets, base=${c.base_mode}, generated ${c.generated}.`);
  out.push('');

  MODEL.modules.forEach(m => {
    const mNote = notes.get(moduleKey(m));
    const kids = m.items.filter(it => notes.has(itemKey(m, it)));
    if (!mNote && !kids.length) return;

    const state = m.published ? '' : ', unpublished';
    out.push(`## ${m.title}  (module ${m.position}${state})`);
    if (mNote) out.push(`> ${mNote.text.replace(/\n/g, '\n> ')}`);
    if (mNote && kids.length) out.push('');

    kids.forEach(it => {
      const bits = [it.content_type];
      if (it.points != null) bits.push(it.points + ' pts');
      if (!it.published) bits.push('unpublished');
      if (it.todo) bits.push('todo');
      out.push(`- **item ${it.position} · ${it.title}** (${bits.join(', ')})`);
      if (it.url) out.push(`  ${it.url}`);
      out.push(`  > ${notes.get(itemKey(m, it)).text.replace(/\n/g, '\n  > ')}`);
    });
    out.push('');
  });
  return out.join('\n');
}

function buildToolbar() {
  const bar = el('div');
  bar.id = 'toolbar';
  const said = el('span', 'said');
  said.style.display = 'none';
  const clear = el('button', null, 'Clear');
  const copy = el('button', 'primary');
  bar.appendChild(said); bar.appendChild(clear); bar.appendChild(copy);
  document.body.appendChild(bar);

  const flash = msg => {
    said.textContent = msg; said.style.display = '';
    setTimeout(() => { said.style.display = 'none'; }, 2600);
  };

  copy.addEventListener('click', () => {
    if (!notes.size) return;
    const text = composePrompt();
    writeClipboard(text)
      .then(() => flash(`Copied ${notes.size} note${notes.size === 1 ? '' : 's'}. Paste it in.`))
      .catch(() => flash('Copy failed. See the console for the text.') ||
                   console.log(text));
  });

  clear.addEventListener('click', () => {
    if (!notes.size) return;
    if (!confirm(`Discard ${notes.size} note${notes.size === 1 ? '' : 's'}? They are not saved anywhere.`)) return;
    notes.clear();
    document.querySelectorAll('.notebox').forEach(b => b.remove());
    document.querySelectorAll('.notebtn.has-note').forEach(b => b.classList.remove('has-note'));
    refreshToolbar();
  });

  refreshToolbar();
}

function refreshToolbar() {
  const bar = document.getElementById('toolbar');
  if (!bar) return;
  const [ , clear, copy] = bar.children;
  const n = notes.size;
  copy.textContent = n ? `Copy review prompt (${n})` : 'Copy review prompt';
  copy.disabled = !n;
  clear.disabled = !n;
}

// navigator.clipboard needs a secure context. http://localhost counts as one,
// so this works when served by `make mockup`. The fallback covers the case of
// someone opening the file some other way, where the modern API is absent.
function writeClipboard(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text);
  }
  return new Promise((resolve, reject) => {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    ok ? resolve() : reject(new Error('execCommand copy failed'));
  });
}
