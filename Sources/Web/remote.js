/* Surface de commande — logique.
   Le Mac fait le son ; cette page ne fait qu'afficher et commander.

   Deux flux, comme côté serveur :
     • un EventSource sur /api/stream pour tout ce qui bouge (spectre,
       niveaux, notes tenues) — une seule connexion, à la cadence de
       l'application ;
     • /api/state, relu seulement quand le numéro de révision change.
   Si le flux ne s'établit pas, on se rabat sur l'interrogation périodique :
   moins fluide, mais tout fonctionne. */

'use strict';

const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];

let KEY = new URLSearchParams(location.search).get('k')
       || localStorage.getItem('plsKey') || '';
let L = {};               // instantané rapide
let S = {};               // état lent (sons, égaliseur, prises)
let library = [];
let query = '';
/* Familles refermées, par leur nom. Cinquante sons dans une colonne de
   tablette, c'est du défilement ; repliées, c'est un sommaire. */
let shutFams = new Set();
let tab = localStorage.getItem('plsTab') || 'play';
let grabbed = {};         // curseurs en cours de manipulation
let es = null, polling = null, watchdog = 0, streamFails = 0;

/* ── Onglets ────────────────────────────────────────────────────────── */

const I = {
  play:  '<path d="M5 3.8v12.4a1 1 0 0 0 1.5.9l10-6.2a1 1 0 0 0 0-1.7l-10-6.2A1 1 0 0 0 5 3.8z"/>',
  eq:    '<path d="M3 15c2.5 0 3-9 5.5-9S11 15 13.5 15 16 9 18.5 9"/><path d="M3 18h15"/>',
  chords:'<circle cx="6" cy="15" r="2.4"/><circle cx="14" cy="13" r="2.4"/><path d="M8.4 15V5l8 -1.6v9.6"/>',
  keys:  '<rect x="2.5" y="4" width="16" height="13" rx="1.6"/><path d="M7 4v8M12 4v8M16 4v8"/>',
  rec:   '<circle cx="10.5" cy="10.5" r="7"/><circle cx="10.5" cy="10.5" r="3" fill="currentColor"/>',
  info:  '<circle cx="10.5" cy="10.5" r="7.5"/><path d="M10.5 9.5v5"/><path d="M10.5 6.6v.9"/>',
};
const TABS = [
  ['play', 'Jeu'], ['eq', 'Égaliseur'], ['chords', 'Accords'],
  ['keys', 'Clavier'], ['rec', 'Prise'], ['info', 'Infos'],
];

function icon(name) {
  return '<svg viewBox="0 0 21 21" fill="none" stroke="currentColor" stroke-width="1.6"'
       + ' stroke-linecap="round" stroke-linejoin="round">' + I[name] + '</svg>';
}

function buildNav() {
  const fill = (host, withLabel) => {
    host.innerHTML = '';
    for (const [id, label] of TABS) {
      const b = document.createElement('button');
      b.dataset.tab = id;
      b.innerHTML = icon(id) + (withLabel ? '<span>' + label + '</span>' : '');
      b.onclick = () => show(id);
      host.appendChild(b);
    }
  };
  fill($('#tabs'), true);
  fill($('#railnav'), true);
}

function show(id) {
  tab = id;
  localStorage.setItem('plsTab', id);
  document.body.dataset.tab = id;
  for (const [t] of TABS) $('#s-' + t).classList.toggle('hide', t !== id);
  $$('#tabs button, #railnav button').forEach(b =>
    b.classList.toggle('on', b.dataset.tab === id));
  fillAll();
  // Les deux canevas se redimensionnent quand l'écran s'affiche : un canevas
  // caché mesure zéro, et garderait la taille qu'il avait avant.
  if (id === 'eq') requestAnimationFrame(() => { paintEQ(); paintMic(); });
}

/* ── Clé d'accès ────────────────────────────────────────────────────── */

function gate(show, msg) {
  $('#gate').classList.toggle('show', show);
  if (msg !== undefined) $('#gerr').textContent = msg;
  if (show) setTimeout(() => $('#key').focus(), 120);
}

function useKey() {
  const v = $('#key').value.trim().toUpperCase();
  if (v.length < 4) { $('#gerr').textContent = 'Clé trop courte'; return; }
  KEY = v;
  localStorage.setItem('plsKey', v);
  gate(false, '');
  start();
}

/* ── Appels ─────────────────────────────────────────────────────────── */

function url(path) {
  return path + (path.includes('?') ? '&' : '?') + 'k=' + encodeURIComponent(KEY);
}

async function api(path, opts) {
  const r = await fetch(url(path), opts);
  if (r.status === 403) {
    localStorage.removeItem('plsKey');
    stop();
    gate(true, 'Clé refusée');
    throw new Error('403');
  }
  return r;
}

async function cmd(action, extra) {
  try {
    await api('/api/cmd', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(Object.assign({ action }, extra || {})),
    });
    if (navigator.vibrate) navigator.vibrate(7);
  } catch (e) { /* le flux rétablira l'état réel */ }
}

/* Pendant un glissement, on n'envoie qu'une commande toutes les 70 à 80 ms :
   le doigt bouge plus vite que ce qu'il est utile de transmettre. */
const lastSent = {};
function throttle(id, ms, fn) {
  const now = performance.now();
  if (now - (lastSent[id] || 0) < ms) return;
  lastSent[id] = now;
  fn();
}
function cmdThrottled(action, extra, ms) {
  throttle(action + JSON.stringify(extra.index ?? ''), ms || 80, () => cmd(action, extra));
}

/* ── Transport ──────────────────────────────────────────────────────── */

function setDot(mode) {
  const d = $('#dot');
  d.classList.toggle('live', mode === 'live');
  d.classList.toggle('poll', mode === 'poll');
  $('#off').classList.toggle('show', mode === 'off');
  $('#i-link').textContent = mode === 'live' ? 'flux temps réel'
    : mode === 'poll' ? 'interrogation périodique' : 'interrompue';
}

