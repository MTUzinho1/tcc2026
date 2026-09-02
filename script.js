"use strict";


const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

let API_BASE_URL = location.hostname.endsWith("onrender.com") ? "" : "https://tcc2026.onrender.com";

function normalizeApiBase(value) {
  return String(value || "").trim().replace(/\/+$/, "");
}

async function loadApiConfig() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2500);
  try {
    const response = await fetch(`./config.json?v=${Date.now()}`, {
      cache: "no-store",
      signal: controller.signal
    });
    if (!response.ok) return;
    const config = await response.json();
    const configured = normalizeApiBase(config.apiBaseUrl);
    if (configured) API_BASE_URL = configured;
  } catch (_error) {
  } finally {
    clearTimeout(timer);
  }
}

function apiUrl(path) {
  if (/^https?:\/\//i.test(path)) return path;
  return `${API_BASE_URL}${path.startsWith("/") ? path : `/${path}`}`;
}

function wakeApi() {
  if (!API_BASE_URL) return;
  fetch(apiUrl("/api/health"), { cache: "no-store" }).catch(() => {});
}

const state = {
  token: localStorage.getItem("bookshare_token") || "",
  user: null,
  route: "dashboard",
  bookView: localStorage.getItem("bookshare_book_view") || "grid",
  loanStatus: "active",
  caches: {
    students: [],
    books: [],
    classes: [],
    categories: [],
    copies: [],
    loans: [],
    reservations: [],
    pending: [],
    schools: [],
    users: [],
    activities: []
  },
  selectedServiceStudent: null,
  notificationTimer: null,
  clockTimer: null
};

const routeMeta = {
  dashboard: ["Visão geral", "Início"],
  atendimento: ["Atendimento", "Balcão rápido"],
  emprestimos: ["Circulação", "Empréstimos"],
  reservas: ["Circulação", "Reservas"],
  pendencias: ["Acompanhamento", "Pendências"],
  livros: ["Acervo", "Livros"],
  exemplares: ["Acervo", "Exemplares"],
  alunos: ["Comunidade", "Alunos"],
  turmas: ["Comunidade", "Turmas"],
  relatorios: ["Gestão", "Relatórios"],
  atividades: ["Gestão", "Histórico de atividades"],
  escolas: ["Administração", "Escolas"],
  usuarios: ["Administração", "Contas da equipe"],
  configuracoes: ["Sistema", "Configurações"],
  perfil: ["Conta", "Meu perfil"]
};

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function normalize(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function debounce(fn, wait = 250) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), wait);
  };
}

function formatDate(value) {
  if (!value) return "—";
  const text = String(value).slice(0, 10);
  const [year, month, day] = text.split("-").map(Number);
  if (!year || !month || !day) return String(value);
  return new Intl.DateTimeFormat("pt-BR").format(new Date(year, month - 1, day));
}

function formatDateTime(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short"
  }).format(date);
}

function initials(name) {
  const parts = String(name || "BS").trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "BS";
  return (parts[0][0] + (parts.length > 1 ? parts.at(-1)[0] : "")).toUpperCase();
}

function number(value) {
  return Number(value || 0).toLocaleString("pt-BR");
}

function statusBadge(label, type = "default") {
  return `<span class="status-badge status-badge--${escapeHTML(type)}">${escapeHTML(label)}</span>`;
}

function installImageFallbacks() {
  document.addEventListener("error", event => {
    const image = event.target;
    if (!(image instanceof HTMLImageElement) || image.dataset.fallbackApplied === "1") return;
    image.dataset.fallbackApplied = "1";
    const holder = image.closest(".book-card__cover, .table-book__cover, .book-detail-cover, .popular-item__cover");
    if (!holder) return;
    image.remove();
    if (!holder.textContent.trim()) holder.innerHTML = `<span aria-hidden="true">▤</span>`;
  }, true);
}

installImageFallbacks();

function setLoading(show, text = "Preparando sua biblioteca...") {
  const loading = $("#app-loading");
  if (!loading) return;
  const paragraph = $("p", loading);
  if (paragraph) paragraph.textContent = text;
  loading.classList.toggle("is-hidden", !show);
}

function toast(message, type = "success") {
  const root = $("#toast-root");
  if (!root) return;
  const item = document.createElement("div");
  item.className = `toast toast--${type}`;
  item.innerHTML = `<span>${type === "error" ? "!" : type === "warning" ? "◷" : "✓"}</span><div><strong>${type === "error" ? "Atenção" : "BookShare"}</strong><p>${escapeHTML(message)}</p></div>`;
  root.append(item);
  requestAnimationFrame(() => item.classList.add("is-visible"));
  setTimeout(() => {
    item.classList.remove("is-visible");
    setTimeout(() => item.remove(), 250);
  }, 4200);
}

function showEmpty(container, title, message, icon = "⌕") {
  container.innerHTML = `
    <div class="empty-state">
      <div class="empty-state__content">
        <span class="empty-state__icon">${icon}</span>
        <h3>${escapeHTML(title)}</h3>
        <p>${escapeHTML(message)}</p>
      </div>
    </div>`;
}

async function api(path, options = {}) {
  const headers = { ...(options.headers || {}) };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;

  let body = options.body;
  if (body && !(body instanceof FormData) && typeof body !== "string") {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(body);
  }

  const isLogin = path === "/api/auth/login";
  const timeoutMs = Number(options.timeoutMs || (isLogin ? 45000 : 15000));
  const controller = options.signal ? null : new AbortController();
  const signal = options.signal || controller.signal;
  const timer = controller ? setTimeout(() => controller.abort(), timeoutMs) : null;

  try {
    const response = await fetch(apiUrl(path), {
      method: options.method || "GET",
      headers,
      body,
      signal
    });

    const raw = await response.text();
    let payload = {};
    try {
      payload = raw ? JSON.parse(raw) : {};
    } catch {
      payload = { message: raw || "Resposta inválida do servidor." };
    }

    if (response.status === 401) {
      logout(false);
      throw new Error(payload.message || "Sua sessão expirou. Entre novamente.");
    }

    if (!response.ok) {
      throw new Error(payload.message || `Erro ${response.status}.`);
    }

    return payload;
  } catch (error) {
    if (error?.name === "AbortError") {
      throw new Error(isLogin
        ? "O servidor demorou para responder. Aguarde alguns segundos e tente entrar novamente."
        : "Essa área demorou para responder. Tente novamente.");
    }
    if (error instanceof TypeError) {
      throw new Error("Não foi possível conectar ao servidor. Confira o Render e sua internet.");
    }
    throw error;
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function formObject(form) {
  const data = Object.fromEntries(new FormData(form).entries());
  $$('input[type="checkbox"]', form).forEach(input => {
    data[input.name] = input.checked;
  });
  return data;
}

function openDialog(id) {
  const dialog = document.getElementById(id);
  if (!dialog) return;
  if (typeof dialog.showModal === "function") {
    if (!dialog.open) dialog.showModal();
  } else {
    dialog.setAttribute("open", "");
  }
  document.body.classList.add("modal-open");
}

function closeDialog(dialogOrId) {
  const dialog = typeof dialogOrId === "string" ? document.getElementById(dialogOrId) : dialogOrId;
  if (!dialog) return;
  if (typeof dialog.close === "function" && dialog.open) dialog.close();
  else dialog.removeAttribute("open");
  if (!$("dialog[open]")) document.body.classList.remove("modal-open");
}

function closeAllDialogs() {
  $$("dialog[open]").forEach(closeDialog);
}

function confirmAction({ title = "Confirmar ação", message = "Deseja continuar?", accept = "Confirmar", danger = false }) {
  return new Promise(resolve => {
    const dialog = $("#confirm-modal");
    if (!dialog) return resolve(window.confirm(message));
    $("#confirm-title").textContent = title;
    $("#confirm-message").textContent = message;
    $("#confirm-icon").textContent = danger ? "!" : "?";
    const acceptButton = $("#confirm-accept");
    acceptButton.textContent = accept;
    acceptButton.classList.toggle("button--danger", danger);
    openDialog("confirm-modal");

    const finish = value => {
      closeDialog(dialog);
      acceptButton.onclick = null;
      $("#confirm-cancel").onclick = null;
      resolve(value);
    };
    acceptButton.onclick = () => finish(true);
    $("#confirm-cancel").onclick = () => finish(false);
  });
}

function roleIsAdmin() {
  return state.user?.role === "admin";
}

function roleIsLibrarian() {
  return state.user?.role === "librarian";
}

function studentStatus(student) {
  const value = String(student?.student_status || "").toLowerCase();
  if (["active", "blocked", "archived"].includes(value)) return value;
  return student?.active === false ? "archived" : "active";
}

function studentStatusBadge(student, overdue = 0) {
  const status = studentStatus(student);
  if (status === "blocked") return statusBadge("Bloqueado", "warning");
  if (status === "archived") return statusBadge("Arquivado", "muted");
  if (Number(overdue) > 0) return statusBadge(`${Number(overdue)} atraso(s)`, "danger");
  return statusBadge("Regular", "success");
}

function applyRoleUI() {
  const app = $("#app-view");
  if (!app || !state.user) return;
  app.classList.remove("role-admin", "role-librarian");
  app.classList.add(state.user.role === "admin" ? "role-admin" : "role-librarian");

  $$(".admin-only, .admin-only-nav").forEach(node => {
    node.classList.toggle("is-hidden", !roleIsAdmin());
  });
  $$(".librarian-only, .librarian-only-nav").forEach(node => {
    node.classList.toggle("is-hidden", !roleIsLibrarian());
  });

  $$("[data-librarian-manage]").forEach(node => node.classList.remove("is-hidden"));
}

function setUserUI() {
  if (!state.user) return;
  const name = state.user.name || "Usuária";
  const role = state.user.role === "admin" ? "Administrador" : "Bibliotecária";
  const avatar = initials(name);
  const school = state.user.school_name || "Biblioteca Escolar";

  ["sidebar-user-name", "topbar-user-name", "librarian-hero-name", "admin-hero-name"].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.textContent = name;
  });
  ["sidebar-user-role", "topbar-user-role"].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.textContent = role;
  });
  ["sidebar-avatar", "topbar-avatar", "librarian-hero-avatar", "admin-hero-avatar"].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.textContent = avatar;
  });
  const schoolName = $("#sidebar-school-name");
  if (schoolName) schoolName.textContent = school;
  const pill = $("#topbar-role-pill");
  if (pill) pill.textContent = roleIsAdmin() ? "Administração" : "Balcão";
  const adminEmail = $("#admin-hero-email");
  if (adminEmail) adminEmail.textContent = state.user.email || "";

  updateWelcomeMessage();
}

function updateWelcomeMessage() {
  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Bom dia" : hour < 18 ? "Boa tarde" : "Boa noite";
  const firstName = String(state.user?.name || "").split(" ")[0] || (roleIsAdmin() ? "Administrador" : "Bibliotecária");
  const librarianTitle = $("#librarian-welcome-title");
  const adminTitle = $("#admin-welcome-title");
  if (librarianTitle) librarianTitle.textContent = `${greeting}, ${firstName}!`;
  if (adminTitle) adminTitle.textContent = `${greeting}, ${firstName}!`;
  if ($("#final-welcome-title")) $("#final-welcome-title").textContent = `${greeting}, ${firstName}!`;
  if ($("#home-profile-name")) $("#home-profile-name").textContent = state.user.name || firstName;
  if ($("#home-profile-role")) $("#home-profile-role").textContent = roleIsAdmin() ? "Administrador" : "Bibliotecária";
  const homeAvatar = $("#home-profile-avatar");
  if (homeAvatar) homeAvatar.innerHTML = state.user.avatar_url ? `<img src="${escapeHTML(state.user.avatar_url)}" alt="">` : initials(state.user.name);
}

function showAuth() {
  $("#auth-view")?.classList.remove("is-hidden");
  $("#app-view")?.classList.add("is-hidden");
  setLoading(false);
  setTimeout(() => $("#login-email")?.focus(), 50);
}

function showApp() {
  $("#auth-view")?.classList.add("is-hidden");
  $("#app-view")?.classList.remove("is-hidden");
  setTimeout(() => setLoading(false), 250);
}

async function handleLogin(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const button = $("#login-submit");
  const email = $("#login-email").value.trim();
  const password = $("#login-password").value;

  if (!email || !password) {
    toast("Preencha o e-mail e a senha.", "warning");
    return;
  }

  button.disabled = true;
  const original = button.innerHTML;
  button.innerHTML = `<span>Entrando...</span><span class="login-submit__spinner" aria-hidden="true"></span>`;
  const slowTimer = setTimeout(() => {
    if (button.disabled) button.querySelector("span")?.replaceChildren("Iniciando servidor...");
  }, 5000);

  try {
    const payload = await api("/api/auth/login", {
      method: "POST",
      body: { email, password },
      timeoutMs: 45000
    });
    state.token = payload.token;
    state.user = payload.user;
    localStorage.setItem("bookshare_token", state.token);
    await enterApplication();
    form.reset();
  } catch (error) {
    toast(error.message, "error");
  } finally {
    clearTimeout(slowTimer);
    button.disabled = false;
    button.innerHTML = original;
  }
}

