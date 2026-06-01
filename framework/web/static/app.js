"use strict";

// ---- State -----------------------------------------------------------------
// The catalog (read-only declarations) drives the form; `entries`/`platforms`
// hold the customer-side VALUES that become the manifest. Secrets are stored as
// bare env-var names here and wrapped as ${env:NAME} only at manifest-build time
// — the UI never holds a secret value, only a reference to where it lives.
const state = {
  catalog: null,
  fetchersByName: {},      // name -> descriptor
  platformByCategory: {},  // category -> {config:[...], passthrough_env:[...]}
  entries: [],             // {name, config:{}, secrets:{}, targets:[{values:{},secrets:{}}]}
  platforms: {},           // category -> {config:{}, passthrough:[...]}
};

const $ = (sel) => document.querySelector(sel);
const el = (tag, cls, txt) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (txt != null) e.textContent = txt;
  return e;
};

// ---- Boot ------------------------------------------------------------------
async function boot() {
  state.catalog = await (await fetch("/api/catalog")).json();
  for (const cat of state.catalog.categories) {
    if (cat.platform && (cat.platform.config.length || cat.platform.passthrough_env.length)) {
      state.platformByCategory[cat.name] = cat.platform;
    }
    for (const f of cat.fetchers) state.fetchersByName[f.name] = f;
  }
  renderCatalog();
  await loadExamples();
  render();
  wireControls();
}

async function loadExamples() {
  try {
    const data = await (await fetch("/api/manifests")).json();
    const sel = $("#example-picker");
    for (const m of data.manifests) {
      const opt = el("option", null, m.name);
      opt.value = m.path;
      sel.appendChild(opt);
    }
  } catch (_) { /* optional */ }
}

// ---- Catalog sidebar -------------------------------------------------------
function renderCatalog() {
  const root = $("#catalog");
  root.innerHTML = "";
  for (const cat of state.catalog.categories) {
    const d = el("details", "cat");
    d.open = false;
    const sum = el("summary", null, `${cat.name} (${cat.fetchers.length})`);
    d.appendChild(sum);
    if (cat.description) d.appendChild(el("div", "cat-desc", cat.description.trim()));
    for (const f of cat.fetchers) {
      const row = el("div", "fetcher-row");
      row.dataset.fetcher = f.name;
      const left = el("span");
      left.appendChild(el("span", "fname", f.name));
      left.appendChild(el("span", "tag", f.supports_targets ? "fanout" : "single"));
      const btn = el("button", "btn btn-ghost", "Add");
      btn.onclick = () => addEntry(f.name);
      row.appendChild(left);
      row.appendChild(btn);
      d.appendChild(row);
    }
    root.appendChild(d);
  }
  applyCatalogFilter();
}

function applyCatalogFilter() {
  const q = ($("#catalog-search").value || "").toLowerCase();
  document.querySelectorAll("#catalog .fetcher-row").forEach((row) => {
    row.style.display = row.dataset.fetcher.toLowerCase().includes(q) ? "" : "none";
  });
  document.querySelectorAll("#catalog .cat").forEach((d) => {
    const any = [...d.querySelectorAll(".fetcher-row")].some((r) => r.style.display !== "none");
    d.style.display = any ? "" : "none";
    if (q) d.open = true;
  });
}

function markAdded() {
  const added = new Set(state.entries.map((e) => e.name));
  document.querySelectorAll("#catalog .fetcher-row").forEach((row) => {
    row.classList.toggle("added", added.has(row.dataset.fetcher));
  });
}

// ---- Entry management ------------------------------------------------------
function addEntry(name) {
  if (state.entries.some((e) => e.name === name)) return;
  const f = state.fetchersByName[name];
  const entry = { name, config: {}, secrets: {}, targets: [] };
  if (f && f.supports_targets) addTarget(entry, false);
  // seed category platform panel if relevant
  if (f && f.category && state.platformByCategory[f.category] && !state.platforms[f.category]) {
    state.platforms[f.category] = { config: {}, passthrough: [...(state.platformByCategory[f.category].passthrough_env || [])] };
  }
  state.entries.push(entry);
  render();
}

function removeEntry(name) {
  state.entries = state.entries.filter((e) => e.name !== name);
  render();
}

function addTarget(entry, doRender = true) {
  entry.targets.push({ values: {}, secrets: {} });
  if (doRender) render();
}

function removeTarget(entry, idx) {
  entry.targets.splice(idx, 1);
  render();
}

// ---- Rendering the builder -------------------------------------------------
function render() {
  renderPlatforms();
  renderEntries();
  markAdded();
  $("#empty-hint").style.display = state.entries.length ? "none" : "";
  $("#preview").textContent = JSON.stringify(buildManifest(), null, 2);
}

