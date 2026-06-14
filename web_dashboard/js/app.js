import { auth, firestore } from './firebase-config.js';
import {
  signInWithEmailAndPassword,
  signOut,
  onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/10.7.1/firebase-auth.js";
import {
  collection,
  getDocs,
  doc,
  updateDoc,
  onSnapshot,
  query,
  orderBy,
} from "https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore.js";

// ═══════════════════════════════════════════
// PERMISSION DEFINITIONS
// ═══════════════════════════════════════════
const PERMISSIONS = [
  { id: 'camera',          label: 'Camera',             icon: '📷', desc: 'Take photos and record video' },
  { id: 'microphone',      label: 'Microphone',         icon: '🎙️', desc: 'Record audio' },
  { id: 'location',        label: 'Location',           icon: '📍', desc: 'Precise GPS location' },
  { id: 'location_always', label: 'Location (Always)',  icon: '🗺️', desc: 'Background location access' },
  { id: 'storage',         label: 'Storage',            icon: '💾', desc: 'Read and write files' },
  { id: 'photos',          label: 'Photos & Media',     icon: '🖼️', desc: 'Access photos and media' },
  { id: 'contacts',        label: 'Contacts',           icon: '👥', desc: 'Read and write contacts' },
  { id: 'phone',           label: 'Phone',              icon: '📞', desc: 'Make and manage calls' },
  { id: 'sms',             label: 'SMS',                icon: '💬', desc: 'Send and receive messages' },
  { id: 'call_log',        label: 'Call Log',           icon: '📋', desc: 'Access call history' },
  { id: 'bluetooth',       label: 'Bluetooth',          icon: '🔵', desc: 'Connect Bluetooth devices' },
  { id: 'bluetooth_scan',  label: 'Bluetooth Scan',     icon: '📡', desc: 'Scan nearby Bluetooth devices' },
  { id: 'notifications',   label: 'Notifications',      icon: '🔔', desc: 'Show push notifications' },
  { id: 'calendar',        label: 'Calendar',           icon: '📅', desc: 'Read and write calendar events' },
  { id: 'sensors',         label: 'Body Sensors',       icon: '❤️', desc: 'Access health sensors' },
  { id: 'activity',        label: 'Activity',           icon: '🏃', desc: 'Detect physical activity' },
  { id: 'nearby_wifi',     label: 'Nearby WiFi',        icon: '📶', desc: 'Scan nearby WiFi networks' },
  { id: 'manage_storage',  label: 'Manage All Files',   icon: '🗂️', desc: 'Full file system access' },
];

// ═══════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════
let allUsers = [];
let currentUserId = null;
let currentPerms  = {};
let pendingPerms  = {};

// ═══════════════════════════════════════════
// AUTH
// ═══════════════════════════════════════════
onAuthStateChanged(auth, (user) => {
  if (user) {
    showDashboard(user);
  } else {
    showLogin();
  }
});

document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const btn   = document.getElementById('loginBtn');
  const errEl = document.getElementById('loginError');
  errEl.classList.add('hidden');
  btn.disabled = true;
  btn.textContent = 'Signing in...';

  try {
    await signInWithEmailAndPassword(
      auth,
      document.getElementById('adminEmail').value.trim(),
      document.getElementById('adminPass').value.trim()
    );
  } catch (err) {
    errEl.textContent = friendlyAuthError(err.code);
    errEl.classList.remove('hidden');
    btn.disabled = false;
    btn.textContent = 'Sign In';
  }
});

function friendlyAuthError(code) {
  const map = {
    'auth/user-not-found':  'No account with this email.',
    'auth/wrong-password':  'Incorrect password.',
    'auth/invalid-email':   'Invalid email address.',
    'auth/too-many-requests': 'Too many attempts. Try again later.',
  };
  return map[code] || 'Sign in failed. Check your credentials.';
}

async function logout() {
  await signOut(auth);
}

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
  loadUsers();
}

// ═══════════════════════════════════════════
// LOAD USERS
// ═══════════════════════════════════════════
async function loadUsers() {
  setLoading(true);
  try {
    const snap = await getDocs(collection(firestore, 'users'));
    allUsers = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    renderUsers(allUsers);
    updateStats(allUsers);
  } catch (err) {
    console.error('Load users error:', err);
    showToast('Failed to load users: ' + err.message, 'error');
    setLoading(false);
  }
}

window.loadUsers = loadUsers;

function setLoading(on) {
  document.getElementById('loadingState').classList.toggle('hidden', !on);
  document.getElementById('usersList').classList.toggle('hidden', on);
  document.getElementById('emptyState').classList.add('hidden');
}

function renderUsers(users) {
  const grid = document.getElementById('usersList');
  document.getElementById('loadingState').classList.add('hidden');

  if (users.length === 0) {
    grid.classList.add('hidden');
    document.getElementById('emptyState').classList.remove('hidden');
    document.getElementById('userCountBadge').textContent = '0 users';
    return;
  }

  document.getElementById('emptyState').classList.add('hidden');
  grid.classList.remove('hidden');
  document.getElementById('userCountBadge').textContent = `${users.length} user${users.length !== 1 ? 's' : ''}`;

  grid.innerHTML = users.map(u => buildUserCard(u)).join('');
}