function logout(showMessage = true) {
  state.token = "";
  state.user = null;
  localStorage.removeItem("bookshare_token");
  Object.keys(state.caches).forEach(key => state.caches[key] = []);
  if (state.notificationTimer) clearInterval(state.notificationTimer);
  if (showMessage) toast("Sessão encerrada.");
  showAuth();
}

async function restoreSession() {
  if (!state.token) return showAuth();
  try {
    const payload = await api("/api/auth/me", { timeoutMs: 10000 });
    state.user = payload.user;
    await enterApplication();
  } catch {
    logout(false);
  }
}

async function enterApplication() {
  applyRoleUI();
  setUserUI();
  startClock();
  state.route = "dashboard";
  $$(".page-view").forEach(view => view.classList.add("is-hidden"));
  $("#view-dashboard")?.classList.remove("is-hidden");
  showApp();
  setLoading(false);

  Promise.allSettled([
    loadReferenceData(),
    loadNotifications(),
    loadDashboard()
  ]).then(results => {
    const failed = results.find(result => result.status === "rejected");
    if (failed) toast("Alguns dados demoraram para carregar. Você já pode usar o menu e tentar novamente.", "warning");
  });

  if (state.notificationTimer) clearInterval(state.notificationTimer);
  state.notificationTimer = setInterval(() => {
    if (state.token && roleIsLibrarian()) loadNotifications().catch(() => {});
  }, 60000);
}

function startClock() {
  if (state.clockTimer) clearInterval(state.clockTimer);
  const update = () => {
    const now = new Date();
    const date = $("#service-date");
    const time = $("#service-time");
    const topDate = $("#topbar-date-text");
    const topTime = $("#topbar-time-text");
    const dateText = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "long", year: "numeric" }).format(now);
    const timeText = new Intl.DateTimeFormat("pt-BR", { weekday: "long", hour: "2-digit", minute: "2-digit" }).format(now);
    if (date) date.textContent = new Intl.DateTimeFormat("pt-BR", { weekday: "long", day: "2-digit", month: "long" }).format(now);
    if (time) time.textContent = new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", minute: "2-digit" }).format(now);
    if (topDate) topDate.textContent = dateText;
    if (topTime) topTime.textContent = timeText;
  };
  update();
  state.clockTimer = setInterval(update, 30000);
}

async function loadReferenceData() {
  const requests = [
    api("/api/classes").then(p => state.caches.classes = p.classes || []),
    api("/api/categories").then(p => state.caches.categories = p.categories || [])
  ];
  if (roleIsAdmin()) {
    requests.push(api("/api/schools").then(p => state.caches.schools = p.schools || []));
  }
  await Promise.allSettled(requests);
  populateReferenceSelects();
}

function populateReferenceSelects() {
  const classes = state.caches.classes;
  const categories = state.caches.categories;
  const schools = state.caches.schools;

  const classOptions = classes.filter(c => c.active !== false).map(c =>
    `<option value="${escapeHTML(c.id)}">${escapeHTML(c.name)} · ${escapeHTML(c.shift || "")}</option>`
  ).join("");
  ["student-class", "loan-class-filter", "student-class-filter"].forEach(id => {
    const select = document.getElementById(id);
    if (!select) return;
    const first = select.options[0]?.outerHTML || "<option value=''>Todas as turmas</option>";
    select.innerHTML = first + classOptions;
  });

  const yearSelect = $("#class-year-filter");
  if (yearSelect) {
    const years = [...new Set(classes.map(c => Number(c.school_year)).filter(Boolean))].sort((a, b) => b - a);
    yearSelect.innerHTML = `<option value="">Todos os anos</option>${years.map(y => `<option value="${y}">${y}</option>`).join("")}`;
  }

  const categoryOptions = categories.filter(c => c.active !== false).map(c =>
    `<option value="${escapeHTML(c.id)}">${escapeHTML(c.name)}</option>`
  ).join("");
  const bookCategory = $("#book-category");
  if (bookCategory) bookCategory.innerHTML = `<option value="">Sem categoria</option>${categoryOptions}`;
  const bookCategoryFilter = $("#book-category-filter");
  if (bookCategoryFilter) bookCategoryFilter.innerHTML = `<option value="">Todas as categorias</option>${categoryOptions}`;

  const schoolSelect = $("#user-school");
  if (schoolSelect) {
    schoolSelect.innerHTML = `<option value="">Sem escola vinculada</option>${schools.map(s => `<option value="${escapeHTML(s.id)}">${escapeHTML(s.name)}</option>`).join("")}`;
  }
}

async function navigate(route) {
  if (!routeMeta[route]) route = "dashboard";
  if ((route === "escolas" || route === "usuarios") && !roleIsAdmin()) route = "dashboard";
  state.route = route;

  $$(".page-view").forEach(view => view.classList.add("is-hidden"));
  $("#view-" + route)?.classList.remove("is-hidden");
  $$("[data-route]").forEach(button => button.classList.toggle("is-active", button.dataset.route === route));

  const [eyebrow, title] = routeMeta[route];
  if ($("#page-eyebrow")) $("#page-eyebrow").textContent = eyebrow;
  if ($("#page-title")) $("#page-title").textContent = title;

  closeSidebar();
  window.scrollTo({ top: 0, behavior: "smooth" });

  const loaders = {
    dashboard: loadDashboard,
    atendimento: loadService,
    emprestimos: loadLoans,
    reservas: loadReservations,
    pendencias: loadPending,
    livros: loadBooks,
    exemplares: loadCopies,
    alunos: loadStudents,
    turmas: loadClasses,
    relatorios: loadReports,
    atividades: loadActivities,
    escolas: loadSchools,
    usuarios: loadUsers,
    configuracoes: loadSettings,
    perfil: loadProfile
  };

  try {
    await loaders[route]?.();
  } catch (error) {
    toast(error.message, "error");
  }
}

function openSidebar() {
  $("#sidebar")?.classList.add("is-open");
  $("#sidebar-overlay")?.classList.add("is-visible");
}

function closeSidebar() {
  $("#sidebar")?.classList.remove("is-open");
  $("#sidebar-overlay")?.classList.remove("is-visible");
}


async function loadDashboard() {
  const payload = await api("/api/dashboard");
  const books = payload.books || {};
  const loans = payload.loans || {};
  const students = payload.students || {};
  const reservations = payload.reservations || {};
  const admin = payload.admin || {};

  const values = {
    "metric-total-titles": books.total_titles,
    "metric-total-copies": `${number(books.total_copies)} exemplares no total`,
    "metric-active-loans": loans.active,
    "metric-due-soon": `${number(loans.due_soon)} vencendo em breve`,
    "metric-overdue-loans": loans.overdue,
    "metric-overdue-detail": Number(loans.overdue || 0) ? `Maior atraso: ${number(loans.max_overdue_days)} dia(s)` : "Nenhuma cobrança necessária",
    "metric-active-students": students.active,
    "metric-active-classes": `${number(students.classes)} turmas cadastradas`,
    "librarian-due-today": loans.due_today,
    "librarian-overdue": loans.overdue,
    "librarian-ready-reservations": reservations.ready,
    "admin-total-staff": admin.active_staff,
    "admin-total-students": admin.active_students,
    "admin-total-schools": admin.active_schools,
    "admin-total-books": admin.active_books
  };
  Object.entries(values).forEach(([id, value]) => {
    const element = document.getElementById(id);
    if (element) element.textContent = value ?? 0;
  });
  if ($("#metric-due-today-badge")) $("#metric-due-today-badge").textContent = `${number(loans.due_today)} hoje`;

  renderDashboardAlerts(payload);
  renderDueToday(payload.due_today || []);
  renderPopularBooks(payload.popular_books || []);
  renderCirculation(payload.circulation || []);

  const pendingCount = Number(loans.overdue || 0);
  const reservationCount = Number(reservations.ready || reservations.active || 0);
  updateNavCounter("#pending-nav-count", pendingCount);
  updateNavCounter("#reservations-nav-count", reservationCount);
}

function updateNavCounter(selector, value) {
  const el = $(selector);
  if (!el) return;
  el.textContent = String(value);
  el.classList.toggle("is-hidden", !Number(value));
}

function renderDashboardAlerts(payload) {
  const container = $("#dashboard-alerts");
  if (!container) return;
  const loans = payload.loans || {};
  const reservations = payload.reservations || {};
  const alerts = [];
  if (Number(loans.overdue) > 0) alerts.push(`<button class="dashboard-alert dashboard-alert--danger" data-route="pendencias"><strong>${number(loans.overdue)} devolução(ões) atrasada(s)</strong><span>Ver alunos que precisam de contato →</span></button>`);
  if (Number(loans.due_today) > 0) alerts.push(`<button class="dashboard-alert dashboard-alert--warning" data-route="emprestimos"><strong>${number(loans.due_today)} livro(s) vence(m) hoje</strong><span>Acompanhar devoluções →</span></button>`);
  if (Number(reservations.ready) > 0) alerts.push(`<button class="dashboard-alert" data-route="reservas"><strong>${number(reservations.ready)} reserva(s) pronta(s)</strong><span>Ver retiradas pendentes →</span></button>`);
  container.innerHTML = alerts.join("");
}

function renderDueToday(items) {
  const container = $("#dashboard-due-list");
  if (!container) return;
  if (!items.length) return showEmpty(container, "Nenhuma devolução hoje", "A biblioteca está em dia.", "✓");
  container.innerHTML = items.map(item => `
    <button class="list-row" data-loan-id="${escapeHTML(item.id)}">
      <span class="list-row__main"><strong>${escapeHTML(item.student_name)}</strong><small>${escapeHTML(item.book_title)} · ${escapeHTML(item.class_name || "Sem turma")}</small></span>
      <span>${formatDate(item.due_date)}</span>
    </button>`).join("");
  $$('[data-loan-id]', container).forEach(button => button.onclick = () => openLoanDetails(button.dataset.loanId));
}

function renderPopularBooks(items) {
  const container = $("#dashboard-popular-books");
  if (!container) return;
  if (!items.length) return showEmpty(container, "Sem histórico ainda", "Os livros mais emprestados aparecerão aqui.", "▤");
  container.innerHTML = items.map((item, index) => `
    <button class="popular-item" data-book-id="${escapeHTML(item.id)}">
      <span class="popular-item__rank">${index + 1}</span>
      <span class="popular-item__cover">${item.cover_url ? `<img loading="lazy" src="${escapeHTML(item.cover_url)}" alt="">` : "▤"}</span>
      <span><strong>${escapeHTML(item.title)}</strong><small>${escapeHTML(item.author)}</small></span>
      <b>${number(item.loan_count)}</b>
    </button>`).join("");
  $$('[data-book-id]', container).forEach(button => button.onclick = () => openBookDetails(button.dataset.bookId));
}

function renderCirculation(items) {
  const canvas = $("#circulation-chart");
  if (!canvas || !canvas.getContext) return;
  const context = canvas.getContext("2d");
  const width = canvas.clientWidth || 700;
  const height = canvas.clientHeight || 260;
  const ratio = window.devicePixelRatio || 1;
  canvas.width = width * ratio;
  canvas.height = height * ratio;
  context.scale(ratio, ratio);
  context.clearRect(0, 0, width, height);
  if (!items.length) return;
  const max = Math.max(1, ...items.flatMap(item => [Number(item.loans || item.loan_count || 0), Number(item.returns || item.return_count || 0)]));
  const pad = 24;
  const usableW = width - pad * 2;
  const usableH = height - pad * 2;
  context.lineWidth = 2;
  context.strokeStyle = "#2f7669";
  context.beginPath();
  items.forEach((item, i) => {
    const x = pad + (i / Math.max(1, items.length - 1)) * usableW;
    const y = pad + usableH - (Number(item.loans || item.loan_count || 0) / max) * usableH;
    if (i === 0) context.moveTo(x, y); else context.lineTo(x, y);
  });
  context.stroke();
  context.strokeStyle = "#c18d45";
  context.beginPath();
  items.forEach((item, i) => {
    const x = pad + (i / Math.max(1, items.length - 1)) * usableW;
    const y = pad + usableH - (Number(item.returns || item.return_count || 0) / max) * usableH;
    if (i === 0) context.moveTo(x, y); else context.lineTo(x, y);
  });
  context.stroke();
}