function alive() {
  clearTimeout(watchdog);
  watchdog = setTimeout(() => setDot('off'), 2600);
}

function openStream() {
  if (!window.EventSource) { startPolling(); return; }
  es = new EventSource(url('/api/stream'));
  es.onopen = () => { streamFails = 0; setDot('live'); };
  es.onmessage = e => {
    streamFails = 0;
    setDot('live');
    alive();
    try { applyLive(JSON.parse(e.data)); } catch (err) {}
  };
  es.onerror = () => {
    // Le navigateur réessaie seul ; après plusieurs échecs on change de
    // méthode plutôt que de laisser la page muette.
    if (++streamFails >= 3) { es.close(); es = null; startPolling(); }
    else setDot('off');
  };
}

function startPolling() {
  if (polling) return;
  setDot('poll');
  const beat = async () => {
    try {
      applyLive(await (await api('/api/live')).json());
      setDot('poll');
      alive();
    } catch (e) { if (e.message !== '403') setDot('off'); }
  };
  beat();
  polling = setInterval(beat, 180);
}

function stop() {
  if (es) { es.close(); es = null; }
  if (polling) { clearInterval(polling); polling = null; }
  clearTimeout(watchdog);
}

async function loadLibrary() {
  library = await (await api('/api/library')).json();
  drawPresets();
}

async function loadState() {
  S = await (await api('/api/state')).json();
  renderState();
}

async function start() {
  try {
    await loadState();
    await loadLibrary();
  } catch (e) {
    if (e.message === '403') return;
    setDot('off');
    setTimeout(start, 2000);
    return;
  }
  stop();
  openStream();
}

/* ── Arrivée d'un instantané rapide ─────────────────────────────────── */

function applyLive(s) {
  L = s;
  const busy = grabbed.eqhandle || grabbed.bgain || grabbed.bfreq || grabbed.bq;
  if (S.rev !== undefined && s.rev !== S.rev && !busy) loadState().catch(() => {});
  renderLive();
}

/* ── Rendu : barre du haut ──────────────────────────────────────────── */

const db2pct = db => Math.max(0, Math.min(100, (((db ?? -60) + 54) / 54) * 100));

function meter(el, hold, db, holdDB) {
  el.style.width = db2pct(db) + '%';
  const box = el.parentElement;
  box.classList.toggle('hot', db > -1.5);
  box.classList.toggle('warm', db <= -1.5 && db > -8);
  hold.style.left = db2pct(holdDB) + '%';
  hold.style.opacity = holdDB > -53 ? .75 : 0;
}

function renderLive() {
  const t = (L.transpose || 0) + (L.octave || 0) * 12;

  $('#hchord').textContent = L.chord || '—';
  $('#hheld').textContent = L.held ? L.held + ' note' + (L.held > 1 ? 's' : '') : '—';
  meter($('#mL'), $('#hL'), L.peakL, L.holdL);
  meter($('#mR'), $('#hR'), L.peakR, L.holdR);
  const top = Math.max(L.peakL ?? -60, L.peakR ?? -60);
  $('#dbtext').textContent = top > -53 ? Math.round(top) + ' dB' : '—';

  $('#nokb').classList.toggle('hide', !!L.hasKeyboard);

  $('#tval').textContent = t > 0 ? '+' + t : '' + t;
  $('#tval').classList.toggle('on', t !== 0);
  $('#tzero').classList.toggle('on', t !== 0);

  fader('master', L.master, v => Math.round(v * 100) + ' %');
  fader('layer', L.layerMix, v => Math.round(v * 100) + ' %', !S.hasLayer);

  // Le son choisi change : la case et la pastille de sa famille suivent.
  drawPresets();

  // Accords
  const hasChord = L.chord && L.chord !== '—';
  $('#bigchord').textContent = L.chord || '—';
  $('#bigchord').style.color = hasChord ? 'var(--accent)' : 'var(--t2)';
  $('#bigq').textContent = L.chordQuality
    || (hasChord ? '' : 'jouez trois notes ou plus');
  $('#bigdeg').textContent = L.chordDegrees || '';
  $('#bignotes').textContent = L.chordNotes || '';
  $('#kchord').textContent = L.chord || '—';
  $('#kq').textContent = L.chordQuality || '—';
  const h = $('#history');
  const want = (L.history || []).join('\u0001');
  if (h.dataset.sig !== want) {
    h.dataset.sig = want;
    h.innerHTML = '';
    (L.history || []).forEach(sym => {
      const s = document.createElement('span');
      s.textContent = sym;
      h.appendChild(s);
    });
    if (!(L.history || []).length) h.innerHTML = '<span>rien encore</span>';
  }

  // Claviers
  const notes = L.sounding || [];
  paintKeys($('#k-small'), notes);
  paintKeys($('#k-chord'), notes);
  paintKeys($('#k-big'), notes);
  $('#kheld').textContent = L.held || 0;
  $('#knotes').textContent = notes.length ? L.chordNotes || notes.join(' ') : 'rien de tenu';

  // Prise
  const rec = !!L.recording;
  $('#recbtn').classList.toggle('on', rec);
  $('#rectitle').textContent = rec ? 'Arrêter · ' + mmss(L.recSeconds) : 'Enregistrer';
  $('#recsub').textContent = rec
    ? (L.recNotes || 0) + ' note' + ((L.recNotes || 0) > 1 ? 's' : '') + ' jouée' + ((L.recNotes || 0) > 1 ? 's' : '')
    : 'audio, MIDI, partition et accords';

  // Vert, puis ambre, puis rouge : les mêmes seuils que les deux vumètres du
  // bandeau et que ceux du Mac. Le sarcelle dit « actif », pas « −8 dB ».
  const mp = L.micPeak;
  const bar = $('#micmeter'), micbox = bar.parentElement;
  const heard = mp !== undefined && mp > -119;
  bar.style.width = heard ? db2pct(mp) + '%' : '0%';
  bar.style.opacity = heard ? 1 : .3;
  micbox.classList.toggle('hot', heard && mp > -1.5);
  micbox.classList.toggle('warm', heard && mp <= -1.5 && mp > -8);

  if (tab === 'eq') { paintEQ(); paintMic(); }
}