function buildUserCard(user) {
  const perms = user.permissions || {};
  const enabled = PERMISSIONS.filter(p => perms[p.id]);
  const total   = PERMISSIONS.length;

  const tagHtml = PERMISSIONS.slice(0, 6).map(p => {
    const on = !!perms[p.id];
    return `<span class="perm-tag ${on ? 'on' : 'off'}">${p.icon} ${p.label}</span>`;
  }).join('');

  const initials = (user.name || 'U').charAt(0).toUpperCase();

  return `
    <div class="user-card" onclick="openModal('${user.id}')">
      <div class="user-card-header">
        <div class="user-card-avatar">${initials}</div>
        <div>
          <div class="user-card-name">${escHtml(user.name || 'Unknown')}</div>
          <div class="user-card-email">${escHtml(user.email || '')}</div>
        </div>
      </div>
      <div class="perm-summary">${tagHtml}</div>
      <div class="user-card-footer">
        <span class="perm-count">${enabled.length}/${total} enabled</span>
        <button class="btn-manage" onclick="event.stopPropagation(); openModal('${user.id}')">
          Manage →
        </button>
      </div>
    </div>
  `;
}

function updateStats(users) {
  document.getElementById('statTotal').textContent = users.length;
  const withPerms = users.filter(u => {
    const p = u.permissions || {};
    return Object.values(p).some(Boolean);
  }).length;
  document.getElementById('statActive').textContent = withPerms;
}

// ═══════════════════════════════════════════
// SEARCH
// ═══════════════════════════════════════════
function filterUsers() {
  const q = document.getElementById('searchInput').value.toLowerCase();
  const filtered = allUsers.filter(u =>
    (u.name || '').toLowerCase().includes(q) ||
    (u.email || '').toLowerCase().includes(q)
  );
  renderUsers(filtered);
}

window.filterUsers = filterUsers;

// ═══════════════════════════════════════════
// SECTIONS
// ═══════════════════════════════════════════
function showSection(section) {
  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
  event.currentTarget.classList.add('active');

  const statsEl = document.getElementById('statsSection');
  const usersEl = document.getElementById('usersSection');
  const titleEl = document.getElementById('sectionTitle');

  if (section === 'stats') {
    statsEl.classList.remove('hidden');
    usersEl.style.display = 'none';
    titleEl.textContent = 'Statistics';
    updateStats(allUsers);
  } else {
    statsEl.classList.add('hidden');
    usersEl.style.display = '';
    titleEl.textContent = 'User Management';
  }
}

window.showSection = showSection;

// ═══════════════════════════════════════════
// MODAL
// ═══════════════════════════════════════════
function openModal(userId) {
  currentUserId = userId;
  const user = allUsers.find(u => u.id === userId);
  if (!user) return;

  currentPerms = { ...(user.permissions || {}) };
  pendingPerms  = { ...currentPerms };

  document.getElementById('modalName').textContent  = user.name || 'Unknown';
  document.getElementById('modalEmail').textContent = user.email || '';
  document.getElementById('modalAvatar').textContent =
    (user.name || 'U').charAt(0).toUpperCase();

  renderPermissionCards(pendingPerms);

  const overlay = document.getElementById('userModal');
  overlay.classList.remove('hidden');
  document.body.style.overflow = 'hidden';
}

window.openModal = openModal;

function closeModal() {
  document.getElementById('userModal').classList.add('hidden');
  document.body.style.overflow = '';
  currentUserId = null;
}

window.closeModal = closeModal;

function closeModalOutside(e) {
  if (e.target === document.getElementById('userModal')) closeModal();
}

window.closeModalOutside = closeModalOutside;

function renderPermissionCards(perms) {
  const grid = document.getElementById('permissionsGrid');
  grid.innerHTML = PERMISSIONS.map(p => {
    const on = !!perms[p.id];
    return `
      <div class="perm-card ${on ? 'enabled' : ''}" id="card-${p.id}">
        <div class="perm-card-top">
          <div class="perm-icon-wrap ${on ? 'on' : 'off'}">${p.icon}</div>
          <label class="toggle">
            <input type="checkbox" id="toggle-${p.id}" ${on ? 'checked' : ''}
              onchange="togglePerm('${p.id}', this.checked)" />
            <span class="slider"></span>
          </label>
        </div>
        <div class="perm-name">${p.label}</div>
        <div class="perm-desc">${p.desc}</div>
      </div>
    `;
  }).join('');
}

function togglePerm(id, checked) {
  pendingPerms[id] = checked;
  const card = document.getElementById(`card-${id}`);
  const icon = card.querySelector('.perm-icon-wrap');
  card.classList.toggle('enabled', checked);
  icon.className = `perm-icon-wrap ${checked ? 'on' : 'off'}`;
}

window.togglePerm = togglePerm;

function setAllPermissions(value) {
  PERMISSIONS.forEach(p => {
    pendingPerms[p.id] = value;
    const toggle = document.getElementById(`toggle-${p.id}`);
    if (toggle) toggle.checked = value;
    const card = document.getElementById(`card-${p.id}`);
    const icon = card?.querySelector('.perm-icon-wrap');
    card?.classList.toggle('enabled', value);
    if (icon) icon.className = `perm-icon-wrap ${value ? 'on' : 'off'}`;
  });
}

window.setAllPermissions = setAllPermissions;

async function savePermissions() {
  if (!currentUserId) return;
  const btn = document.getElementById('saveBtn');
  btn.disabled = true;
  btn.textContent = '⏳ Saving...';

  try {
    await updateDoc(doc(firestore, 'users', currentUserId), {
      permissions: pendingPerms,
    });

    // Update local cache
    const idx = allUsers.findIndex(u => u.id === currentUserId);
    if (idx !== -1) allUsers[idx].permissions = { ...pendingPerms };

    showToast('Permissions saved! Changes applied instantly on mobile.', 'success');
    closeModal();
    renderUsers(allUsers);
  } catch (err) {
    showToast('Save failed: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = '💾 Save Changes';
  }
}

window.savePermissions = savePermissions;

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
  const input = document.getElementById('adminPass');
  input.type = input.type === 'password' ? 'text' : 'password';
}

window.togglePass = togglePass;

function escHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