async function loadNotifications() {
  if (!state.token || !roleIsLibrarian()) {
    $("#notification-dot")?.classList.add("is-hidden");
    return;
  }
  const payload = await api("/api/notifications");
  const items = payload.notifications || [];
  const list = $("#notification-list");
  if (!list) return;
  $("#notification-dot")?.classList.toggle("is-hidden", !items.length);
  if (!items.length) return showEmpty(list, "Tudo em dia", "Nenhuma notificação importante agora.", "✓");
  list.innerHTML = items.map(item => `
    <button class="notification-item notification-item--${escapeHTML(item.type || "default")}" data-notification-route="${escapeHTML(item.route || "dashboard")}">
      <span class="notification-item__icon">${escapeHTML(item.icon || "•")}</span>
      <span><strong>${escapeHTML(item.title)}</strong><p>${escapeHTML(item.message)}</p><small>${escapeHTML(item.time || "")}</small></span>
    </button>`).join("");
  $$('[data-notification-route]', list).forEach(button => button.onclick = () => {
    $("#notification-panel")?.classList.remove("is-open");
    navigate(button.dataset.notificationRoute);
  });
}

function toggleNotificationPanel(force) {
  const panel = $("#notification-panel");
  if (!panel) return;
  const open = typeof force === "boolean" ? force : !panel.classList.contains("is-open");
  panel.classList.toggle("is-open", open);
  if (open) loadNotifications().catch(error => toast(error.message, "error"));
}


async function loadService() {
  if (!state.caches.students.length) await fetchStudents();
  renderServiceSearch();
}

function renderServiceSearch() {
  const input = $("#service-student-search");
  const results = $("#service-student-results");
  if (!input || !results) return;
  const query = normalize(input.value);
  const students = state.caches.students
    .filter(student => student.active !== false)
    .filter(student => !query || normalize(`${student.full_name} ${student.registration_number} ${student.class_name}`).includes(query))
    .slice(0, 12);

  if (!students.length) return showEmpty(results, "Aluno não encontrado", "Digite parte do nome ou da matrícula.", "⌕");
  results.innerHTML = students.map(student => `
    <button class="service-result" data-service-student="${escapeHTML(student.id)}">
      <span class="card-identity__avatar">${escapeHTML(initials(student.full_name))}</span>
      <span><strong>${escapeHTML(student.full_name)}</strong><small>${escapeHTML(student.class_name || "Sem turma")} · ${escapeHTML(student.registration_number)}</small></span>
      <b>→</b>
    </button>`).join("");
  $$('[data-service-student]', results).forEach(button => button.onclick = () => selectServiceStudent(button.dataset.serviceStudent));
}

async function selectServiceStudent(id) {
  try {
    const payload = await api(`/api/students/${id}`);
    state.selectedServiceStudent = payload.student;
    renderServiceStudent(payload);
  } catch (error) {
    toast(error.message, "error");
  }
}

function renderServiceStudent(payload) {
  const container = $("#service-student-summary");
  if (!container) return;
  const student = payload.student || {};
  const activeLoans = payload.active_loans || [];
  const overdue = activeLoans.filter(loan => Number(loan.overdue_days || 0) > 0);
  container.innerHTML = `
    <div class="service-student-card">
      <div class="service-student-card__head">
        <span class="card-identity__avatar">${escapeHTML(initials(student.full_name))}</span>
        <div><p class="eyebrow">Aluno selecionado</p><h3>${escapeHTML(student.full_name)}</h3><small>${escapeHTML(student.class_name || "Sem turma")} · Matrícula ${escapeHTML(student.registration_number)}</small></div>
      </div>
      <div class="student-card__stats">
        <div><strong>${activeLoans.length}</strong><span>emprestados</span></div>
        <div><strong>${overdue.length}</strong><span>atrasados</span></div>
        <div><strong>${(payload.notices || []).length}</strong><span>contatos</span></div>
      </div>
      <div class="card-actions">
        <button class="button button--primary" data-service-action="loan">＋ Emprestar livro</button>
        <button class="button button--secondary" data-service-action="return">↵ Receber devolução</button>
        <button class="button button--ghost" data-service-action="history">Ver histórico</button>
        <button class="button button--ghost" data-service-action="edit">Editar aluno</button>
      </div>
    </div>`;
  $('[data-service-action="loan"]', container).onclick = () => openLoanModal({ studentId: student.id });
  $('[data-service-action="return"]', container).onclick = () => openReturnSearch(student.full_name);
  $('[data-service-action="history"]', container).onclick = () => openStudentDetails(student.id);
  $('[data-service-action="edit"]', container).onclick = () => openStudentEdit(student.id);
}


async function fetchStudents(force = false) {
  if (state.caches.students.length && !force) return state.caches.students;
  const payload = await api("/api/students");
  state.caches.students = payload.students || [];
  populateStudentAndLoanSelects();
  return state.caches.students;
}

function populateStudentAndLoanSelects() {
  const students = state.caches.students.filter(student => studentStatus(student) === "active");
  const options = students.map(student => `<option value="${escapeHTML(student.id)}">${escapeHTML(student.full_name)} · ${escapeHTML(student.class_name || "Sem turma")}</option>`).join("");
  ["loan-student", "reservation-student"].forEach(id => {
    const select = document.getElementById(id);
    if (select) select.innerHTML = `<option value="">Selecione um aluno</option>${options}`;
  });
}

async function loadStudents(force = false) {
  await fetchStudents(force);
  renderStudents();
}

function getFilteredStudents() {
  const query = normalize($("#student-search")?.value);
  const classId = $("#student-class-filter")?.value || "";
  const status = $("#student-status-filter")?.value || "active";
  return state.caches.students.filter(student => {
    if (query && !normalize(`${student.full_name} ${student.registration_number} ${student.guardian_contact || ""}`).includes(query)) return false;
    if (classId && String(student.class_id) !== String(classId)) return false;
    const lifecycle = studentStatus(student);
    if (status === "active" && lifecycle !== "active") return false;
    if (status === "blocked" && lifecycle !== "blocked") return false;
    if (status === "archived" && lifecycle !== "archived") return false;
    if (status === "pending" && (lifecycle !== "active" || Number(student.overdue_loans || 0) < 1)) return false;
    return true;
  });
}

function renderStudents() {
  const container = $("#students-container");
  if (!container) return;
  const students = getFilteredStudents();
  if (!students.length) return showEmpty(container, "Nenhum aluno encontrado", "Ajuste os filtros ou cadastre um novo aluno.", "♙");

  container.innerHTML = students.slice(0, 120).map(student => {
    const overdue = Number(student.overdue_loans || 0);
    return `
      <article class="student-card">
        <div class="student-card__header">
          <div class="card-identity">
            <span class="card-identity__avatar">${student.photo_url ? `<img loading="lazy" src="${escapeHTML(student.photo_url)}" alt="">` : escapeHTML(initials(student.full_name))}</span>
            <div><h3>${escapeHTML(student.full_name)}</h3><p>${escapeHTML(student.class_name || "Sem turma")} · nº ${escapeHTML(student.roll_number || "—")}</p><small>Matrícula ${escapeHTML(student.registration_number)}</small></div>
          </div>
          ${studentStatusBadge(student, overdue)}
        </div>
        <div class="student-card__stats">
          <div><strong>${number(student.active_loans)}</strong><span>emprestados</span></div>
          <div><strong>${number(student.total_loans)}</strong><span>no histórico</span></div>
          <div><strong>${escapeHTML(student.guardian_contact || "—")}</strong><span>contato</span></div>
        </div>
        <div class="card-actions">
          <button class="button button--primary" data-student-loan="${escapeHTML(student.id)}" ${studentStatus(student) !== "active" ? "disabled" : ""}>Emprestar</button>
          <button class="button button--secondary" data-student-detail="${escapeHTML(student.id)}">Ver aluno</button>
          <button class="button button--ghost" data-student-edit="${escapeHTML(student.id)}">Editar</button>
        </div>
      </article>`;
  }).join("");

  $$('[data-student-loan]', container).forEach(button => button.onclick = () => openLoanModal({ studentId: button.dataset.studentLoan }));
  $$('[data-student-detail]', container).forEach(button => button.onclick = () => openStudentDetails(button.dataset.studentDetail));
  $$('[data-student-edit]', container).forEach(button => button.onclick = () => openStudentEdit(button.dataset.studentEdit));
}

async function openStudentDetails(id) {
  const payload = await api(`/api/students/${id}`);
  const student = payload.student || {};
  const activeLoans = payload.active_loans || [];
  const history = payload.history || [];
  const notices = payload.notices || [];
  const overdue = activeLoans.filter(item => Number(item.overdue_days || 0) > 0);
  const lifecycle = studentStatus(student);
  const lifecycleLabel = lifecycle === "blocked" ? "Bloqueado" : lifecycle === "archived" ? "Arquivado" : overdue.length ? `${overdue.length} atraso(s)` : "Regular";

  $("#detail-modal-eyebrow").textContent = "Aluno";
  $("#detail-modal-title").textContent = student.full_name || "Aluno";
  $("#detail-modal-subtitle").textContent = `${student.class_name || "Sem turma"} · Matrícula ${student.registration_number || "—"}`;
  $("#detail-modal-content").innerHTML = `
    <div class="detail-summary-grid">
      <div><span>Situação</span><strong>${escapeHTML(lifecycleLabel)}</strong></div>
      <div><span>Livros atuais</span><strong>${activeLoans.length}</strong></div>
      <div><span>Contato</span><strong>${escapeHTML(student.guardian_contact || "Não informado")}</strong></div>
      <div><span>Histórico</span><strong>${history.length}</strong></div>
    </div>
    <div class="detail-actions">
      <button class="button button--primary" data-detail-student-loan ${lifecycle !== "active" ? "disabled" : ""}>＋ Emprestar livro</button>
      <button class="button button--secondary" data-detail-student-edit>Editar aluno</button>
      ${lifecycle === "archived" && !roleIsAdmin() ? "" : `<button class="button button--ghost" data-detail-student-status>${lifecycle === "active" ? "Bloquear aluno" : "Reativar aluno"}</button>`}
      ${roleIsAdmin() ? `<button class="button button--danger" data-detail-student-archive ${lifecycle === "archived" ? "disabled" : ""}>Arquivar cadastro</button>` : ""}
    </div>
    <section class="detail-section"><h3>Livros atuais</h3>${activeLoans.length ? activeLoans.map(item => `<div class="detail-row"><div><strong>${escapeHTML(item.book_title)}</strong><small>${escapeHTML(item.inventory_code || "")} · devolução ${formatDate(item.due_date)}</small></div>${Number(item.overdue_days || 0) > 0 ? statusBadge(`${item.overdue_days} dia(s) atrasado`, "danger") : statusBadge("Em dia", "success")}</div>`).join("") : `<p class="muted-text">Nenhum empréstimo ativo.</p>`}</section>
    <section class="detail-section"><h3>Histórico recente</h3>${history.slice(0, 12).map(item => `<div class="detail-row"><div><strong>${escapeHTML(item.book_title)}</strong><small>${formatDate(item.loan_date)} → ${item.returned_at ? formatDate(item.returned_at) : "Em aberto"}</small></div>${statusBadge(item.status === "active" ? "Ativo" : "Devolvido", item.status === "active" ? "warning" : "muted")}</div>`).join("") || `<p class="muted-text">Sem histórico.</p>`}</section>
    <section class="detail-section"><h3>Contatos de cobrança</h3>${notices.slice(0, 10).map(item => `<div class="detail-row"><div><strong>${escapeHTML(item.channel || "Contato")}</strong><small>${formatDateTime(item.created_at)} · ${escapeHTML(item.result || "registrado")}</small></div></div>`).join("") || `<p class="muted-text">Nenhum contato registrado.</p>`}</section>`;
  $("[data-detail-student-loan]").onclick = () => { closeDialog("detail-modal"); openLoanModal({ studentId: student.id }); };
  $("[data-detail-student-edit]").onclick = () => { closeDialog("detail-modal"); openStudentEdit(student.id); };
  const lifecycleButton = $("[data-detail-student-status]");
  if (lifecycleButton) lifecycleButton.onclick = async () => {
    const activate = lifecycle !== "active";
    const ok = await confirmAction(
      activate ? "Reativar aluno" : "Bloquear aluno",
      activate
        ? `Deseja reativar ${student.full_name}? Ele poderá voltar a realizar empréstimos.`
        : `Deseja bloquear ${student.full_name}? O histórico será preservado e novos empréstimos ficarão indisponíveis.`,
      activate ? "Reativar" : "Bloquear"
    );
    if (!ok) return;
    try {
      await api(`/api/students/${student.id}/status`, { method: "PUT", body: { status: activate ? "active" : "blocked" } });
      toast(activate ? "Aluno reativado." : "Aluno bloqueado.");
      closeDialog("detail-modal");
      await loadStudents(true);
    } catch (error) { toast(error.message, "error"); }
  };
  const archiveButton = $("[data-detail-student-archive]");
  if (archiveButton) archiveButton.onclick = async () => {
    const ok = await confirmAction(
      "Arquivar cadastro",
      `Arquivar ${student.full_name}? O cadastro sairá da lista de alunos ativos, mas o histórico de empréstimos, reservas e cobranças será mantido.`,
      "Arquivar"
    );
    if (!ok) return;
    try {
      await api(`/api/students/${student.id}`, { method: "DELETE" });
      toast("Cadastro do aluno arquivado.");
      closeDialog("detail-modal");
      await loadStudents(true);
    } catch (error) { toast(error.message, "error"); }
  };
  openDialog("detail-modal");
}

