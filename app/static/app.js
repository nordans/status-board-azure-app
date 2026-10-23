"use strict";

const $ = (id) => document.getElementById(id);
const labels = {operational: "Operational", degraded: "Degraded", outage: "Outage", maintenance: "Maintenance", unknown: "Awaiting report"};
const dialog = $("update-dialog");
const form = $("update-form");
let toastTimer;

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function badge(status) {
  const node = element("span", `badge ${status}`);
  node.append(element("i", `dot ${status}`), document.createTextNode(labels[status]));
  return node;
}

function timestamp(value) {
  if (!value) return "No report yet";
  return new Date(value).toLocaleTimeString([], {hour: "2-digit", minute: "2-digit", second: "2-digit"});
}

function renderServices(services) {
  const rows = services.map((service, index) => {
    const row = element("article", "service-row");
    const main = element("div", "service-main");
    const icon = element("span", "service-icon", ["⌘", "⇄", "↗"][index % 3]);
    icon.setAttribute("aria-hidden", "true");
    const text = element("div", "service-text");
    text.append(element("h3", "service-name", service.name), element("p", "service-description", service.description));
    if (service.updated_at && service.message) text.append(element("p", "service-message", service.message));
    main.append(icon, text);
    const latency = element("div", "service-latency", service.response_time_ms === null ? "—" : `${service.response_time_ms} ms`);
    latency.append(element("small", "", "reported latency"));
    const state = element("div", "service-state");
    const updated = element("time", "updated-at", timestamp(service.updated_at));
    if (service.updated_at) { updated.dateTime = service.updated_at; updated.title = new Date(service.updated_at).toLocaleString(); }
    state.append(badge(service.status), updated);
    row.append(main, latency, state);
    return row;
  });
  $("services").replaceChildren(...rows);
}

function renderEvents(events) {
  $("event-count").textContent = `${events.length} UPDATE${events.length === 1 ? "" : "S"} · LAST 50`;
  if (!events.length) {
    const empty = element("div", "empty-state");
    empty.append(element("span", "empty-icon", "↳"), element("h3", "", "A quiet start"), element("p", "", "Service reports will appear here as they arrive."));
    $("activity").replaceChildren(empty);
    return;
  }
  $("activity").replaceChildren(...events.slice(0, 8).map((event) => {
    const row = element("article", "activity-row");
    const time = element("time", "activity-time", timestamp(event.created_at));
    time.dateTime = event.created_at;
    time.title = new Date(event.created_at).toLocaleString();
    const copy = element("div", "activity-copy");
    copy.append(element("h3", "activity-name", event.service_name), element("p", "activity-message", event.message || "Status report received."));
    row.append(time, copy, badge(event.status));
    return row;
  }));
}

function renderSummary(services) {
  const counts = Object.fromEntries(Object.keys(labels).map((key) => [key, services.filter((s) => s.status === key).length]));
  $("count-total").textContent = services.length;
  $("count-operational").textContent = counts.operational;
  $("count-attention").textContent = counts.degraded + counts.outage + counts.maintenance;
  $("count-unknown").textContent = counts.unknown;
  const state = ["outage", "degraded", "maintenance", "unknown"].find((key) => counts[key]) || "operational";
  const messages = {
    outage: ["Service disruption reported", "One or more services have an active outage report.", "!"],
    degraded: ["Some services need attention", "Degraded performance has been reported. See the latest updates below.", "!"],
    maintenance: ["Maintenance in progress", "One or more services are undergoing planned maintenance.", "↻"],
    unknown: [counts.unknown === services.length ? "Waiting for service reports" : "Some services are awaiting reports", "Unreported services remain unknown until a status is submitted.", "—"],
    operational: ["All services operational", "All services were operational in their latest submitted reports.", "✓"],
  };
  $("summary").dataset.state = state;
  [$("summary-title").textContent, $("summary-description").textContent, $("summary-icon").textContent] = messages[state];
  $("summary-count").textContent = `${services.length - counts.unknown} of ${services.length} services reporting`;
}

async function refresh() {
  try {
    const response = await fetch("/api/status", {cache: "no-store", signal: AbortSignal.timeout(8000)});
    if (!response.ok) throw new Error("Status unavailable");
    const data = await response.json();
    document.title = `${data.title} · Status Board`;
    $("board-title").textContent = data.title;
    $("environment").textContent = data.environment.toUpperCase();
    $("runtime-meta").textContent = `${data.version} · ${data.instance} · up ${Math.floor(data.uptime_seconds / 60)}m`;
    $("refresh-state").textContent = `Updated ${timestamp(data.generated_at)}`;
    $("connection-error").hidden = true;
    renderSummary(data.services);
    renderServices(data.services);
    renderEvents(data.events);
    const selected = $("service-select").value;
    $("service-select").replaceChildren(...data.services.map((service) => {
      const option = element("option", "", service.name);
      option.value = service.id;
      return option;
    }));
    if (data.services.some((service) => service.id === selected)) $("service-select").value = selected;
  } catch {
    $("connection-error").hidden = false;
    $("refresh-state").textContent = "Connection lost";
  }
}

$("open-update").addEventListener("click", () => { $("form-error").hidden = true; dialog.showModal(); });
for (const id of ["close-update", "cancel-update"]) $(id).addEventListener("click", () => dialog.close());
dialog.addEventListener("close", () => { form.reset(); $("form-error").hidden = true; });

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  $("submit-update").disabled = true;
  $("form-error").hidden = true;
  try {
    const latency = $("latency-input").value;
    const response = await fetch(`/api/services/${encodeURIComponent($("service-select").value)}/status`, {
      method: "PUT",
      headers: {"Content-Type": "application/json", "Authorization": `Bearer ${$("token-input").value.trim()}`},
      body: JSON.stringify({status: $("status-select").value, message: $("message-input").value.trim(), response_time_ms: latency === "" ? null : Number(latency)}),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) {
      const errors = {401: "The token is invalid. Check your secret file and try again.", 503: "Admin authentication is unavailable. Check the mounted token file.", 404: "Service not found. Refresh the page and try again.", 422: "Check the status, message and reported latency."};
      throw new Error(errors[response.status] || "The update could not be published.");
    }
    dialog.close();
    await refresh();
    $("toast").hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { $("toast").hidden = true; }, 4000);
  } catch (error) {
    $("form-error").textContent = error.name === "TimeoutError" ? "Request timed out. Refresh to check whether it was applied." : error.message;
    $("form-error").hidden = false;
  } finally {
    $("token-input").value = "";
    $("submit-update").disabled = false;
  }
});

async function poll() {
  await refresh();
  setTimeout(poll, 10000);
}
poll();