const mmss = s => Math.floor((s || 0) / 60) + '′' + String((s || 0) % 60).padStart(2, '0') + '″';

/* La piste se teinte jusqu'à la valeur, comme sur le Mac : un réglage se lit
   d'un coup d'œil, sans chercher où est la poignée. */
function fill(input) {
  const lo = +input.min, hi = +input.max;
  const t = hi > lo ? (+input.value - lo) / (hi - lo) : 0;
  input.style.setProperty('--f', (Math.max(0, Math.min(1, t)) * 100).toFixed(1) + '%');
}
const fillAll = () => $$('input[type=range]').forEach(fill);

/* Ne jamais écraser un curseur que le doigt est en train de bouger. */
function fader(name, value, format, disabled) {
  const input = $('#f-' + name);
  if (!input) return;
  const box = input.closest('.fader');
  if (disabled !== undefined) {
    input.disabled = !!disabled;
    if (box) box.classList.toggle('off', !!disabled);
  }
  if (grabbed[name]) return;
  if (value !== undefined && value !== null) input.value = value;
  fill(input);
  const out = $('#v-' + name);
  if (out) out.textContent = input.disabled ? '—'
    : format(value === undefined ? +input.value : value);
}

/* ── Rendu : état lent ──────────────────────────────────────────────── */

function renderState() {
  $('#sound').textContent = S.preset || '—';
  $('#catname').textContent = S.category || '—';
  $('#railver').textContent = S.version ? 'version ' + S.version : '';
  $('#railfoot').textContent = S.output ? 'Sortie : ' + S.output : '';

  fader('drive', S.fx && S.fx.drive, v => Math.round(v * 100) + ' %');
  fader('comp', S.fx && S.fx.comp, v => Math.round(v * 100) + ' %');
  fader('tremDepth', S.fx && S.fx.tremDepth, v => Math.round(v * 100) + ' %');
  fader('tremRate', S.fx && S.fx.tremRate, v => (+v).toFixed(1) + ' Hz',
        !(S.fx && S.fx.tremDepth > 0.005));
  fader('tempo', S.tempo, v => Math.round(v) + ' bpm');

  $('#recaudio').textContent = S.recordAudio ? 'Oui' : 'Non';
  $('#recaudio').classList.toggle('on', !!S.recordAudio);

  $('#ksplit').textContent = S.hasLayer && S.split
    ? 'Deux zones : la main gauche sous ' + noteName(S.split) + ', la droite au-dessus.'
    : 'Un seul son sur tout le clavier.';

  $('#i-kb').textContent = (S.keyboards && S.keyboards.length)
    ? S.keyboards.join(', ') : 'aucun clavier branché';
  $('#i-out').textContent = S.audioStatus || S.output || '—';
  $('#i-preset').textContent = (S.preset || '—') + (S.subtitle ? ' — ' + S.subtitle : '');
  $('#i-mic').textContent = S.micOn ? 'en service' : 'éteint';
  $('#i-ver').textContent = S.version ? S.version + ' (' + (S.commit || '') + ')' : '—';
  $('#i-latest').textContent = S.update ? S.update.latest : (S.updateMessage || 'pas vérifié');
  $('#i-key').textContent = KEY || '—';
  const repo = $('#i-repo');
  repo.textContent = (S.repo || '').replace('https://github.com/', '') || '—';
  repo.href = S.repo || '#';

  const banner = $('#updbanner');
  if (S.update && S.update.newer) {
    banner.classList.remove('hide');
    banner.innerHTML = 'La version <b>' + S.update.latest + '</b> est disponible — '
      + 'vous avez la ' + S.version + '.<br>Sur le Mac : onglet Périphériques, '
      + 'section Version, qui donne la commande à lancer.';
  } else banner.classList.add('hide');

  drawTakes();
  drawPresets();
  drawBands();
  drawMic();
  if (tab === 'eq') { paintEQ(); paintMic(); }
}

function drawMic() {
  const m = S.mic;
  if (!m) return;
  $('#micon').textContent = m.on ? 'Couper' : 'Ouvrir';
  $('#micon').classList.toggle('on', !!m.on);
  $('#micauth').textContent = m.auth === 'authorized' ? '' : m.authText || '';
  $('#micmon').textContent = m.monitoring ? 'Écoute ouverte' : 'Écouter';
  $('#micmon').classList.toggle('on', !!m.monitoring);

  const msg = $('#micmsg');
  msg.textContent = m.message || '';
  msg.classList.toggle('hide', !m.message);

  fader('micGain', m.gain, v => Math.round(v * 100) + ' %');
  fader('micComp', m.comp, v => Math.round(v * 100) + ' %');

  // Liste des entrées
  const sel = $('#micdev');
  const sig = (m.devices || []).map(d => d.id + ':' + d.name).join('|');
  if (sel.dataset.sig !== sig) {
    sel.dataset.sig = sig;
    sel.innerHTML = '';
    if (!(m.devices || []).length) {
      const o = document.createElement('option');
      o.textContent = 'aucune entrée trouvée';
      o.disabled = true;
      sel.appendChild(o);
    }
    for (const d of m.devices || []) {
      const o = document.createElement('option');
      o.value = d.id;
      o.textContent = d.name;
      sel.appendChild(o);
    }
  }
  if (document.activeElement !== sel) sel.value = String(m.deviceID);

  // Égaliseur du micro : des curseurs simples, pas de courbe à tracer.
  const host = $('#micbands');
  const bands = m.bands || [];
  if (host.children.length !== bands.length) {
    host.innerHTML = '';
    bands.forEach((_, i) => {
      const row = document.createElement('div');
      row.className = 'microw';
      row.innerHTML = '<div><b></b><small class="num"></small></div>'
        + '<input type="range" min="-18" max="18" step=".5">'
        + '<div class="v num"></div>';
      const input = row.querySelector('input');
      const flag = 'micb' + i;
      const apply = live => {
        const b = (S.mic.bands || [])[i];
        if (!b) return;
        b.gain = +input.value;
        row.querySelector('.v').textContent = (b.gain > 0 ? '+' : '') + b.gain.toFixed(1);
        live ? cmdThrottled('micBand', { index: i, gain: b.gain }, 70)
             : cmd('micBand', { index: i, gain: b.gain });
      };
      input.addEventListener('pointerdown', () => { grabbed[flag] = true; });
      input.addEventListener('input', () => { grabbed[flag] = true; apply(true); });
      const done = () => { apply(false); setTimeout(() => { grabbed[flag] = false; }, 350); };
      input.addEventListener('change', done);
      input.addEventListener('pointerup', done);
      host.appendChild(row);
    });
  }
  bands.forEach((b, i) => {
    const row = host.children[i];
    row.querySelector('b').textContent = b.label;
    row.querySelector('small').textContent = hz(b.freq);
    const input = row.querySelector('input');
    input.disabled = !b.usesGain;
    row.classList.toggle('off', !b.usesGain);
    if (grabbed['micb' + i]) return;
    input.value = b.gain;
    fill(input);
    row.querySelector('.v').textContent = b.usesGain
      ? (b.gain > 0 ? '+' : '') + (+b.gain).toFixed(1) : '—';
  });
}