async function openStudentEdit(id) {
  const student = state.caches.students.find(item => String(item.id) === String(id)) || (await api(`/api/students/${id}`)).student;
  const form = $("#student-form");
  form.reset();
  form.elements.id.value = student.id;
  form.elements.full_name.value = student.full_name || "";
  form.elements.registration_number.value = student.registration_number || "";
  form.elements.class_id.value = student.class_id || "";
  form.elements.roll_number.value = student.roll_number || "";
  form.elements.guardian_contact.value = student.guardian_contact || "";
  form.elements.notes.value = student.notes || "";
  $("#student-photo-url").value = student.photo_url || "";
  updateStudentPhotoPreview(student.photo_url);
  $("#student-modal-title").textContent = "Editar aluno";
  openDialog("student-modal");
}

function prepareNewStudentModal() {
  const form = $("#student-form");
  form.reset();
  form.elements.id.value = "";
  $("#student-photo-url").value = "";
  updateStudentPhotoPreview("");
  $("#student-modal-title").textContent = "Cadastrar aluno";
}

async function saveStudent(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const data = formObject(form);
  const id = data.id;
  delete data.id;
  data.roll_number = data.roll_number ? Number(data.roll_number) : null;
  try {
    await api(id ? `/api/students/${id}` : "/api/students", { method: id ? "PUT" : "POST", body: data });
    toast(id ? "Aluno atualizado." : "Aluno cadastrado.");
    closeDialog("student-modal");
    await loadStudents(true);
    if (state.route === "atendimento") renderServiceSearch();
  } catch (error) {
    toast(error.message, "error");
  }
}

function updateStudentPhotoPreview(url) {
  const preview = $("#student-photo-preview");
  if (!preview) return;
  preview.innerHTML = url ? `<img src="${escapeHTML(url)}" alt="Foto do aluno">` : `<span>♙</span>`;
}

function handleStudentPhotoFile(event) {
  const file = event.target.files?.[0];
  if (!file) return;
  if (file.size > 900000) return toast("Use uma foto menor que 900 KB para manter o app leve.", "warning");
  const reader = new FileReader();
  reader.onload = () => {
    $("#student-photo-url").value = reader.result;
    updateStudentPhotoPreview(reader.result);
  };
  reader.readAsDataURL(file);
}


async function fetchBooks(force = false) {
  if (state.caches.books.length && !force) return state.caches.books;
  const payload = await api("/api/books");
  state.caches.books = payload.books || [];
  populateBookSelects();
  return state.caches.books;
}

function populateBookSelects() {
  const books = state.caches.books.filter(book => book.active !== false);
  const options = books.map(book => `<option value="${escapeHTML(book.id)}">${escapeHTML(book.title)} · ${escapeHTML(book.author)}</option>`).join("");
  ["loan-book", "reservation-book", "copy-book"].forEach(id => {
    const select = document.getElementById(id);
    if (select) select.innerHTML = `<option value="">Selecione um livro</option>${options}`;
  });
}

async function loadBooks(force = false) {
  await fetchBooks(force);
  renderBooks();
}

function filteredBooks() {
  const query = normalize($("#book-search")?.value);
  const category = $("#book-category-filter")?.value || "";
  const availability = $("#book-availability-filter")?.value || "";
  return state.caches.books.filter(book => {
    if (query && !normalize(`${book.title} ${book.author} ${book.isbn || ""} ${book.publisher || ""}`).includes(query)) return false;
    if (category && String(book.category_id) !== String(category)) return false;
    const available = Number(book.available_copies || 0);
    if (availability === "available" && available < 1) return false;
    if (availability === "unavailable" && available > 0) return false;
    return true;
  });
}

function renderBooks() {
  const container = $("#books-container");
  if (!container) return;
  const books = filteredBooks();
  const summary = $("#books-summary");
  if (summary) summary.textContent = `${number(books.length)} título(s) exibido(s) · ${number(books.reduce((sum, book) => sum + Number(book.total_copies || 0), 0))} exemplares`;
  if (!books.length) return showEmpty(container, "Nenhum livro encontrado", "Tente outro termo ou cadastre um novo livro.", "▤");

  if (state.bookView === "table") {
    container.className = "table-card";
    container.innerHTML = `<div class="table-scroll"><table class="data-table"><thead><tr><th>Livro</th><th>Categoria</th><th>Local</th><th>Disponíveis</th><th></th></tr></thead><tbody>${books.slice(0, 180).map(book => `<tr><td><div class="table-book"><span class="table-book__cover">${book.cover_url ? `<img loading="lazy" src="${escapeHTML(book.cover_url)}" alt="">` : "▤"}</span><span><strong>${escapeHTML(book.title)}</strong><small>${escapeHTML(book.author)}</small></span></div></td><td>${escapeHTML(book.category_name || "—")}</td><td>${escapeHTML(book.shelf || "—")}</td><td>${number(book.available_copies)} / ${number(book.total_copies)}</td><td><button class="button button--small button--secondary" data-book-detail="${escapeHTML(book.id)}">Ver</button></td></tr>`).join("")}</tbody></table></div>`;
  } else {
    container.className = "book-grid";
    container.innerHTML = books.slice(0, 120).map(book => `
      <article class="book-card">
        <div class="book-card__cover">
          ${book.cover_url ? `<img loading="lazy" decoding="async" src="${escapeHTML(book.cover_url)}" alt="Capa de ${escapeHTML(book.title)}">` : `<div class="book-card__placeholder"><span>▤</span><small>Capa sendo sincronizada</small></div>`}
          <span class="book-card__status">${Number(book.available_copies) > 0 ? statusBadge(`${book.available_copies} disponível(is)`, "success") : statusBadge("Sem exemplar livre", "warning")}</span>
        </div>
        <div class="book-card__body">
          <h3>${escapeHTML(book.title)}</h3>
          <p class="book-card__author">${escapeHTML(book.author)}</p>
          <div class="book-card__meta"><div><span>Exemplares</span><strong>${number(book.total_copies)}</strong></div><div><span>Estante</span><strong>${escapeHTML(book.shelf || "—")}</strong></div></div>
          <div class="book-card__actions">
            <button class="button button--secondary" data-book-detail="${escapeHTML(book.id)}">Detalhes</button>
            <button class="button button--primary" data-book-loan="${escapeHTML(book.id)}" ${Number(book.available_copies) < 1 ? "disabled" : ""}>Emprestar</button>
            <button class="button button--ghost" data-book-edit="${escapeHTML(book.id)}">Editar</button>
          </div>
        </div>
      </article>`).join("");
  }

  $$('[data-book-detail]', container).forEach(button => button.onclick = () => openBookDetails(button.dataset.bookDetail));
  $$('[data-book-loan]', container).forEach(button => button.onclick = () => openLoanModal({ bookId: button.dataset.bookLoan }));
  $$('[data-book-edit]', container).forEach(button => button.onclick = () => openBookEdit(button.dataset.bookEdit));
}

async function openBookDetails(id) {
  const payload = await api(`/api/books/${id}`);
  const book = payload.book || {};
  const copies = payload.copies || [];
  const recent = payload.recent_loans || [];
  $("#detail-modal-eyebrow").textContent = "Livro";
  $("#detail-modal-title").textContent = book.title || "Livro";
  $("#detail-modal-subtitle").textContent = `${book.author || "Autor não informado"} · ${book.category_name || "Sem categoria"}`;
  $("#detail-modal-content").innerHTML = `
    <div class="book-detail-hero">
      <div class="book-detail-cover">${book.cover_url ? `<img loading="lazy" src="${escapeHTML(book.cover_url)}" alt="">` : "▤"}</div>
      <div><p><strong>ISBN:</strong> ${escapeHTML(book.isbn || "—")}</p><p><strong>Editora:</strong> ${escapeHTML(book.publisher || "—")}</p><p><strong>Estante:</strong> ${escapeHTML(book.shelf || "—")}</p><p>${escapeHTML(book.description || "Sem descrição cadastrada.")}</p></div>
    </div>
    <div class="detail-summary-grid"><div><span>Exemplares</span><strong>${copies.length}</strong></div><div><span>Disponíveis</span><strong>${copies.filter(copy => copy.status === "available").length}</strong></div><div><span>Emprestados</span><strong>${copies.filter(copy => copy.status === "loaned").length}</strong></div><div><span>Empréstimos</span><strong>${number(book.total_loan_count)}</strong></div></div>
    <div class="detail-actions"><button class="button button--primary" data-detail-book-loan ${copies.some(copy => copy.status === "available") ? "" : "disabled"}>Emprestar</button><button class="button button--secondary" data-detail-book-edit>Editar livro</button><button class="button button--ghost" data-detail-add-copy>＋ Exemplares</button></div>
    <section class="detail-section"><h3>Exemplares</h3>${copies.map(copy => `<div class="detail-row"><div><strong>${escapeHTML(copy.inventory_code)}</strong><small>${escapeHTML(copy.condition_notes || "Sem observações")}</small></div>${statusBadge(copy.status, copy.status === "available" ? "success" : copy.status === "loaned" ? "warning" : copy.status === "lost" ? "danger" : "muted")}</div>`).join("")}</section>
    <section class="detail-section"><h3>Movimentações recentes</h3>${recent.slice(0, 8).map(item => `<div class="detail-row"><div><strong>${escapeHTML(item.student_name || "Aluno")}</strong><small>${formatDate(item.loan_date)} · ${escapeHTML(item.inventory_code || "")}</small></div></div>`).join("") || `<p class="muted-text">Nenhum empréstimo registrado.</p>`}</section>`;
  $("[data-detail-book-loan]").onclick = () => { closeDialog("detail-modal"); openLoanModal({ bookId: book.id }); };
  $("[data-detail-book-edit]").onclick = () => { closeDialog("detail-modal"); openBookEdit(book.id); };
  $("[data-detail-add-copy]").onclick = () => { closeDialog("detail-modal"); prepareCopyModal(book.id); openDialog("copy-modal"); };
  openDialog("detail-modal");
}

function prepareNewBookModal() {
  const form = $("#book-form");
  form.reset();
  form.elements.id.value = "";
  $("#book-modal-title").textContent = "Cadastrar livro";
  $("#book-cover-preview").innerHTML = `<span>▤</span>`;
}

async function openBookEdit(id) {
  const payload = await api(`/api/books/${id}`);
  const book = payload.book;
  const form = $("#book-form");
  form.reset();
  for (const key of ["id", "title", "author", "category_id", "isbn", "publisher", "publication_year", "shelf", "cover_url", "description"]) {
    if (form.elements[key]) form.elements[key].value = book[key] ?? "";
  }
  if (form.elements.quantity) form.elements.quantity.value = 0;
  $("#book-modal-title").textContent = "Editar livro";
  $("#book-cover-preview").innerHTML = book.cover_url ? `<img src="${escapeHTML(book.cover_url)}" alt="Capa">` : `<span>▤</span>`;
  openDialog("book-modal");
}

async function saveBook(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const data = formObject(form);
  const id = data.id;
  delete data.id;
  data.publication_year = data.publication_year ? Number(data.publication_year) : null;
  data.quantity = Math.max(0, Number(data.quantity || 0));
  try {
    await api(id ? `/api/books/${id}` : "/api/books", { method: id ? "PUT" : "POST", body: data });
    toast(id ? "Livro atualizado." : "Livro cadastrado.");
    closeDialog("book-modal");
    await loadBooks(true);
  } catch (error) {
    toast(error.message, "error");
  }
}

function prepareCopyModal(bookId = "") {
  const form = $("#copy-form");
  form.reset();
  if (bookId) $("#copy-book").value = bookId;
  const acquired = form.elements.acquired_at;
  if (acquired) acquired.value = new Date().toISOString().slice(0, 10);
}

async function saveCopies(event) {
  event.preventDefault();
  const data = formObject(event.currentTarget);
  data.quantity = Number(data.quantity || 1);
  try {
    await api("/api/copies", { method: "POST", body: data });
    toast(`${data.quantity} exemplar(es) cadastrado(s).`);
    closeDialog("copy-modal");
    state.caches.copies = [];
    await loadBooks(true);
    if (state.route === "exemplares") await loadCopies(true);
  } catch (error) {
    toast(error.message, "error");
  }
}