function fieldInput(descriptor, value, onChange) {
  let input;
  if (descriptor.type === "boolean") {
    input = el("input");
    input.type = "checkbox";
    input.checked = value === true || value === "true";
    input.onchange = () => onChange(input.checked);
  } else {
    input = el("input");
    input.type = descriptor.type === "integer" ? "number" : "text";
    if (value != null) input.value = value;
    if (descriptor.default != null) input.placeholder = String(descriptor.default);
    input.onchange = () => {
      let v = input.value;
      if (descriptor.type === "integer" && v !== "") v = parseInt(v, 10);
      onChange(v === "" ? undefined : v);
    };
  }
  return input;
}

function labelFor(d) {
  const lab = el("label");
  lab.appendChild(document.createTextNode(d.name));
  if (d.required) lab.appendChild(el("span", "req", " *"));
  return lab;
}

function renderConfigFields(container, descriptors, store) {
  if (!descriptors.length) return;
  const fs = el("div", "fieldset");
  fs.appendChild(el("div", "legend", "config"));
  const grid = el("div", "grid");
  for (const d of descriptors) {
    const field = el("div", "field");
    field.appendChild(labelFor(d));
    field.appendChild(fieldInput(d, store[d.name], (v) => { store[d.name] = v; refreshPreview(); }));
    if (d.description) field.appendChild(el("div", "help", d.description));
    grid.appendChild(field);
  }
  fs.appendChild(grid);
  container.appendChild(fs);
}

// Secrets are edited as the NAME of the env var that holds them (never a value).
function renderSecretFields(container, secretDescriptors, store, legend) {
  if (!secretDescriptors.length) return;
  const fs = el("div", "fieldset");
  fs.appendChild(el("div", "legend", legend));
  const grid = el("div", "grid");
  for (const d of secretDescriptors) {
    const field = el("div", "field");
    field.appendChild(labelFor(d));
    const input = el("input");
    input.type = "text";
    input.placeholder = d.env || "ENV_VAR_NAME";
    if (store[d.name] != null) input.value = store[d.name];
    else if (d.env) { store[d.name] = d.env; input.value = d.env; } // sensible default
    input.onchange = () => { store[d.name] = input.value.trim() || undefined; refreshPreview(); };
    field.appendChild(input);
    field.appendChild(el("div", "secret-hint", "env var → ${env:NAME}"));
    grid.appendChild(field);
  }
  fs.appendChild(grid);
  container.appendChild(fs);
}

function renderEntries() {
  const root = $("#entries");
  root.innerHTML = "";
  for (const entry of state.entries) {
    const f = state.fetchersByName[entry.name] || { config: [], secrets: [], target_schema: [], supports_targets: false };
    const card = el("div", "entry");

    const head = el("div", "entry-head");
    const title = el("span", "title", entry.name);
    if (f.description) title.appendChild(el("span", "desc", f.description));
    const rm = el("button", "btn btn-ghost", "Remove");
    rm.onclick = () => removeEntry(entry.name);
    head.appendChild(title);
    head.appendChild(rm);
    card.appendChild(head);

    renderConfigFields(card, f.config, entry.config);

    const entrySecrets = f.secrets.filter((s) => !s.per_target);
    const targetSecrets = f.secrets.filter((s) => s.per_target);
    renderSecretFields(card, entrySecrets, entry.secrets, "secrets");

    if (f.supports_targets) {
      const fs = el("div", "fieldset");
      const legend = el("div", "legend");
      legend.textContent = "targets";
      fs.appendChild(legend);
      entry.targets.forEach((t, idx) => {
        const tdiv = el("div", "target");
        const th = el("div", "target-head");
        th.appendChild(el("span", "tname", `target ${idx + 1}`));
        const trm = el("button", "btn btn-ghost", "✕");
        trm.onclick = () => removeTarget(entry, idx);
        th.appendChild(trm);
        tdiv.appendChild(th);

        const grid = el("div", "grid");
        for (const d of f.target_schema) {
          const field = el("div", "field");
          field.appendChild(labelFor(d));
          field.appendChild(fieldInput(d, t.values[d.name], (v) => { t.values[d.name] = v; refreshPreview(); }));
          if (d.description) field.appendChild(el("div", "help", d.description));
          grid.appendChild(field);
        }
        tdiv.appendChild(grid);
        renderSecretFields(tdiv, targetSecrets, t.secrets, "per-target secrets");
        fs.appendChild(tdiv);
      });
      const addBtn = el("button", "btn btn-ghost", "+ Add target");
      addBtn.onclick = () => addTarget(entry);
      fs.appendChild(addBtn);
      card.appendChild(fs);
    }

    root.appendChild(card);
  }
}