function drawPresets() {
  const box = $('#presets');
  const q = query.trim().toLowerCase();
  const searching = q.length > 0;
  const rows = library
    .map((p, i) => ({ p, i }))
    .filter(({ p }) => !q || (p.name + ' ' + p.subtitle + ' ' + p.category).toLowerCase().includes(q));
  $('#pcount').textContent = searching ? rows.length + ' sur ' + library.length
                                       : library.length + ' sons';
  $('#foldall').textContent = shutFams.size ? 'Tout déplier' : 'Tout replier';
  $('#foldall').classList.toggle('hide', searching);

  // Les familles dans l'ordre de la bibliothèque, celui du Mac.
  const fams = [];
  for (const r of rows) {
    const last = fams[fams.length - 1];
    if (!last || last.name !== r.p.category) fams.push({ name: r.p.category, rows: [r] });
    else last.rows.push(r);
  }

  const sig = rows.map(r => r.i).join(',') + '|' + L.presetIndex
    + '|' + [...shutFams].sort().join(',') + '|' + searching;
  if (box.dataset.sig === sig) return;
  box.dataset.sig = sig;
  box.innerHTML = '';
  if (!rows.length) { box.innerHTML = '<p class="note">Aucun son ne correspond.</p>'; return; }

  for (const fam of fams) {
    const shut = !searching && shutFams.has(fam.name);
    const sec = document.createElement('section');
    sec.className = 'fam' + (shut ? ' shut' : '');

    const head = document.createElement('button');
    head.className = 'famhead';
    head.innerHTML = '<span class="chev">' + (shut ? '\u25b8' : '\u25be') + '</span>'
      + '<span>' + fam.name + '</span>'
      + (fam.rows.some(r => r.i === L.presetIndex) ? '<span class="dot"></span>' : '')
      + '<span class="n num">' + fam.rows.length + '</span>';
    head.onclick = () => {
      shut ? shutFams.delete(fam.name) : shutFams.add(fam.name);
      drawPresets();
    };
    sec.appendChild(head);

    const grid = document.createElement('div');
    grid.className = 'famgrid';
    for (const { p, i } of fam.rows) {
      const b = document.createElement('button');
      b.dataset.i = i;
      b.classList.toggle('on', i === L.presetIndex);
      const n = document.createElement('div'); n.className = 'n'; n.textContent = p.name;
      const sub = document.createElement('div'); sub.className = 's'; sub.textContent = p.subtitle;
      b.append(n, sub);
      b.onclick = () => cmd('preset', { index: i });
      grid.appendChild(b);
    }
    sec.appendChild(grid);
    box.appendChild(sec);
  }
}

function drawTakes() {
  const box = $('#takes');
  const takes = S.takes || [];
  box.innerHTML = '';
  if (!takes.length) {
    box.innerHTML = '<p class="note">Aucune prise pour l\'instant.</p>';
    return;
  }
  for (const t of takes) {
    const row = document.createElement('div');
    row.className = 'take';
    const left = document.createElement('div');
    left.style.minWidth = 0;
    left.innerHTML = '<div class="n"></div><div class="m"></div>'
      + '<div class="tags"><i>midi</i><i>partition</i><i>accords</i></div>';
    left.querySelector('.n').textContent = t.name;
    left.querySelector('.m').textContent = t.when + ' · ' + mmss(t.seconds)
      + ' · ' + t.notes + ' notes · ' + t.tempo + ' bpm';
    if (t.audio) {
      const i = document.createElement('i');
      i.textContent = 'audio';
      left.querySelector('.tags').prepend(i);
    }
    row.appendChild(left);
    box.appendChild(row);
  }
}

/* ── Claviers ───────────────────────────────────────────────────────── */

const WHITE = [0, 2, 4, 5, 7, 9, 11];
const NOTE_FR = ['do', 'do♯', 'ré', 'ré♯', 'mi', 'fa', 'fa♯', 'sol', 'sol♯', 'la', 'la♯', 'si'];
const noteName = n => NOTE_FR[((n % 12) + 12) % 12] + (Math.floor(n / 12) - 1);