async function loadCopies(force = false) {
  if (!state.caches.copies.length || force) {
    const payload = await api("/api/copies");
    state.caches.copies = payload.copies || [];
  }
  const query = normalize($("#copy-search")?.value);
  const status = $("#copy-status-filter")?.value || "";
  const items = state.caches.copies.filter(copy => {
    if (query && !normalize(`${copy.inventory_code} ${copy.book_title} ${copy.book_author}`).includes(query)) return false;
    if (status && copy.status !== status) return false;
    return true;
  });
  const container = $("#copies-container");
  if (!container) return;
  if (!items.length) return showEmpty(container, "Nenhum exemplar encontrado", "Ajuste os filtros ou cadastre exemplares.", "▥");
  container.innerHTML = `<div class="table-card"><div class="table-scroll"><table class="data-table"><thead><tr><th>Patrimônio</th><th>Livro</th><th>Situação</th><th>Aquisição</th><th></th></tr></thead><tbody>${items.slice(0, 200).map(copy => `<tr><td><strong>${escapeHTML(copy.inventory_code)}</strong></td><td>${escapeHTML(copy.book_title)}<br><small>${escapeHTML(copy.book_author || "")}</small></td><td>${statusBadge(copy.status, copy.status === "available" ? "success" : copy.status === "loaned" ? "warning" : copy.status === "lost" ? "danger" : "muted")}</td><td>${formatDate(copy.acquired_at)}</td><td><select class="select-control select-control--small" data-copy-status="${escapeHTML(copy.id)}"><option value="available" ${copy.status === "available" ? "selected" : ""}>Disponível</option><option value="damaged" ${copy.status === "damaged" ? "selected" : ""}>Danificado</option><option value="lost" ${copy.status === "lost" ? "selected" : ""}>Perdido</option><option value="maintenance" ${copy.status === "maintenance" ? "selected" : ""}>Manutenção</option></select></td></tr>`).join("")}</tbody></table></div></div>`;
  $$('[data-copy-status]', container).forEach(select => select.onchange = () => changeCopyStatus(select.dataset.copyStatus, select.value));
}

async function changeCopyStatus(id, status) {
  try {
    await api(`/api/copies/${id}/status`, { method: "PUT", body: { status } });
    toast("Situação do exemplar atualizada.");
    await loadCopies(true);
    state.caches.books = [];
  } catch (error) {
    toast(error.message, "error");
  }
}

async function syncBookCovers() {
  const button = $("#sync-covers-button");
  if (!button) return;
  button.disabled = true;
  const original = button.textContent;
  button.textContent = "Atualizando...";
  try {
    const payload = await api("/api/admin/book-covers/sync", { method: "POST", body: { force: true } });
    toast(payload.message || "Sincronização de capas iniciada.");
    if ($("#cover-sync-status")) $("#cover-sync-status").textContent = "Buscando capas originais em segundo plano...";
    setTimeout(() => loadBooks(true).catch(() => {}), 6000);
  } catch (error) {
    toast(error.message, "error");
  } finally {
    button.disabled = false;
    button.textContent = original;
  }
}


async function fetchLoans(force = false) {
  if (state.caches.loans.length && !force) return state.caches.loans;
  const payload = await api("/api/loans");
  state.caches.loans = payload.loans || [];
  return state.caches.loans;
}

async function loadLoans(force = false) {
  await fetchLoans(force);
  renderLoans();
}

function filteredLoans() {
  const query = normalize($("#loan-search")?.value);
  const classId = $("#loan-class-filter")?.value || "";
  const start = $("#loan-start-date")?.value || "";
  const end = $("#loan-end-date")?.value || "";
  return state.caches.loans.filter(loan => {
    const overdue = loan.status === "active" && Number(loan.overdue_days || 0) > 0;
    if (state.loanStatus === "active" && loan.status !== "active") return false;
    if (state.loanStatus === "overdue" && !overdue) return false;
    if (state.loanStatus === "returned" && loan.status === "active") return false;
    if (query && !normalize(`${loan.student_name} ${loan.registration_number} ${loan.book_title} ${loan.inventory_code}`).includes(query)) return false;
    if (classId && String(loan.class_id) !== String(classId)) return false;
    const date = String(loan.loan_date || "").slice(0, 10);
    if (start && date < start) return false;
    if (end && date > end) return false;
    return true;
  });
}

function renderLoans() {
  const container = $("#loans-container");
  if (!container) return;
  const loans = filteredLoans();
  if ($("#loans-summary")) $("#loans-summary").textContent = `${number(loans.length)} registro(s)`;
  if (!loans.length) return showEmpty(container, "Nenhum empréstimo encontrado", "Ajuste os filtros ou registre um novo empréstimo.", "⇄");

  container.innerHTML = `<div class="table-card"><div class="table-scroll"><table class="data-table"><thead><tr><th>Aluno</th><th>Livro</th><th>Prazo</th><th>Situação</th><th>Ações</th></tr></thead><tbody>${loans.slice(0, 220).map(loan => {
    const overdue = loan.status === "active" && Number(loan.overdue_days || 0) > 0;
    return `<tr><td><strong>${escapeHTML(loan.student_name)}</strong><br><small>${escapeHTML(loan.class_name || "Sem turma")} · ${escapeHTML(loan.registration_number)}</small></td><td><strong>${escapeHTML(loan.book_title)}</strong><br><small>${escapeHTML(loan.inventory_code)}</small></td><td>${formatDate(loan.due_date)}${overdue ? `<br><small class="text-danger">${loan.overdue_days} dia(s) de atraso</small>` : ""}</td><td>${loan.status === "active" ? overdue ? statusBadge("Atrasado", "danger") : statusBadge("Ativo", "success") : statusBadge("Devolvido", "muted")}</td><td><div class="table-actions"><button class="button button--small button--secondary" data-loan-detail="${escapeHTML(loan.id)}">Ver</button>${loan.status === "active" ? `<button class="button button--small button--primary" data-loan-return="${escapeHTML(loan.id)}">Devolver</button><button class="button button--small button--ghost" data-loan-renew="${escapeHTML(loan.id)}">Renovar</button>` : ""}</div></td></tr>`;
  }).join("")}</tbody></table></div></div>`;
  $$('[data-loan-detail]', container).forEach(button => button.onclick = () => openLoanDetails(button.dataset.loanDetail));
  $$('[data-loan-return]', container).forEach(button => button.onclick = () => openReturnModal(button.dataset.loanReturn));
  $$('[data-loan-renew]', container).forEach(button => button.onclick = () => renewLoan(button.dataset.loanRenew));
}

async function openLoanDetails(id) {
  const payload = await api(`/api/loans/${id}`);
  const loan = payload.loan;
  const notices = payload.notices || [];
  $("#detail-modal-eyebrow").textContent = "Empréstimo";
  $("#detail-modal-title").textContent = loan.book_title || "Empréstimo";
  $("#detail-modal-subtitle").textContent = `${loan.student_name} · ${loan.inventory_code}`;
  $("#detail-modal-content").innerHTML = `
    <div class="detail-summary-grid"><div><span>Empréstimo</span><strong>${formatDate(loan.loan_date)}</strong></div><div><span>Devolução</span><strong>${formatDate(loan.due_date)}</strong></div><div><span>Renovações</span><strong>${number(loan.renewal_count)}</strong></div><div><span>Situação</span><strong>${loan.status === "active" ? "Ativo" : "Devolvido"}</strong></div></div>
    ${loan.status === "active" ? `<div class="detail-actions"><button class="button button--primary" data-detail-return>Receber devolução</button><button class="button button--secondary" data-detail-renew>Renovar</button>${Number(loan.overdue_days || 0) > 0 ? `<button class="button button--ghost" data-detail-notice>Registrar cobrança</button>` : ""}</div>` : ""}
    <section class="detail-section"><h3>Histórico de cobrança</h3>${notices.length ? notices.map(item => `<div class="detail-row"><div><strong>${escapeHTML(item.channel || "Contato")}</strong><small>${formatDateTime(item.created_at)} · ${escapeHTML(item.result || "registrado")}</small><p>${escapeHTML(item.notes || "")}</p></div></div>`).join("") : `<p class="muted-text">Nenhum contato registrado.</p>`}</section>`;
  $("[data-detail-return]")?.addEventListener("click", () => { closeDialog("detail-modal"); openReturnModal(id); }, { once: true });
  $("[data-detail-renew]")?.addEventListener("click", () => { closeDialog("detail-modal"); renewLoan(id); }, { once: true });
  $("[data-detail-notice]")?.addEventListener("click", () => { closeDialog("detail-modal"); openNoticeModal(id); }, { once: true });
  openDialog("detail-modal");
}

async function openLoanModal(prefill = {}) {
  await Promise.all([fetchStudents(), fetchBooks()]);
  const form = $("#loan-form");
  form.reset();
  const today = new Date();
  const due = new Date(today);
  due.setDate(due.getDate() + 14);
  $("#loan-date").value = today.toISOString().slice(0, 10);
  $("#loan-due-date").value = due.toISOString().slice(0, 10);
  if (prefill.studentId) $("#loan-student").value = prefill.studentId;
  if (prefill.bookId) $("#loan-book").value = prefill.bookId;
  updateLoanStudentStatus();
  openDialog("loan-modal");
}

function updateLoanStudentStatus() {
  const id = $("#loan-student")?.value;
  const preview = $("#loan-student-status");
  if (!preview) return;
  const student = state.caches.students.find(item => String(item.id) === String(id));
  if (!student) return preview.classList.add("is-hidden");
  preview.classList.remove("is-hidden");
  preview.innerHTML = `<strong>${escapeHTML(student.full_name)}</strong><span>${Number(student.overdue_loans || 0) ? `${student.overdue_loans} atraso(s) — regularize antes de um novo empréstimo.` : `${student.active_loans || 0} empréstimo(s) ativo(s) · situação regular.`}</span>`;
}

async function saveLoan(event) {
  event.preventDefault();
  const data = formObject(event.currentTarget);
  try {
    await api("/api/loans", { method: "POST", body: data });
    toast("Empréstimo registrado com sucesso.");
    closeDialog("loan-modal");
    state.caches.loans = [];
    state.caches.students = [];
    state.caches.books = [];
    await Promise.allSettled([loadDashboard(), loadNotifications()]);
    if (state.route === "emprestimos") await loadLoans(true);
  } catch (error) {
    toast(error.message, "error");
  }
}

async function openReturnSearch(initial = "") {
  await fetchLoans(true);
  $("#return-search-input").value = initial;
  renderReturnSearchResults();
  openDialog("return-search-modal");
  setTimeout(() => $("#return-search-input")?.focus(), 50);
}

function renderReturnSearchResults() {
  const query = normalize($("#return-search-input")?.value);
  const items = state.caches.loans.filter(loan => loan.status === "active" && (!query || normalize(`${loan.student_name} ${loan.book_title} ${loan.inventory_code}`).includes(query))).slice(0, 30);
  const container = $("#return-search-results");
  if (!items.length) return showEmpty(container, "Nenhum empréstimo ativo", "Busque pelo aluno, livro ou patrimônio.", "⌕");
  container.innerHTML = items.map(loan => `<button class="return-result" data-return-id="${escapeHTML(loan.id)}"><span><strong>${escapeHTML(loan.student_name)}</strong><small>${escapeHTML(loan.book_title)} · ${escapeHTML(loan.inventory_code)}</small></span><span>${formatDate(loan.due_date)}</span></button>`).join("");
  $$('[data-return-id]', container).forEach(button => button.onclick = () => { closeDialog("return-search-modal"); openReturnModal(button.dataset.returnId); });
}

async function openReturnModal(id) {
  const payload = await api(`/api/loans/${id}`);
  const loan = payload.loan;
  const form = $("#return-form");
  form.reset();
  form.elements.loan_id.value = loan.id;
  const normal = form.querySelector('input[name="condition"][value="normal"]');
  if (normal) normal.checked = true;
  $("#return-modal-description").textContent = `${loan.student_name} · ${loan.book_title}`;
  $("#return-loan-preview").innerHTML = `<div><strong>${escapeHTML(loan.book_title)}</strong><small>${escapeHTML(loan.inventory_code)} · previsto para ${formatDate(loan.due_date)}</small></div>`;
  openDialog("return-modal");
}

async function saveReturn(event) {
  event.preventDefault();
  const data = formObject(event.currentTarget);
  const id = data.loan_id;
  delete data.loan_id;
  try {
    await api(`/api/loans/${id}/return`, { method: "PUT", body: data });
    toast("Devolução registrada.");
    closeDialog("return-modal");
    state.caches.loans = [];
    state.caches.books = [];
    state.caches.students = [];
    await Promise.allSettled([loadDashboard(), loadNotifications()]);
    if (state.route === "emprestimos") await loadLoans(true);
  } catch (error) {
    toast(error.message, "error");
  }
}

