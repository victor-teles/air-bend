// Client for the dashboard example. Every call goes to a route defined in
// main.bend; nothing here is framework-specific.

const $ = (sel) => document.querySelector(sel);
const log = $("#log");

async function api(method, path, body) {
  const t0 = performance.now();
  const res = await fetch(path, {
    method,
    headers: body ? { "content-type": "application/json" } : {},
    body,
  });
  const ms = (performance.now() - t0).toFixed(1);
  const li = document.createElement("li");
  li.textContent = `${method} ${path} → ${res.status} in ${ms} ms`;
  log.prepend(li);
  while (log.children.length > 8) log.lastChild.remove();
  return res.json();
}

function fmt(ms) {
  const s = Math.floor(ms / 1000);
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`;
}

async function loadStats() {
  const s = await api("GET", "/api/stats");
  const cards = [
    ["server", s.server],
    ["bend", s.bend],
    ["uptime", fmt(s.uptime_ms)],
    ["max body", `${s.max_body / 1024 / 1024} MiB`],
  ];
  const box = $("#stats");
  const tpl = $("#stat-card");
  box.querySelectorAll(":scope > div").forEach((n) => n.remove());
  for (const [k, v] of cards) {
    const el = tpl.content.firstElementChild.cloneNode(true);
    el.querySelector("dt").textContent = k;
    el.querySelector("dd").textContent = v;
    box.append(el);
  }
  $("#status").textContent = "online";
  $("#status").className =
    "rounded-full bg-emerald-100 px-3 py-1 text-xs font-medium text-emerald-700";
}

async function loadTasks() {
  const tasks = await api("GET", "/api/tasks");
  const ul = $("#tasks");
  ul.innerHTML = "";
  for (const t of tasks) {
    const li = document.createElement("li");
    li.className = "flex items-center gap-3 px-4 py-3";
    li.innerHTML = `
      <input type="checkbox" class="size-4 accent-ink" ${t.done ? "checked" : ""}>
      <span class="text-sm ${t.done ? "text-slate-400 line-through" : ""}">${t.title}</span>`;
    li.querySelector("input").addEventListener("change", (e) => {
      t.done = e.target.checked;
      li.querySelector("span").className =
        "text-sm " + (t.done ? "text-slate-400 line-through" : "");
      count(tasks);
    });
    ul.append(li);
  }
  count(tasks);
}

function count(tasks) {
  $("#task-count").textContent = tasks.length;
  $("#done-count").textContent = tasks.filter((t) => t.done).length;
}

$("#greet-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const name = encodeURIComponent($("#greet-name").value.trim());
  const r = await api("GET", `/api/hello/${name}`);
  $("#greet-out").textContent = r.greeting;
});

$("#echo-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const body = $("#echo-body").value;
  try {
    JSON.parse(body);
  } catch {
    $("#echo-out").textContent = "not valid JSON";
    return;
  }
  const r = await api("POST", "/api/echo", body);
  $("#echo-out").textContent = JSON.stringify(r, null, 2);
});

loadStats().catch(() => ($("#status").textContent = "offline"));
loadTasks();
setInterval(loadStats, 5000);