function buildKeys(el) {
  const labels = el.classList.contains('big');
  const whites = [];
  for (let n = 21; n <= 108; n++) if (WHITE.includes(((n % 12) + 12) % 12)) whites.push(n);
  const wW = 100 / whites.length;
  const bW = wW * 0.58;
  const marks = [];
  el.innerHTML = '';
  // Zone de la main gauche : un lit de touches assombri et un filet au point
  // de partage, comme sur le Mac. Elle se voit même quand rien n'est tenu, et
  // les notes gardent toutes la même couleur.
  const zone = document.createElement('div');
  zone.className = 'zone';
  zone.style.display = 'none';
  el.appendChild(zone);
  el.zone = zone;
  el.whiteWidth = wW;
  el.whites = whites;
  let wi = 0;
  for (let n = 21; n <= 108; n++) {
    const pc = ((n % 12) + 12) % 12;
    const d = document.createElement('div');
    d.dataset.n = n;
    if (WHITE.includes(pc)) {
      d.className = 'w';
      d.style.left = (wi * wW) + '%';
      d.style.width = wW + '%';
      if (labels && pc === 0) {
        const c = document.createElement('div');
        c.className = 'c';
        c.textContent = 'do' + (Math.floor(n / 12) - 1);
        c.style.left = (wi * wW) + '%';
        c.style.width = wW + '%';
        marks.push(c);
      }
      wi++;
    } else {
      d.className = 'b';
      d.style.left = (wi * wW - bW / 2) + '%';
      d.style.width = bW + '%';
      d.style.height = '61%';
    }
    el.appendChild(d);
  }
  marks.forEach(m => el.appendChild(m));
  el.dataset.built = '1';
}

function paintKeys(el, notes) {
  if (!el || el.offsetParent === null) return;
  if (!el.dataset.built) buildKeys(el);
  const set = new Set(notes);
  const split = S.hasLayer ? (S.split || 60) : 0;
  const sig = notes.join(',') + '|' + split;
  if (el.dataset.sig === sig) return;
  el.dataset.sig = sig;
  for (const d of el.children) {
    if (!d.dataset.n) continue;
    d.classList.toggle('hit', set.has(+d.dataset.n));
  }
  if (el.zone) {
    const i = el.whites.findIndex(n => n >= split);
    if (split > 0 && i > 0) {
      el.zone.style.display = '';
      el.zone.style.width = (i * el.whiteWidth) + '%';
    } else {
      el.zone.style.display = 'none';
    }
  }
}

/* ── Égaliseur : la même courbe que sur le Mac ──────────────────────── */

const F_MIN = 20, F_MAX = 20000, EQ_RANGE = 18, SPEC_TOP = 0, SPEC_BOTTOM = -72;
const SR = 44100;
const GRID = [30, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];

const xForFreq = (f, w) =>
  (Math.log10(Math.max(F_MIN, Math.min(F_MAX, f))) - Math.log10(F_MIN))
  / (Math.log10(F_MAX) - Math.log10(F_MIN)) * w;
const freqForX = (x, w) => F_MIN * Math.pow(F_MAX / F_MIN, Math.max(0, Math.min(1, x / w)));
const yForEQ = (db, h) => h * (0.5 - db / (2 * EQ_RANGE));
const eqForY = (y, h) => (0.5 - y / h) * 2 * EQ_RANGE;
const yForSpec = (db, h) =>
  h * (1 - (Math.max(SPEC_BOTTOM, Math.min(SPEC_TOP, db)) - SPEC_BOTTOM)
       / (SPEC_TOP - SPEC_BOTTOM));

/* Mêmes formules que BiquadCoeffs.make, pour que la courbe affichée soit
   celle que le Mac applique vraiment. */
function coeffs(kind, freq, gainDB, q) {
  const f = Math.max(10, Math.min(freq, SR * 0.49));
  const w0 = 2 * Math.PI * f / SR;
  const cs = Math.cos(w0), sn = Math.sin(w0);
  const alpha = sn / (2 * Math.max(0.1, q));
  const A = Math.pow(10, gainDB / 40);
  let b0, b1, b2, a0, a1, a2;
  switch (kind) {
    case 'highpass':
      b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = (1 + cs) / 2;
      a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; break;
    case 'lowpass':
      b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = (1 - cs) / 2;
      a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; break;
    case 'lowshelf': {
      const beta = 2 * Math.sqrt(A) * alpha;
      b0 = A * ((A + 1) - (A - 1) * cs + beta);
      b1 = 2 * A * ((A - 1) - (A + 1) * cs);
      b2 = A * ((A + 1) - (A - 1) * cs - beta);
      a0 = (A + 1) + (A - 1) * cs + beta;
      a1 = -2 * ((A - 1) + (A + 1) * cs);
      a2 = (A + 1) + (A - 1) * cs - beta; break;
    }
    case 'highshelf': {
      const beta = 2 * Math.sqrt(A) * alpha;
      b0 = A * ((A + 1) + (A - 1) * cs + beta);
      b1 = -2 * A * ((A - 1) + (A + 1) * cs);
      b2 = A * ((A + 1) + (A - 1) * cs - beta);
      a0 = (A + 1) - (A - 1) * cs + beta;
      a1 = 2 * ((A - 1) - (A + 1) * cs);
      a2 = (A + 1) - (A - 1) * cs - beta; break;
    }
    default:
      b0 = 1 + alpha * A; b1 = -2 * cs; b2 = 1 - alpha * A;
      a0 = 1 + alpha / A; a1 = -2 * cs; a2 = 1 - alpha / A;
  }
  return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
}

function magDB(c, freq) {
  const w = 2 * Math.PI * freq / SR;
  const cw = Math.cos(w), sw = Math.sin(w);
  const c2w = Math.cos(2 * w), s2w = Math.sin(2 * w);
  const nr = c.b0 + c.b1 * cw + c.b2 * c2w;
  const ni = -(c.b1 * sw + c.b2 * s2w);
  const dr = 1 + c.a1 * cw + c.a2 * c2w;
  const di = -(c.a1 * sw + c.a2 * s2w);
  const num = Math.hypot(nr, ni);
  const den = Math.max(1e-9, Math.hypot(dr, di));
  return 20 * Math.log10(Math.max(1e-9, num / den));
}