async function renewLoan(id) {
  if (!await confirmAction({ title: "Renovar empréstimo", message: "Deseja renovar o prazo deste empréstimo?", accept: "Renovar" })) return;
  try {
    const payload = await api(`/api/loans/${id}/renew`, { method: "PUT", body: {} });
    toast(`Empréstimo renovado até ${formatDate(payload.loan?.due_date)}.`);
    state.caches.loans = [];
    await loadLoans(true);
  } catch (error) {
    toast(error.message, "error");
  }
}


async function loadPending() {
  const payload = await api("/api/pending");
  state.caches.pending = payload.pending || [];
  renderPending();
}

function filteredPending() {
  const query = normalize($("#pending-search")?.value);
  const minDays = Number($("#pending-days-filter")?.value || 0);
  const contact = $("#pending-contact-filter")?.value || "";
  return state.caches.pending.filter(item => {
    if (query && !normalize(`${item.student_name} ${item.registration_number} ${item.class_name} ${item.book_title}`).includes(query)) return false;
    if (Number(item.overdue_days || 0) < minDays) return false;
    if (contact === "without" && Number(item.notice_count || 0) > 0) return false;
    if (contact === "with" && Number(item.notice_count || 0) < 1) return false;
    return true;
  });
}

function buildNoticeMessage(item) {
  return `Olá! A biblioteca da escola informa que o livro “${item.book_title}”, emprestado para ${item.student_name}, está com ${item.overdue_days} dia(s) de atraso. Pedimos, por gentileza, que a devolução seja realizada assim que possível. Obrigada.`;
}

function renderPending() {
  const items = filteredPending();
  const total = state.caches.pending.length;
  const without = state.caches.pending.filter(item => Number(item.notice_count || 0) === 0).length;
  const critical = state.caches.pending.filter(item => Number(item.overdue_days || 0) >= 15).length;
  if ($("#pending-total-count")) $("#pending-total-count").textContent = number(total);
  if ($("#pending-without-notice-count")) $("#pending-without-notice-count").textContent = number(without);
  if ($("#pending-critical-count")) $("#pending-critical-count").textContent = number(critical);
  updateNavCounter("#pending-nav-count", total);

  const container = $("#pending-container");
  if (!items.length) return showEmpty(container, "Nenhuma pendência", "Não há livros atrasados com estes filtros.", "✓");
  container.innerHTML = items.map(item => `
    <article class="pending-card ${Number(item.overdue_days) >= 15 ? "is-critical" : ""}">
      <div class="pending-card__header"><div class="card-identity"><span class="card-identity__avatar">${escapeHTML(initials(item.student_name))}</span><div><h3>${escapeHTML(item.student_name)}</h3><p>${escapeHTML(item.class_name || "Sem turma")} · ${escapeHTML(item.registration_number)}</p></div></div><span class="pending-days">${number(item.overdue_days)} dia(s)</span></div>
      <div class="pending-book"><strong>${escapeHTML(item.book_title)}</strong><span>${escapeHTML(item.inventory_code || "")} · deveria ter sido devolvido em ${formatDate(item.due_date)}</span></div>
      <div class="pending-contact"><span>Responsável</span><strong>${escapeHTML(item.guardian_contact || "Contato não informado")}</strong><small>${number(item.notice_count)} contato(s) registrado(s)</small></div>
      <div class="card-actions"><button class="button button--primary" data-pending-notice="${escapeHTML(item.id)}">Gerar / registrar cobrança</button><button class="button button--secondary" data-pending-copy="${escapeHTML(item.id)}">Copiar mensagem</button><button class="button button--ghost" data-pending-return="${escapeHTML(item.id)}">Devolver</button></div>
    </article>`).join("");
  $$('[data-pending-notice]', container).forEach(button => button.onclick = () => openNoticeModal(button.dataset.pendingNotice));
  $$('[data-pending-copy]', container).forEach(button => button.onclick = () => copyPendingMessage(button.dataset.pendingCopy));
  $$('[data-pending-return]', container).forEach(button => button.onclick = () => openReturnModal(button.dataset.pendingReturn));
}

async function copyPendingMessage(loanId) {
  const item = state.caches.pending.find(x => String(x.id) === String(loanId));
  if (!item) return;
  const message = buildNoticeMessage(item);
  try {
    await navigator.clipboard.writeText(message);
    toast("Mensagem de cobrança copiada.");
  } catch {
    window.prompt("Copie a mensagem:", message);
  }
}

function openNoticeModal(loanId) {
  const item = state.caches.pending.find(x => String(x.id) === String(loanId)) || state.caches.loans.find(x => String(x.id) === String(loanId));
  const form = $("#notice-form");
  form.reset();
  form.elements.loan_id.value = loanId;
  const message = item ? buildNoticeMessage(item) : "Mensagem de cobrança do BookShare.";
  $("#notice-message-preview").textContent = message;
  openDialog("notice-modal");
}

async function saveNotice(event) {
  event.preventDefault();
  const data = formObject(event.currentTarget);
  const id = data.loan_id;
  delete data.loan_id;
  try {
    await api(`/api/loans/${id}/notices`, { method: "POST", body: data });
    toast("Contato de cobrança registrado.");
    closeDialog("notice-modal");
    await loadPending();
  } catch (error) {
    toast(error.message, "error");
  }
}


async function loadReservations() {
  const payload = await api("/api/reservations");
  state.caches.reservations = payload.reservations || [];
  renderReservations();
}

function renderReservations() {
  const query = normalize($("#reservation-search")?.value);
  const status = $("#reservation-status-filter")?.value || "active";
  const items = state.caches.reservations.filter(item => {
    if (query && !normalize(`${item.student_name} ${item.class_name} ${item.book_title}`).includes(query)) return false;
    if (status === "active" && !["active", "ready"].includes(item.status)) return false;
    if (status !== "all" && status !== "active" && item.status !== status) return false;
    return true;
  });
  updateNavCounter("#reservations-nav-count", state.caches.reservations.filter(item => ["active", "ready"].includes(item.status)).length);
  const container = $("#reservations-container");
  if (!items.length) return showEmpty(container, "Nenhuma reserva encontrada", "Crie uma reserva quando um livro estiver indisponível.", "◇");
  container.innerHTML = items.map(item => `
    <article class="reservation-card">
      <div class="reservation-card__header"><div><h3>${escapeHTML(item.book_title)}</h3><p>${escapeHTML(item.book_author || "")}</p></div>${statusBadge(item.status === "ready" ? "Pronta" : item.status === "active" ? "Na fila" : item.status, item.status === "ready" ? "success" : item.status === "cancelled" ? "muted" : "warning")}</div>
      <div class="reservation-person"><strong>${escapeHTML(item.student_name)}</strong><span>${escapeHTML(item.class_name || "Sem turma")} · posição ${number(item.queue_position || 1)}</span></div>
      <div class="reservation-meta"><span>Reservado em ${formatDate(item.created_at)}</span>${item.expires_at ? `<span>Retirar até ${formatDate(item.expires_at)}</span>` : ""}</div>
      ${["active", "ready"].includes(item.status) ? `<div class="card-actions">${item.status === "active" ? `<button class="button button--primary" data-res-ready="${escapeHTML(item.id)}">Marcar pronta</button>` : ""}<button class="button button--ghost" data-res-cancel="${escapeHTML(item.id)}">Cancelar</button></div>` : ""}
    </article>`).join("");
  $$('[data-res-ready]', container).forEach(button => button.onclick = () => markReservationReady(button.dataset.resReady));
  $$('[data-res-cancel]', container).forEach(button => button.onclick = () => cancelReservation(button.dataset.resCancel));
}

async function prepareReservationModal() {
  await Promise.all([fetchStudents(), fetchBooks()]);
  $("#reservation-form").reset();
}

async function saveReservation(event) {
  event.preventDefault();
  const data = formObject(event.currentTarget);
  try {
    await api("/api/reservations", { method: "POST", body: data });
    toast("Reserva registrada.");
    closeDialog("reservation-modal");
    await loadReservations();
  } catch (error) {
    toast(error.message, "error");
  }
}

async function markReservationReady(id) {
  try {
    await api(`/api/reservations/${id}/ready`, { method: "PUT", body: {} });
    toast("Reserva marcada como pronta para retirada.");
    await loadReservations();
    loadNotifications().catch(() => {});
  } catch (error) {
    toast(error.message, "error");
  }
}

async function cancelReservation(id) {
  if (!await confirmAction({ title: "Cancelar reserva", message: "Deseja cancelar esta reserva?", accept: "Cancelar reserva", danger: true })) return;
  try {
    await api(`/api/reservations/${id}/cancel`, { method: "PUT", body: {} });
    toast("Reserva cancelada.");
    await loadReservations();
  } catch (error) {
    toast(error.message, "error");
  }
}


async function loadClasses(force = false) {
  if (!state.caches.classes.length || force) {
    const payload = await api("/api/classes");
    state.caches.classes = payload.classes || [];
    populateReferenceSelects();
  }
  const query = normalize($("#class-search")?.value);
  const year = $("#class-year-filter")?.value || "";
  const shift = $("#class-shift-filter")?.value || "";
  const classes = state.caches.classes.filter(item => {
    if (query && !normalize(`${item.name} ${item.teacher_name || ""}`).includes(query)) return false;
    if (year && String(item.school_year) !== year) return false;
    if (shift && item.shift !== shift) return false;
    return true;
  });
  const container = $("#classes-container");
  if (!classes.length) return showEmpty(container, "Nenhuma turma encontrada", "Ajuste os filtros.", "▦");
  container.innerHTML = classes.map(item => `<article class="class-card"><div class="class-card__header"><div><h3>${escapeHTML(item.name)}</h3><p>${escapeHTML(item.shift)} · ${escapeHTML(item.school_year)}</p></div>${item.active === false ? statusBadge("Arquivada", "muted") : statusBadge("Ativa", "success")}</div><div class="class-card__stats"><div><strong>${number(item.student_count)}</strong><span>alunos</span></div><div><strong>${escapeHTML(item.teacher_name || "—")}</strong><span>responsável</span></div></div>${roleIsAdmin() ? `<div class="card-actions"><button class="button button--secondary" data-class-edit="${escapeHTML(item.id)}">Editar</button></div>` : ""}</article>`).join("");
  $$('[data-class-edit]', container).forEach(button => button.onclick = () => openClassEdit(button.dataset.classEdit));
}

function prepareNewClassModal() {
  const form = $("#class-form");
  form.reset();
  form.elements.id.value = "";
  $("#class-modal-title").textContent = "Cadastrar turma";
  if (form.elements.school_year) form.elements.school_year.value = new Date().getFullYear();
}

function openClassEdit(id) {
  const item = state.caches.classes.find(x => String(x.id) === String(id));
  if (!item) return;
  const form = $("#class-form");
  form.reset();
  ["id", "name", "shift", "school_year", "teacher_name"].forEach(key => {
    if (form.elements[key]) form.elements[key].value = item[key] ?? "";
  });
  $("#class-modal-title").textContent = "Editar turma";
  openDialog("class-modal");
}

async function saveClass(event) {
  event.preventDefault();
  const data = formObject(event.currentTarget);
  const id = data.id;
  delete data.id;
  data.school_year = Number(data.school_year);
  try {
    await api(id ? `/api/classes/${id}` : "/api/classes", { method: id ? "PUT" : "POST", body: data });
    toast(id ? "Turma atualizada." : "Turma cadastrada.");
    closeDialog("class-modal");
    await loadClasses(true);
  } catch (error) {
    toast(error.message, "error");
  }
}


async function loadSchools(force = false) {
  if (!roleIsAdmin()) return;
  if (!state.caches.schools.length || force) {
    const payload = await api("/api/schools");
    state.caches.schools = payload.schools || [];
    populateReferenceSelects();
  }
  const query = normalize($("#school-search")?.value);
  const status = $("#school-status-filter")?.value || "";
  const items = state.caches.schools.filter(item => {
    if (query && !normalize(`${item.name} ${item.code} ${item.address || ""}`).includes(query)) return false;
    if (status === "active" && item.active === false) return false;
    if (status === "inactive" && item.active !== false) return false;
    return true;
  });
  const container = $("#schools-container");
  if (!items.length) return showEmpty(container, "Nenhuma escola encontrada", "Cadastre uma unidade escolar.", "⌂");
  container.innerHTML = items.map(item => `<article class="school-card"><div class="school-card__head"><span class="school-card__icon">⌂</span><div><strong>${escapeHTML(item.name)}</strong><span>${escapeHTML(item.code)}</span></div>${item.active === false ? statusBadge("Arquivada", "muted") : statusBadge("Ativa", "success")}</div><div class="school-card__stats"><div><strong>${number(item.student_count)}</strong><span>alunos</span></div><div><strong>${number(item.book_count)}</strong><span>livros</span></div><div><strong>${number(item.staff_count)}</strong><span>equipe</span></div></div><p>${escapeHTML(item.address || "Endereço não informado")}</p><div class="card-actions"><button class="button button--secondary" data-school-edit="${escapeHTML(item.id)}">Editar</button></div></article>`).join("");
  $$('[data-school-edit]', container).forEach(button => button.onclick = () => openSchoolEdit(button.dataset.schoolEdit));
}