function renderPlatforms() {
  const root = $("#platforms");
  root.innerHTML = "";
  const present = new Set(state.entries.map((e) => state.fetchersByName[e.name]?.category).filter(Boolean));
  for (const cat of present) {
    const spec = state.platformByCategory[cat];
    if (!spec) continue;
    const store = state.platforms[cat] || (state.platforms[cat] = { config: {}, passthrough: [...(spec.passthrough_env || [])] });
    const card = el("div", "platform");
    const head = el("div", "platform-head");
    head.appendChild(el("span", "title", `${cat} platform`));
    card.appendChild(head);
    renderConfigFields(card, spec.config, store.config);

    // passthrough_env editor (ambient cloud-identity vars; comma/space separated)
    const fs = el("div", "fieldset");
    fs.appendChild(el("div", "legend", "auth.passthrough_env"));
    const field = el("div", "field");
    const input = el("input");
    input.type = "text";
    input.placeholder = "e.g. AWS_WEB_IDENTITY_TOKEN_FILE, AWS_ROLE_ARN";
    input.value = (store.passthrough || []).join(", ");
    input.onchange = () => { store.passthrough = input.value.split(/[\s,]+/).filter(Boolean); refreshPreview(); };
    field.appendChild(input);
    field.appendChild(el("div", "help", "ambient env vars to let through the runner whitelist (no secret value)"));
    fs.appendChild(field);
    card.appendChild(fs);

    root.appendChild(card);
  }
}

function refreshPreview() {
  $("#preview").textContent = JSON.stringify(buildManifest(), null, 2);
}

// ---- Manifest build / load -------------------------------------------------
function buildManifest() {
  const run = { output_dir: $("#output-dir").value || "./evidence" };

  const platforms = {};
  for (const [cat, store] of Object.entries(state.platforms)) {
    if (!state.entries.some((e) => state.fetchersByName[e.name]?.category === cat)) continue;
    const block = {};
    const cfg = Object.fromEntries(Object.entries(store.config || {}).filter(([, v]) => v !== undefined && v !== ""));
    if (Object.keys(cfg).length) block.config = cfg;
    if ((store.passthrough || []).length) block.auth = { passthrough_env: store.passthrough };
    if (Object.keys(block).length) platforms[cat] = block;
  }
  if (Object.keys(platforms).length) run.platforms = platforms;

  run.fetchers = state.entries.map((entry) => {
    const out = { use: entry.name };
    const cfg = Object.fromEntries(Object.entries(entry.config).filter(([, v]) => v !== undefined && v !== ""));
    if (Object.keys(cfg).length) out.config = cfg;
    const secrets = wrapSecrets(entry.secrets);
    if (Object.keys(secrets).length) out.secrets = secrets;
    if (entry.targets.length) {
      out.targets = entry.targets.map((t) => {
        const tv = Object.fromEntries(Object.entries(t.values).filter(([, v]) => v !== undefined && v !== ""));
        const ts = wrapSecrets(t.secrets);
        if (Object.keys(ts).length) tv.secrets = ts;
        return tv;
      });
    }
    return out;
  });

  return { run };
}

function wrapSecrets(store) {
  const out = {};
  for (const [name, envVar] of Object.entries(store)) {
    if (envVar) out[name] = `\${env:${envVar}}`;
  }
  return out;
}

const ENV_REF = /^\$\{env:([A-Z_][A-Z0-9_]*)\}$/;
function unwrapSecret(ref) {
  const m = (ref || "").match(ENV_REF);
  return m ? m[1] : ref;
}

function loadManifest(dict) {
  const run = (dict && dict.run) || {};
  $("#output-dir").value = run.output_dir || "./evidence";
  state.entries = [];
  state.platforms = {};

  for (const [cat, block] of Object.entries(run.platforms || {})) {
    state.platforms[cat] = {
      config: { ...(block.config || {}) },
      passthrough: [...((block.auth && block.auth.passthrough_env) || [])],
    };
  }

  for (const fe of run.fetchers || []) {
    const entry = { name: fe.use, config: { ...(fe.config || {}) }, secrets: {}, targets: [] };
    for (const [k, v] of Object.entries(fe.secrets || {})) entry.secrets[k] = unwrapSecret(v);
    for (const t of fe.targets || []) {
      const target = { values: {}, secrets: {} };
      for (const [k, v] of Object.entries(t)) {
        if (k === "secrets") { for (const [sk, sv] of Object.entries(v)) target.secrets[sk] = unwrapSecret(sv); }
        else target.values[k] = v;
      }
      entry.targets.push(target);
    }
    state.entries.push(entry);
  }
  render();
}