let selBand = 2;
let peaks = new Float32Array(128).fill(-100);
let specCache = new Float32Array(128).fill(-100);
let micPeaks = new Float32Array(128).fill(-100);
let micSpec = new Float32Array(128).fill(-100);

function decodeSpectrum(b64, spec, peakHold) {
  if (!b64) return;
  const bin = atob(b64);
  const n = Math.min(bin.length, spec.length);
  for (let i = 0; i < n; i++) {
    const db = bin.charCodeAt(i) / 255 * 72 - 72;
    spec[i] = db;
    peakHold[i] = Math.max(db, peakHold[i] - 0.9);
  }
}

function bandCenter(i) {
  return F_MIN * Math.pow(F_MAX / F_MIN, (i + 0.5) / 128);
}

/* Le cadre d'un analyseur : la grille, le spectre, puis la courbe.
   Le même tracé sert au piano et au micro — seule la source change. */
function paintAnalyzer(g, w, h, spec, peakHold, bands) {
  // Grille
  g.font = '500 9px -apple-system,system-ui,sans-serif';
  g.textBaseline = 'alphabetic';
  const dense = h >= 170;
  for (const f of GRID) {
    if (!dense && f !== 100 && f !== 1000 && f !== 10000 && f !== 30) continue;
    const x = xForFreq(f, w);
    g.strokeStyle = 'rgba(255,255,255,' + (f === 1000 ? .09 : .05) + ')';
    g.beginPath(); g.moveTo(x, 0); g.lineTo(x, h); g.stroke();
    g.fillStyle = '#7A8296';
    g.textAlign = 'left';
    g.fillText(f >= 1000 ? (f / 1000) + 'k' : '' + f, x + 3, h - 4);
  }
  for (let db = -12; db <= 12; db += 6) {
    if (!dense && db !== 0) continue;
    const y = yForEQ(db, h);
    g.strokeStyle = 'rgba(255,255,255,' + (db === 0 ? .14 : .05) + ')';
    g.setLineDash(db === 0 ? [] : [2, 4]);
    g.beginPath(); g.moveTo(0, y); g.lineTo(w, y); g.stroke();
    g.setLineDash([]);
    if (db !== 0) {
      g.fillStyle = '#7A8296'; g.textAlign = 'right';
      g.fillText((db > 0 ? '+' : '') + db, w - 4, y - 3);
    }
  }

  // Spectre : un gris. L'accent est réservé à la courbe qu'on règle.
  g.beginPath();
  g.moveTo(0, h);
  for (let i = 0; i < 128; i++) {
    g.lineTo(xForFreq(bandCenter(i), w), yForSpec(spec[i], h));
  }
  g.lineTo(w, h);
  g.closePath();
  const grad = g.createLinearGradient(0, 0, 0, h);
  grad.addColorStop(0, 'rgba(255,255,255,.14)');
  grad.addColorStop(.35, 'rgba(255,255,255,.05)');
  grad.addColorStop(.8, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fill();
  // L'arête se lit, le remplissage ne fait que donner la masse.
  g.beginPath();
  for (let i = 0; i < 128; i++) {
    const x = xForFreq(bandCenter(i), w), y = yForSpec(spec[i], h);
    i ? g.lineTo(x, y) : g.moveTo(x, y);
  }
  g.strokeStyle = 'rgba(255,255,255,.45)';
  g.lineWidth = 1.2;
  g.stroke();

  // Crêtes qui retombent
  g.beginPath();
  for (let i = 0; i < 128; i++) {
    const x = xForFreq(bandCenter(i), w), y = yForSpec(peakHold[i], h);
    i ? g.lineTo(x, y) : g.moveTo(x, y);
  }
  g.strokeStyle = 'rgba(255,255,255,.22)';
  g.lineWidth = 1;
  g.stroke();

  // Courbe d'égalisation
  const cs = (bands || []).filter(b => b.enabled)
    .map(b => coeffs(b.kind, b.freq, b.usesGain ? b.gain : 0, b.q));
  g.beginPath();
  for (let x = 0; x <= w; x += 2) {
    const f = freqForX(x, w);
    let db = 0;
    for (const k of cs) db += magDB(k, f);
    const y = yForEQ(Math.max(-EQ_RANGE, Math.min(EQ_RANGE, db)), h);
    x ? g.lineTo(x, y) : g.moveTo(x, y);
  }
  g.strokeStyle = '#4FD1C5';
  g.lineWidth = 2;
  g.stroke();
}

/* Prépare le canevas à la taille de son cadre, écran Retina compris. */
function fitCanvas(wrap, c) {
  if (!wrap || wrap.offsetParent === null) return null;
  const w = wrap.clientWidth, h = wrap.clientHeight;
  if (w < 20 || h < 20) return null;
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) {
    c.width = Math.round(w * dpr); c.height = Math.round(h * dpr);
    c.style.width = w + 'px'; c.style.height = h + 'px';
  }
  const g = c.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, w, h);
  return { g, w, h };
}

function paintEQ() {
  const f = fitCanvas($('#eqwrap'), $('#eqcanvas'));
  if (!f) return;
  decodeSpectrum(L.spectrum, specCache, peaks);
  paintAnalyzer(f.g, f.w, f.h, specCache, peaks, S.eq || []);
  placeHandles(f.w, f.h);
}

/* L'analyseur du micro : ce que l'entrée entend, avant gain et avant
   égalisation, avec par-dessus la courbe qu'on lui applique. */
function paintMic() {
  const on = !!(S.mic && S.mic.on);
  const hint = $('#micoff');
  if (hint) hint.classList.toggle('hide', on);
  const f = fitCanvas($('#micwrap'), $('#miccanvas'));
  if (!f) return;
  if (on) decodeSpectrum(L.micSpectrum, micSpec, micPeaks);
  else { micSpec.fill(-100); micPeaks.fill(-100); }
  paintAnalyzer(f.g, f.w, f.h, micSpec, micPeaks, (S.mic && S.mic.bands) || []);
}