function prepareNewSchoolModal() {
  const form = $("#school-form");
  form.reset();
  form.elements.id.value = "";
  $("#school-modal-title").textContent = "Cadastrar escola";
}

function openSchoolEdit(id) {
  const item = state.caches.schools.find(x => String(x.id) === String(id));
  if (!item) return;
  const form = $("#school-form");
  form.reset();
  ["id", "name", "code", "phone", "address", "contact_email"].forEach(key => {
    if (form.elements[key]) form.elements[key].value = item[key] ?? "";
  });
  $("#school-modal-title").textContent = "Editar escola";
  openDialog("school-modal");
}

async function saveSchool(event) {
  event.preventDefault();
  const data = formObject(event.currentTarget);
  const id = data.id;
  delete data.id;
  try {
    await api(id ? `/api/schools/${id}` : "/api/schools", { method: id ? "PUT" : "POST", body: data });
    toast(id ? "Escola atualizada." : "Escola cadastrada.");
    closeDialog("school-modal");
    await loadSchools(true);
  } catch (error) {
    toast(error.message, "error");
  }
}

async function loadUsers(force = false) {
  if (!roleIsAdmin()) return;
  if (!state.caches.users.length || force) {
    const payload = await api("/api/users");
    state.caches.users = payload.users || [];
  }
  const query = normalize($("#user-search")?.value);
  const role = $("#user-role-filter")?.value || "";
  const items = state.caches.users.filter(item => {
    if (query && !normalize(`${item.name} ${item.email}`).includes(query)) return false;
    if (role && item.role !== role) return false;
    return true;
  });
  const container = $("#users-container");
  if (!items.length) return showEmpty(container, "Nenhuma conta encontrada", "Cadastre uma conta para a equipe.", "♟");
  container.innerHTML = items.map(item => `<article class="user-card"><div class="user-card__header"><div class="card-identity"><span class="card-identity__avatar">${escapeHTML(initials(item.name))}</span><div><h3>${escapeHTML(item.name)}</h3><p>${escapeHTML(item.email)}</p></div></div>${item.active === false ? statusBadge("Inativa", "muted") : statusBadge(item.role === "admin" ? "Admin" : "Bibliotecária", item.role === "admin" ? "warning" : "success")}</div><div class="user-card__stats"><div><strong>${escapeHTML(item.school_name || "—")}</strong><span>escola</span></div><div><strong>${escapeHTML(item.phone || "—")}</strong><span>telefone</span></div></div></article>`).join("");
}

async function prepareUserModal() {
  if (!state.caches.schools.length) await loadSchools(true);
  $("#user-form").reset();
  populateReferenceSelects();
}

async function saveUser(event) {
  event.preventDefault();
  const data = formObject(event.currentTarget);
  try {
    await api("/api/users", { method: "POST", body: data });
    toast("Conta criada.");
    closeDialog("user-modal");
    await loadUsers(true);
  } catch (error) {
    toast(error.message, "error");
  }
}


async function loadReports() {
  const start = $("#report-start-date")?.value || "";
  const end = $("#report-end-date")?.value || "";
  const params = new URLSearchParams();
  if (start) params.set("start_date", start);
  if (end) params.set("end_date", end);
  const payload = await api(`/api/reports/summary${params.toString() ? `?${params}` : ""}`);
  const summary = payload.summary || payload.loans || {};
  if ($("#report-total-loans")) $("#report-total-loans").textContent = number(summary.total_loans ?? summary.total ?? 0);
  if ($("#report-returned-loans")) $("#report-returned-loans").textContent = number(summary.returned_loans ?? summary.returned ?? 0);
  if ($("#report-lost-loans")) $("#report-lost-loans").textContent = number(summary.lost_loans ?? summary.lost ?? 0);
  if ($("#report-damaged-loans")) $("#report-damaged-loans").textContent = number(summary.damaged_loans ?? summary.damaged ?? 0);
  renderSimpleBars("#report-class-bars", payload.by_class || payload.classes || [], "class_name", "loan_count");
  renderSimpleBars("#report-popular-books", payload.popular_books || [], "title", "loan_count");
  renderSimpleBars("#report-losses", payload.losses || payload.losses_and_damage || [], "title", "count");
  renderCategoryLegend(payload.by_category || payload.categories || []);
}

function renderSimpleBars(selector, items, labelKey, valueKey) {
  const container = $(selector);
  if (!container) return;
  if (!items.length) return showEmpty(container, "Sem dados no período", "Escolha outro período ou registre movimentações.", "◫");
  const max = Math.max(1, ...items.map(item => Number(item[valueKey] || item.total || 0)));
  container.innerHTML = items.slice(0, 12).map(item => {
    const value = Number(item[valueKey] || item.total || 0);
    return `<div class="report-bar"><div><strong>${escapeHTML(item[labelKey] || item.name || "Sem nome")}</strong><span>${number(value)}</span></div><i><b style="width:${Math.max(3, (value / max) * 100)}%"></b></i></div>`;
  }).join("");
}

function renderCategoryLegend(items) {
  const container = $("#category-legend");
  if (!container) return;
  container.innerHTML = items.slice(0, 8).map(item => `<span><i></i>${escapeHTML(item.category_name || item.name || "Sem categoria")} <strong>${number(item.loan_count || item.total || 0)}</strong></span>`).join("");
}

async function loadActivities() {
  const payload = await api("/api/activity");
  state.caches.activities = payload.activities || [];
  renderActivities();
}

function renderActivities() {
  const query = normalize($("#activity-search")?.value);
  const type = $("#activity-type-filter")?.value || "";
  const items = state.caches.activities.filter(item => {
    if (query && !normalize(`${item.action} ${item.entity_type} ${item.user_name || ""}`).includes(query)) return false;
    if (type && item.action !== type && item.entity_type !== type) return false;
    return true;
  });
  const container = $("#activity-container");
  if (!items.length) return showEmpty(container, "Sem atividades", "As ações do sistema aparecerão aqui.", "◷");
  container.innerHTML = items.slice(0, 150).map(item => `<div class="activity-item"><span class="activity-item__icon">◷</span><div><strong>${escapeHTML(item.user_name || "Sistema")}</strong><p>${escapeHTML(item.action)} · ${escapeHTML(item.entity_type || "registro")}</p><small>${formatDateTime(item.created_at)}</small></div></div>`).join("");
}


async function loadProfile() {
  if (!state.user) return;
  if ($("#profile-name-input")) $("#profile-name-input").value = state.user.name || "";
  if ($("#profile-email-input")) $("#profile-email-input").value = state.user.email || "";
  if ($("#profile-phone-input")) $("#profile-phone-input").value = state.user.phone || "";
  if ($("#profile-role-title")) $("#profile-role-title").textContent = roleIsAdmin() ? "Administrador" : "Bibliotecária";
  if ($("#profile-role-description")) $("#profile-role-description").textContent = roleIsAdmin() ? "Administração completa do sistema" : "Atendimento e gestão da biblioteca";
  if ($("#profile-school-name")) $("#profile-school-name").textContent = state.user.school_name || "Biblioteca Escolar";
  if ($("#profile-job-title")) $("#profile-job-title").textContent = state.user.job_title || (roleIsAdmin() ? "Administrador do sistema" : "Bibliotecária");
  if ($("#profile-phone")) $("#profile-phone").textContent = state.user.phone || "Não informado";
  const preview = $("#profile-photo-preview");
  if (preview) preview.innerHTML = state.user.avatar_url ? `<img src="${escapeHTML(state.user.avatar_url)}" alt="">` : initials(state.user.name);
}

async function loadSettings() {
  const payload = await api("/api/settings");
  const settings = payload.settings || {};
  const form = $("#settings-form");
  if (form) {
    Object.entries(settings).forEach(([key, value]) => {
      const field = form.elements[key];
      if (!field) return;
      if (field.type === "checkbox") field.checked = Boolean(value);
      else field.value = value ?? "";
    });
  }
  if (state.user) {
    if ($("#profile-name-input")) $("#profile-name-input").value = state.user.name || "";
    if ($("#profile-email-input")) $("#profile-email-input").value = state.user.email || "";
    if ($("#profile-phone-input")) $("#profile-phone-input").value = state.user.phone || "";
    if ($("#profile-role-title")) $("#profile-role-title").textContent = roleIsAdmin() ? "Administrador" : "Bibliotecária";
    if ($("#profile-school-name")) $("#profile-school-name").textContent = state.user.school_name || "Biblioteca Escolar";
    if ($("#profile-job-title")) $("#profile-job-title").textContent = state.user.job_title || (roleIsAdmin() ? "Administrador do sistema" : "Bibliotecária");
    if ($("#profile-phone")) $("#profile-phone").textContent = state.user.phone || "Telefone não informado";
    const preview = $("#profile-photo-preview");
    if (preview) preview.innerHTML = state.user.avatar_url ? `<img src="${escapeHTML(state.user.avatar_url)}" alt="">` : initials(state.user.name);
  }
}

async function saveSettings(event) {
  event.preventDefault();
  if (!roleIsAdmin()) return;
  const data = formObject(event.currentTarget);
  for (const key of ["current_school_year", "default_loan_days", "max_active_loans", "max_renewals", "renewal_days", "due_soon_days", "reservation_hold_days"]) {
    if (data[key] !== undefined && data[key] !== "") data[key] = Number(data[key]);
  }
  try {
    await api("/api/settings", { method: "PUT", body: data });
    if ($("#settings-save-status")) $("#settings-save-status").textContent = "Configurações salvas agora.";
    toast("Configurações atualizadas.");
  } catch (error) {
    toast(error.message, "error");
  }
}

async function saveProfile() {
  const data = {
    name: $("#profile-name-input")?.value.trim(),
    email: $("#profile-email-input")?.value.trim(),
    phone: $("#profile-phone-input")?.value.trim(),
    avatar_url: state.user.avatar_url || null
  };
  try {
    const payload = await api("/api/auth/profile", { method: "PUT", body: data });
    state.user = payload.user;
    setUserUI();
    toast("Perfil atualizado.");
    loadProfile();
  } catch (error) {
    toast(error.message, "error");
  }
}

async function changeOwnPassword() {
  const current_password = $("#current-password")?.value || "";
  const new_password = $("#new-password")?.value || "";
  try {
    await api("/api/auth/change-password", { method: "PUT", body: { current_password, new_password } });
    $("#current-password").value = "";
    $("#new-password").value = "";
    toast("Senha alterada.");
  } catch (error) {
    toast(error.message, "error");
  }
}

function handleProfilePhoto(event) {
  const file = event.target.files?.[0];
  if (!file) return;
  if (file.size > 900000) return toast("Use uma imagem menor que 900 KB.", "warning");
  const reader = new FileReader();
  reader.onload = () => {
    state.user.avatar_url = reader.result;
    const preview = $("#profile-photo-preview");
    if (preview) preview.innerHTML = `<img src="${reader.result}" alt="">`;
  };
  reader.readAsDataURL(file);
}


async function globalSearch() {
  const input = $("#global-search-input");
  const box = $("#global-search-results");
  const query = normalize(input?.value);
  if (!box) return;
  if (query.length < 2) return box.classList.add("is-hidden");

  await Promise.all([fetchStudents(), fetchBooks()]);
  const students = state.caches.students.filter(item => normalize(`${item.full_name} ${item.registration_number}`).includes(query)).slice(0, 5);
  const books = state.caches.books.filter(item => normalize(`${item.title} ${item.author} ${item.isbn || ""}`).includes(query)).slice(0, 5);
  box.innerHTML = `
    ${students.length ? `<p class="search-group-label">Alunos</p>${students.map(item => `<button data-global-student="${escapeHTML(item.id)}"><span>♙</span><div><strong>${escapeHTML(item.full_name)}</strong><small>${escapeHTML(item.class_name || "Sem turma")} · ${escapeHTML(item.registration_number)}</small></div></button>`).join("")}` : ""}
    ${books.length ? `<p class="search-group-label">Livros</p>${books.map(item => `<button data-global-book="${escapeHTML(item.id)}"><span>▤</span><div><strong>${escapeHTML(item.title)}</strong><small>${escapeHTML(item.author)}</small></div></button>`).join("")}` : ""}
    ${!students.length && !books.length ? `<div class="global-search-empty">Nenhum resultado.</div>` : ""}`;
  box.classList.remove("is-hidden");
  $$('[data-global-student]', box).forEach(button => button.onclick = () => { box.classList.add("is-hidden"); openStudentDetails(button.dataset.globalStudent); });
  $$('[data-global-book]', box).forEach(button => button.onclick = () => { box.classList.add("is-hidden"); openBookDetails(button.dataset.globalBook); });
}