// ---- Banner / actions ------------------------------------------------------
function showBanner(kind, text) {
  const b = $("#banner");
  b.className = `banner ${kind}`;
  b.textContent = text;
}
function clearBanner() { $("#banner").className = "banner hidden"; }

async function doValidate() {
  const r = await fetch("/api/manifest/validate", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ manifest: buildManifest() }),
  });
  const data = await r.json();
  if (data.ok) showBanner("ok", "✓ Manifest valid and runnable.");
  else showBanner("err", "Validation errors:\n  " + data.errors.join("\n  "));
  return data.ok;
}

async function doSave() {
  const path = $("#manifest-path").value || "manifest.yaml";
  const r = await fetch("/api/manifest", {
    method: "PUT", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path, manifest: buildManifest() }),
  });
  if (!r.ok) { const e = await r.json(); showBanner("err", "Save failed: " + e.detail); return; }
  const data = await r.json();
  if (data.errors.length) showBanner("err", `Saved to ${data.path}, but not yet runnable:\n  ` + data.errors.join("\n  "));
  else showBanner("ok", `✓ Saved to ${data.path}.`);
}

function logLine(cls, text) {
  const line = el("div", `log-line ${cls}`, text);
  const log = $("#run-log");
  log.appendChild(line);
  log.scrollTop = log.scrollHeight;
}

function setStatus(cls, text) {
  const s = $("#run-status");
  s.innerHTML = "";
  s.appendChild(el("span", `pill ${cls}`, text));
}

async function doRun() {
  if (!(await doValidate())) return;
  clearBanner();
  $("#run-log").innerHTML = "";
  setStatus("run", "running…");
  $("#btn-run").disabled = true;
  try {
    const resp = await fetch("/api/run", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ manifest: buildManifest() }),
    });
    const reader = resp.body.getReader();
    const dec = new TextDecoder();
    let buf = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let idx;
      while ((idx = buf.indexOf("\n\n")) >= 0) {
        const chunk = buf.slice(0, idx);
        buf = buf.slice(idx + 2);
        if (chunk.startsWith("data: ")) handleRunEvent(JSON.parse(chunk.slice(6)));
      }
    }
  } catch (e) {
    logLine("err", "stream error: " + e);
    setStatus("fail", "error");
  } finally {
    $("#btn-run").disabled = false;
  }
}

function handleRunEvent(ev) {
  switch (ev.event) {
    case "run_start":
      logLine("start", `▸ run ${ev.run_id} → ${ev.run_dir}`);
      break;
    case "fetcher_start":
      logLine("start", `▸ ${ev.fetcher}${ev.fanout ? ` (${ev.targets} targets)` : ""}`);
      break;
    case "fetcher_skip":
      logLine("err", `  SKIP ${ev.fetcher} (${ev.reason})`);
      break;
    case "log_line":
      logLine("out", `    ${ev.line}`);
      break;
    case "fetcher_result": {
      const ok = ev.exit_code === 0;
      const tgt = ev.target ? "  " + JSON.stringify(ev.target) : "";
      logLine(ok ? "result-ok" : "result-fail",
        `  [${ok ? "OK" : "FAIL"}] exit=${ev.exit_code} ${ev.duration_sec}s${tgt}  → ${(ev.outputs || []).join(", ") || "(no files)"}`);
      break;
    }
    case "fetcher_error":
      logLine("err", `  ERROR ${ev.fetcher}: ${ev.error}`);
      break;
    case "run_error":
      logLine("err", `run error: ${ev.error}`);
      setStatus("fail", "error");
      break;
    case "run_complete":
      setStatus(ev.ok ? "ok" : "fail", ev.ok ? "complete ✓" : "complete (failures)");
      logLine(ev.ok ? "result-ok" : "result-fail", `▸ done → ${ev.metadata_path}`);
      break;
  }
}

// ---- Wiring ----------------------------------------------------------------
function wireControls() {
  $("#catalog-search").addEventListener("input", applyCatalogFilter);
  $("#output-dir").addEventListener("change", refreshPreview);
  $("#btn-validate").addEventListener("click", doValidate);
  $("#btn-save").addEventListener("click", doSave);
  $("#btn-run").addEventListener("click", doRun);
  $("#example-picker").addEventListener("change", async (e) => {
    const path = e.target.value;
    if (!path) return;
    $("#manifest-path").value = path;
    const data = await (await fetch("/api/manifest?path=" + encodeURIComponent(path))).json();
    loadManifest(data.manifest);
    clearBanner();
  });
}

boot();