function placeHandles(w, h) {
  const wrap = $('#eqwrap');
  const bands = S.eq || [];
  let nodes = [...wrap.querySelectorAll('.handle')];
  while (nodes.length > bands.length) nodes.pop().remove();
  while (nodes.length < bands.length) {
    const d = document.createElement('div');
    d.className = 'handle';
    d.dataset.i = nodes.length;
    wrap.appendChild(d);
    nodes.push(d);
    armHandle(d);
  }
  bands.forEach((b, i) => {
    const d = nodes[i];
    // Le numéro de la bande, comme sur le Mac. Un nom coupé au troisième
    // caractère dans un rond de trente pixels ne se lit pas, et le nom entier
    // est juste en dessous, dans la tranche.
    d.textContent = String(i + 1);
    // On garde la poignée entièrement dans le cadre : au bord, elle serait
    // coupée en deux et difficile à attraper.
    d.style.left = Math.max(16, Math.min(w - 16, xForFreq(b.freq, w))) + 'px';
    d.style.top = Math.max(16, Math.min(h - 16, yForEQ(b.usesGain ? b.gain : 0, h))) + 'px';
    d.classList.toggle('sel', i === selBand);
    d.classList.toggle('off', !b.enabled);
  });
}

function armHandle(d) {
  let last = 0;
  d.addEventListener('pointerdown', ev => {
    ev.preventDefault();
    const i = +d.dataset.i;
    selBand = i;
    drawBands();
    d.setPointerCapture(ev.pointerId);
    const now = performance.now();
    if (now - last < 320) {           // deux tapes : bande à plat
      cmd('eqband', { index: i, gain: 0 });
      if (S.eq && S.eq[i]) S.eq[i].gain = 0;
    }
    last = now;
    grabbed.eqhandle = true;
  });
  d.addEventListener('pointermove', ev => {
    if (!grabbed.eqhandle || !d.hasPointerCapture(ev.pointerId)) return;
    const i = +d.dataset.i, b = (S.eq || [])[i];
    if (!b) return;
    const r = $('#eqwrap').getBoundingClientRect();
    const x = Math.max(0, Math.min(r.width, ev.clientX - r.left));
    const y = Math.max(0, Math.min(r.height, ev.clientY - r.top));
    b.freq = Math.round(freqForX(x, r.width));
    cmdThrottled('eqfreq', { index: i, freq: b.freq }, 70);
    if (b.usesGain) {
      b.gain = Math.round(Math.max(-18, Math.min(18, eqForY(y, r.height))) * 2) / 2;
      cmdThrottled('eqband', { index: i, gain: b.gain }, 70);
    }
    drawBands();
    paintEQ();
  });
  const release = ev => {
    if (!grabbed.eqhandle) return;
    grabbed.eqhandle = false;
    const i = +d.dataset.i, b = (S.eq || [])[i];
    if (b) {
      cmd('eqfreq', { index: i, freq: b.freq });
      if (b.usesGain) cmd('eqband', { index: i, gain: b.gain });
    }
  };
  d.addEventListener('pointerup', release);
  d.addEventListener('pointercancel', release);
}

function drawBands() {
  const bands = S.eq || [];
  const bar = $('#bandbar');
  if (bar.children.length !== bands.length) {
    bar.innerHTML = '';
    bands.forEach((_, i) => {
      const b = document.createElement('button');
      // Le numéro sert sur un écran étroit, où sept noms entiers ne tiennent
      // pas ; le nom complet est alors juste en dessous, dans le détail de la
      // bande choisie. Mieux qu'un « Présenc » coupé au bord.
      b.innerHTML = '<div class="i num">' + (i + 1) + '</div><div class="l"></div>'
                  + '<div class="g num"></div><div class="f num"></div>';
      b.onclick = () => { selBand = i; drawBands(); paintEQ(); };
      bar.appendChild(b);
    });
  }
  bands.forEach((b, i) => {
    const el = bar.children[i];
    el.querySelector('.l').textContent = b.label;
    el.querySelector('.g').textContent = b.usesGain
      ? (b.gain > 0 ? '+' : '') + (+b.gain).toFixed(1) : '—';
    el.querySelector('.f').textContent = hz(b.freq);
    el.classList.toggle('on', i === selBand);
    el.classList.toggle('mute', !b.enabled);
  });

  const b = bands[selBand];
  if (!b) return;
  $('#bandname').textContent = b.label + ' · ' + hz(b.freq);
  $('#bandoff').textContent = b.enabled ? 'Couper' : 'Remettre';
  $('#bandoff').classList.toggle('on', !b.enabled);
  if (!grabbed.bgain) {
    $('#b-gain').value = b.gain;
    $('#b-gain').disabled = !b.usesGain;
    $('#b-gain').closest('.fader').classList.toggle('off', !b.usesGain);
    $('#b-gainv').textContent = b.usesGain
      ? (b.gain > 0 ? '+' : '') + (+b.gain).toFixed(1) + ' dB' : '—';
  }
  if (!grabbed.bfreq) {
    $('#b-freq').value = Math.round(freqToSlider(b.freq));
    $('#b-freqv').textContent = hz(b.freq);
  }
  if (!grabbed.bq) {
    $('#b-q').value = b.q;
    $('#b-qv').textContent = (+b.q).toFixed(2);
  }
  ['#b-gain', '#b-freq', '#b-q'].forEach(sel => fill($(sel)));
}

const hz = f => f >= 1000 ? (f / 1000).toFixed(f >= 10000 ? 0 : 1) + ' kHz' : Math.round(f) + ' Hz';
const freqToSlider = f => xForFreq(f, 1000);
const sliderToFreq = v => Math.round(freqForX(v, 1000));

/* ── Branchements ───────────────────────────────────────────────────── */