function downloadCSV(filename, headers, rows) {
  const escapeCell = value => `"${String(value ?? "").replaceAll('"', '""')}"`;
  const csv = "\ufeff" + [headers, ...rows].map(row => row.map(escapeCell).join(";")).join("\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function exportStudents() {
  const items = getFilteredStudents();
  downloadCSV("bookshare-alunos.csv", ["Nome", "Matrícula", "Turma", "Contato", "Empréstimos", "Atrasos"], items.map(item => [item.full_name, item.registration_number, item.class_name, item.guardian_contact, item.active_loans, item.overdue_loans]));
}

function exportBooks() {
  const items = filteredBooks();
  downloadCSV("bookshare-livros.csv", ["Título", "Autor", "ISBN", "Categoria", "Estante", "Exemplares", "Disponíveis"], items.map(item => [item.title, item.author, item.isbn, item.category_name, item.shelf, item.total_copies, item.available_copies]));
}

function exportLoans() {
  const items = filteredLoans();
  downloadCSV("bookshare-emprestimos.csv", ["Aluno", "Turma", "Livro", "Patrimônio", "Empréstimo", "Prazo", "Situação"], items.map(item => [item.student_name, item.class_name, item.book_title, item.inventory_code, item.loan_date, item.due_date, item.status]));
}


function bindModalButtons() {
  $$('[data-open-modal]').forEach(button => {
    button.addEventListener("click", async () => {
      const id = button.dataset.openModal;
      try {
        if (id === "loan-modal") return openLoanModal();
        if (id === "return-search-modal") return openReturnSearch();
        if (id === "student-modal") prepareNewStudentModal();
        if (id === "book-modal") prepareNewBookModal();
        if (id === "copy-modal") prepareCopyModal();
        if (id === "class-modal") prepareNewClassModal();
        if (id === "reservation-modal") await prepareReservationModal();
        if (id === "school-modal") prepareNewSchoolModal();
        if (id === "user-modal") await prepareUserModal();
        openDialog(id);
      } catch (error) {
        toast(error.message, "error");
      }
    });
  });

  $$('[data-close-modal]').forEach(button => button.addEventListener("click", () => closeDialog(button.closest("dialog"))));
  $$("dialog").forEach(dialog => dialog.addEventListener("click", event => {
    if (event.target === dialog) closeDialog(dialog);
  }));
}

function bindFilters() {
  $("#student-search")?.addEventListener("input", debounce(renderStudents));
  $("#student-class-filter")?.addEventListener("change", renderStudents);
  $("#student-status-filter")?.addEventListener("change", renderStudents);
  $("#book-search")?.addEventListener("input", debounce(renderBooks));
  $("#book-category-filter")?.addEventListener("change", renderBooks);
  $("#book-availability-filter")?.addEventListener("change", renderBooks);
  $("#copy-search")?.addEventListener("input", debounce(() => loadCopies()));
  $("#copy-status-filter")?.addEventListener("change", () => loadCopies());
  $("#loan-search")?.addEventListener("input", debounce(renderLoans));
  $("#loan-class-filter")?.addEventListener("change", renderLoans);
  $("#loan-start-date")?.addEventListener("change", renderLoans);
  $("#loan-end-date")?.addEventListener("change", renderLoans);
  $("#reservation-search")?.addEventListener("input", debounce(renderReservations));
  $("#reservation-status-filter")?.addEventListener("change", renderReservations);
  $("#pending-search")?.addEventListener("input", debounce(renderPending));
  $("#pending-days-filter")?.addEventListener("change", renderPending);
  $("#pending-contact-filter")?.addEventListener("change", renderPending);
  $("#class-search")?.addEventListener("input", debounce(() => loadClasses()));
  $("#class-year-filter")?.addEventListener("change", () => loadClasses());
  $("#class-shift-filter")?.addEventListener("change", () => loadClasses());
  $("#school-search")?.addEventListener("input", debounce(() => loadSchools()));
  $("#school-status-filter")?.addEventListener("change", () => loadSchools());
  $("#user-search")?.addEventListener("input", debounce(() => loadUsers()));
  $("#user-role-filter")?.addEventListener("change", () => loadUsers());
  $("#activity-search")?.addEventListener("input", debounce(renderActivities));
  $("#activity-type-filter")?.addEventListener("change", renderActivities);
  $("#service-student-search")?.addEventListener("input", debounce(renderServiceSearch, 150));
  $("#return-search-input")?.addEventListener("input", debounce(renderReturnSearchResults, 150));
}

function bindPageActions() {
  document.addEventListener("click", event => {
    const routeButton = event.target.closest("[data-route]");
    if (routeButton) {
      event.preventDefault();
      navigate(routeButton.dataset.route);
      return;
    }
    const moreButton = event.target.closest("#mobile-more-button");
    if (moreButton) {
      event.preventDefault();
      openSidebar();
    }
  });
  $("#menu-button")?.addEventListener("click", openSidebar);
  $("#sidebar-close")?.addEventListener("click", closeSidebar);
  $("#sidebar-overlay")?.addEventListener("click", closeSidebar);
  $("#logout-button")?.addEventListener("click", () => logout(true));
  $("#notifications-button")?.addEventListener("click", () => toggleNotificationPanel());
  $("#notification-panel-close")?.addEventListener("click", () => toggleNotificationPanel(false));
  $("#refresh-button")?.addEventListener("click", () => navigate(state.route));
  $("#sidebar-profile-button")?.addEventListener("click", () => navigate("perfil"));
  $("#topbar-profile")?.addEventListener("click", () => navigate("perfil"));
  $("#librarian-profile-shortcut")?.addEventListener("click", () => navigate("perfil"));
  $("#global-search-input")?.addEventListener("input", debounce(globalSearch, 180));

  $("#loan-status-tabs")?.addEventListener("click", event => {
    const button = event.target.closest("button[data-value]");
    if (!button) return;
    state.loanStatus = button.dataset.value;
    $$("button", event.currentTarget).forEach(item => item.classList.toggle("is-active", item === button));
    renderLoans();
  });

  $("#book-view-switcher")?.addEventListener("click", event => {
    const button = event.target.closest("button[data-view]");
    if (!button) return;
    state.bookView = button.dataset.view;
    localStorage.setItem("bookshare_book_view", state.bookView);
    $$("button", event.currentTarget).forEach(item => item.classList.toggle("is-active", item === button));
    renderBooks();
  });

  $("#loan-filter-clear")?.addEventListener("click", () => {
    $("#loan-search").value = "";
    $("#loan-class-filter").value = "";
    $("#loan-start-date").value = "";
    $("#loan-end-date").value = "";
    renderLoans();
  });

  $("#sync-covers-button")?.addEventListener("click", syncBookCovers);
  $("#export-students-button")?.addEventListener("click", exportStudents);
  $("#export-books-button")?.addEventListener("click", exportBooks);
  $("#export-loans-button")?.addEventListener("click", exportLoans);
  $("#report-apply-button")?.addEventListener("click", loadReports);
  $("#report-print-button")?.addEventListener("click", () => window.print());
  $("#activity-refresh-button")?.addEventListener("click", loadActivities);
}

function bindForms() {
  $("#login-form")?.addEventListener("submit", handleLogin);
  $("#loan-form")?.addEventListener("submit", saveLoan);
  $("#return-form")?.addEventListener("submit", saveReturn);
  $("#book-form")?.addEventListener("submit", saveBook);
  $("#copy-form")?.addEventListener("submit", saveCopies);
  $("#student-form")?.addEventListener("submit", saveStudent);
  $("#class-form")?.addEventListener("submit", saveClass);
  $("#reservation-form")?.addEventListener("submit", saveReservation);
  $("#notice-form")?.addEventListener("submit", saveNotice);
  $("#user-form")?.addEventListener("submit", saveUser);
  $("#school-form")?.addEventListener("submit", saveSchool);
  $("#settings-form")?.addEventListener("submit", saveSettings);
  $("#loan-student")?.addEventListener("change", updateLoanStudentStatus);
  $("#student-photo-file")?.addEventListener("change", handleStudentPhotoFile);
  $("#student-photo-button")?.addEventListener("click", () => $("#student-photo-file")?.click());
  $("#profile-photo-input")?.addEventListener("change", handleProfilePhoto);
  $("#save-profile-button")?.addEventListener("click", saveProfile);
  $("#change-own-password-button")?.addEventListener("click", changeOwnPassword);
  $("#copy-notice-from-modal")?.addEventListener("click", async () => {
    const text = $("#notice-message-preview")?.textContent || "";
    try { await navigator.clipboard.writeText(text); toast("Mensagem copiada."); } catch { window.prompt("Copie:", text); }
  });
}

function bindPasswordToggle() {
  $("#toggle-password")?.addEventListener("click", () => {
    const input = $("#login-password");
    input.type = input.type === "password" ? "text" : "password";
  });
}

function bindKeyboard() {
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") {
      closeAllDialogs();
      toggleNotificationPanel(false);
      closeSidebar();
      $("#global-search-results")?.classList.add("is-hidden");
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
      event.preventDefault();
      $("#global-search-input")?.focus();
    }
  });
  document.addEventListener("click", event => {
    if (!event.target.closest(".global-search")) $("#global-search-results")?.classList.add("is-hidden");
  });
  document.addEventListener("error", event => {
    const target = event.target;
    if (!(target instanceof HTMLImageElement)) return;
    target.style.visibility = "hidden";
    target.parentElement?.classList.add("image-load-failed");
  }, true);
}

function setupInitialBookView() {
  const switcher = $("#book-view-switcher");
  if (!switcher) return;
  $$("button[data-view]", switcher).forEach(button => button.classList.toggle("is-active", button.dataset.view === state.bookView));
}


function setupWelcomeBookCarousel() {
  const viewport = document.querySelector("[data-book-carousel]");
  const track = viewport?.querySelector(".welcome-books__track");
  const prev = document.querySelector("[data-book-carousel-prev]");
  const next = document.querySelector("[data-book-carousel-next]");
  if (!viewport || !track) return;

  const step = () => {
    const card = track.querySelector(".welcome-book");
    return card ? card.getBoundingClientRect().width + 13 : 115;
  };
  const move = direction => {
    const max = Math.max(0, track.scrollWidth - track.clientWidth);
    let target = track.scrollLeft + direction * step();
    if (direction > 0 && target >= max - 4) target = 0;
    if (direction < 0 && target <= 4) target = max;
    track.scrollTo({ left: target, behavior: "smooth" });
  };

  prev?.addEventListener("click", () => move(-1));
  next?.addEventListener("click", () => move(1));

  let timer = setInterval(() => move(1), 3600);
  const pause = () => clearInterval(timer);
  const resume = () => {
    clearInterval(timer);
    timer = setInterval(() => move(1), 3600);
  };
  viewport.addEventListener("mouseenter", pause);
  viewport.addEventListener("mouseleave", resume);
  viewport.addEventListener("focusin", pause);
  viewport.addEventListener("focusout", resume);
  document.addEventListener("visibilitychange", () => document.hidden ? pause() : resume());
}

async function boot() {
  const bootWatchdog = setTimeout(() => {
    const loading = $("#app-loading");
    if (loading && !loading.classList.contains("is-hidden")) {
      state.user ? showApp() : showAuth();
    }
  }, 7000);

  setLoading(true);
  bindModalButtons();
  bindFilters();
  bindPageActions();
  bindForms();
  bindPasswordToggle();
  bindKeyboard();
  setupInitialBookView();
  setupWelcomeBookCarousel();
  if (!state.token) showAuth();
  await loadApiConfig();
  wakeApi();

  const apiHint = $("#api-connection-hint");
  if (!API_BASE_URL && !["localhost", "127.0.0.1"].includes(location.hostname) && !location.hostname.endsWith(".onrender.com")) {
    if (apiHint) {
      apiHint.textContent = "A API ainda não foi configurada. Coloque o endereço do Render no arquivo config.json.";
      apiHint.classList.remove("is-hidden");
    }
  } else if (apiHint) {
    apiHint.classList.add("is-hidden");
  }

  const started = performance.now();
  await restoreSession();
  const elapsed = performance.now() - started;
  if (elapsed < 250) await new Promise(resolve => setTimeout(resolve, 250 - elapsed));
  clearTimeout(bootWatchdog);
  setLoading(false);
}

document.addEventListener("DOMContentLoaded", boot);