function wire() {
  $('#gatego').onclick = useKey;
  $('#key').addEventListener('keydown', e => { if (e.key === 'Enter') useKey(); });

  // Boutons déclaratifs : data-cmd / data-delta / data-set
  $$('[data-cmd]').forEach(b => {
    b.onclick = () => {
      const extra = {};
      if (b.dataset.delta !== undefined) extra.delta = +b.dataset.delta;
      if (b.dataset.set !== undefined) extra.set = +b.dataset.set;
      cmd(b.dataset.cmd, extra);
    };
  });

  // Curseurs
  $$('input[type=range][data-send]').forEach(input => {
    const name = input.id.replace('f-', '');
    const action = input.dataset.send;
    const key = input.dataset.key;
    const payload = () => {
      if (action === 'fx') return { [key]: +input.value };
      return { value: +input.value };
    };
    input.addEventListener('pointerdown', () => { grabbed[name] = true; });
    input.addEventListener('input', () => {
      grabbed[name] = true;
      const out = $('#v-' + name);
      if (out) {
        out.textContent = name === 'tempo' ? Math.round(+input.value) + ' bpm'
          : name === 'tremRate' ? (+input.value).toFixed(1) + ' Hz'
          : Math.round(+input.value * 100) + ' %';
      }
      throttle('f-' + name, 80, () => cmd(action, payload()));
    });
    const done = () => {
      cmd(action, payload());
      setTimeout(() => { grabbed[name] = false; }, 350);
    };
    input.addEventListener('change', done);
    input.addEventListener('pointerup', done);
  });

  $('#search').addEventListener('input', e => { query = e.target.value; drawPresets(); });

  $('#eqreset').onclick = () => cmd('eqreset', {});
  $('#bandoff').onclick = () => {
    const b = (S.eq || [])[selBand];
    if (!b) return;
    b.enabled = !b.enabled;
    cmd('eqenabled', { index: selBand, on: b.enabled });
    drawBands(); paintEQ();
  };

  const bandFader = (id, flag, apply) => {
    const el = $(id);
    el.addEventListener('pointerdown', () => { grabbed[flag] = true; });
    el.addEventListener('input', () => { grabbed[flag] = true; apply(+el.value, true); });
    const done = () => { apply(+el.value, false); setTimeout(() => { grabbed[flag] = false; }, 350); };
    el.addEventListener('change', done);
    el.addEventListener('pointerup', done);
  };
  bandFader('#b-gain', 'bgain', (v, live) => {
    const b = (S.eq || [])[selBand]; if (!b) return;
    b.gain = v;
    $('#b-gainv').textContent = (v > 0 ? '+' : '') + v.toFixed(1) + ' dB';
    live ? cmdThrottled('eqband', { index: selBand, gain: v }, 70)
         : cmd('eqband', { index: selBand, gain: v });
    drawBands(); paintEQ();
  });
  bandFader('#b-freq', 'bfreq', (v, live) => {
    const b = (S.eq || [])[selBand]; if (!b) return;
    b.freq = sliderToFreq(v);
    $('#b-freqv').textContent = hz(b.freq);
    live ? cmdThrottled('eqfreq', { index: selBand, freq: b.freq }, 70)
         : cmd('eqfreq', { index: selBand, freq: b.freq });
    drawBands(); paintEQ();
  });
  bandFader('#b-q', 'bq', (v, live) => {
    const b = (S.eq || [])[selBand]; if (!b) return;
    b.q = v;
    $('#b-qv').textContent = v.toFixed(2);
    live ? cmdThrottled('eqq', { index: selBand, q: v }, 70)
         : cmd('eqq', { index: selBand, q: v });
    drawBands(); paintEQ();
  });

  $('#foldall').onclick = () => {
    const fams = [...new Set(library.map(p => p.category))];
    shutFams = shutFams.size ? new Set() : new Set(fams);
    drawPresets();
  };

  $('#micon').onclick = () => cmd('mic', {});
  $('#micmon').onclick = () => cmd('micMonitor', { on: !(S.mic && S.mic.monitoring) });
  $('#micrescan').onclick = () => cmd('micRescan', {});
  $('#micreset').onclick = () => cmd('micReset', {});
  $('#micdev').addEventListener('change', e => cmd('micDevice', { id: +e.target.value }));

  $('#recbtn').onclick = () => cmd('record', {});
  $('#recaudio').onclick = () => cmd('recordAudio', { on: !S.recordAudio });
  $('#chkupd').onclick = () => { $('#i-latest').textContent = 'vérification…'; cmd('checkUpdate', {}); };
  $('#forget').onclick = () => {
    localStorage.removeItem('plsKey');
    KEY = '';
    stop();
    gate(true, '');
  };
  $('#reload').onclick = () => location.reload();

  // Le manifeste emporte la clé : l'icône posée sur l'écran d'accueil
  // s'ouvre déjà connectée.
  if (KEY) $('#manifest').href = '/manifest.webmanifest?k=' + encodeURIComponent(KEY);

  document.addEventListener('input', e => {
    if (e.target && e.target.type === 'range') fill(e.target);
  }, true);

  let resizeTimer = 0;
  addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      ['#k-small', '#k-chord', '#k-big'].forEach(s => {
        const el = $(s);
        if (el) { el.dataset.sig = ''; }
      });
      paintEQ();
      paintMic();
    }, 120);
  });
  addEventListener('orientationchange', () => {
    setTimeout(() => {
      ['#k-small', '#k-chord', '#k-big'].forEach(sel => {
        const el = $(sel);
        if (el) el.dataset.sig = '';
      });
      paintEQ(); paintMic();
    }, 260);
  });

  // Une tablette qu'on réveille : on repart proprement.
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && KEY) { stop(); start(); }
  });
}

/* ── Départ ─────────────────────────────────────────────────────────── */

buildNav();
wire();
show(TABS.some(t => t[0] === tab) ? tab : 'play');
history.replaceState(null, '', location.pathname);

if (KEY) { localStorage.setItem('plsKey', KEY); start(); } else gate(true, '');
