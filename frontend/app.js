// Frontend mínimo sin dependencias. Autentica contra Cognito con la API
// InitiateAuth (USER_PASSWORD_AUTH) y llama a la API vía CloudFront (/api/*).
const CFG = window.TELEMED_CONFIG;
const $ = (id) => document.getElementById(id);
const LOCAL_MODE = CFG?.mode === "local";
let session = JSON.parse(sessionStorage.getItem("telemed") || "null");

const localStore = {
  get docs() { return JSON.parse(localStorage.getItem("telemed-docs") || "[]"); },
  set docs(value) { localStorage.setItem("telemed-docs", JSON.stringify(value)); },
  get consents() { return JSON.parse(localStorage.getItem("telemed-consents") || "[]"); },
  set consents(value) { localStorage.setItem("telemed-consents", JSON.stringify(value)); },
};

function log(msg) {
  $("log").textContent = `[${new Date().toLocaleTimeString()}] ${msg}\n` + $("log").textContent;
}

function decodeJwt(token) {
  const b64 = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(decodeURIComponent(escape(atob(b64))));
}

async function login(role, email, password) {
  if (LOCAL_MODE) {
    const safeEmail = email.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    session = {
      idToken: "local-demo-token",
      claims: {
        sub: role === "medico" ? "local-medico-demo" : `local-paciente-${safeEmail}`,
        email,
        "custom:role": role,
        ...(role === "medico" ? { "custom:license": "LOCAL-001" } : {}),
        iss: "telemed-local",
        exp: Math.floor(Date.now() / 1000) + 86400,
      },
    };
    sessionStorage.setItem("telemed", JSON.stringify(session));
    return;
  }
  const { clientId } = CFG.pools[role];
  const res = await fetch(`https://cognito-idp.${CFG.region}.amazonaws.com/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Target": "AWSCognitoIdentityProviderService.InitiateAuth",
    },
    body: JSON.stringify({
      AuthFlow: "USER_PASSWORD_AUTH",
      ClientId: clientId,
      AuthParameters: { USERNAME: email, PASSWORD: password },
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.message || "Login fallido");
  if (!data.AuthenticationResult) throw new Error(`Reto no soportado en la demo: ${data.ChallengeName}`);
  const idToken = data.AuthenticationResult.IdToken;
  session = { idToken, claims: decodeJwt(idToken) };
  sessionStorage.setItem("telemed", JSON.stringify(session));
}

async function api(method, path, body) {
  if (LOCAL_MODE) return localApi(method, path, body);
  const res = await fetch(path, {
    method,
    headers: {
      Authorization: `Bearer ${session.idToken}`,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  log(`${method} ${path} -> ${res.status}`);
  if (!res.ok) throw new Error(data.error || data.message || `HTTP ${res.status}`);
  return data;
}

async function localApi(method, path, body) {
  const role = session.claims["custom:role"];
  const userId = session.claims.sub;
  let result;

  if (method === "GET" && path === "/api/documents") {
    result = { documents: localStore.docs.filter((d) => d.patientId === userId) };
  } else if (method === "POST" && path === "/api/consents") {
    const key = `${userId}:${body.doctorId}`;
    localStore.consents = [...new Set([...localStore.consents, key])];
    result = { created: true };
  } else if (method === "GET" && path.startsWith("/api/medico/patients/")) {
    const patientId = decodeURIComponent(path.split("/")[4]);
    if (role !== "medico" || !localStore.consents.includes(`${patientId}:${userId}`)) {
      throw new Error("El paciente todavía no ha autorizado a este médico");
    }
    result = { documents: localStore.docs.filter((d) => d.patientId === patientId) };
  } else if (method === "GET" && /^\/api\/documents\/[^/]+\/download-url$/.test(path)) {
    const documentId = path.split("/")[3];
    const doc = localStore.docs.find((d) => d.documentId === documentId);
    if (!doc) throw new Error("Documento no encontrado");
    const allowed = doc.patientId === userId ||
      (role === "medico" && localStore.consents.includes(`${doc.patientId}:${userId}`));
    if (!allowed) throw new Error("No tienes permiso para abrir este documento");
    const expiresIn = doc.docType === "informe" ? 3600 : 300;
    result = { url: doc.dataUrl, expiresIn, expiresAt: Date.now() + expiresIn * 1000 };
  } else {
    throw new Error(`Ruta local no implementada: ${method} ${path}`);
  }

  log(`[LOCAL] ${method} ${path} -> 200`);
  return result;
}

function readAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(new Error("No se pudo leer el archivo"));
    reader.readAsDataURL(file);
  });
}

function render() {
  const role = session?.claims?.["custom:role"];
  $("environment").textContent = LOCAL_MODE ? "DEMO LOCAL" : "AWS";
  $("local-help").classList.toggle("hidden", !LOCAL_MODE);
  $("login-view").classList.toggle("hidden", !!session);
  $("logout").classList.toggle("hidden", !session);
  $("paciente-view").classList.toggle("hidden", role !== "paciente");
  $("medico-view").classList.toggle("hidden", role !== "medico");
  $("who").textContent = session ? `${session.claims.email} · ${role}` : "";
  $("claims").textContent = session
    ? JSON.stringify(
        Object.fromEntries(Object.entries(session.claims).filter(([k]) =>
          k.startsWith("custom:") || ["sub", "email", "iss", "exp"].includes(k))),
        null, 2)
    : "—";
  if (role === "paciente") { $("my-sub").textContent = session.claims.sub; loadMyDocs(); }
  if (role === "medico") $("doc-sub").textContent = session.claims.sub;
}

function docsTable(tableId, docs) {
  const t = $(tableId);
  t.innerHTML = "<tr><th>Archivo</th><th>Tipo</th><th>Fecha</th><th></th></tr>";
  for (const d of docs) {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td>${d.fileName}</td><td>${d.docType}</td>
      <td>${new Date(d.uploadedAt).toLocaleString()}</td><td><button class="small">Ver</button></td>`;
    tr.querySelector("button").onclick = () => openDoc(d.documentId);
    t.appendChild(tr);
  }
  if (!docs.length) t.innerHTML += "<tr><td colspan=4 class=muted>Sin documentos</td></tr>";
}

async function loadMyDocs() {
  try { docsTable("my-docs", (await api("GET", "/api/documents")).documents); }
  catch (e) { log(e.message); }
}

async function openDoc(documentId) {
  try {
    const r = await api("GET", `/api/documents/${documentId}/download-url`);
    log(`URL válida ${r.expiresIn / 60} min (expira ${new Date(r.expiresAt).toLocaleTimeString()})`);
    window.open(r.url, "_blank", "noopener");
  } catch (e) { alert(e.message); }
}

$("login-form").onsubmit = async (ev) => {
  ev.preventDefault();
  try { await login($("login-role").value, $("login-email").value, $("login-pass").value); render(); }
  catch (e) { alert(e.message); }
};

$("logout").onclick = () => { sessionStorage.removeItem("telemed"); session = null; render(); };
$("refresh").onclick = loadMyDocs;

$("upload-form").onsubmit = async (ev) => {
  ev.preventDefault();
  const file = $("file").files[0];
  const docType = $("doc-type").value;
  const contentType = file.type || (file.name.endsWith(".dcm") ? "application/dicom" : "");
  try {
    if (LOCAL_MODE) {
      if (file.size > 2 * 1024 * 1024) throw new Error("En la demo local usa archivos de máximo 2 MB");
      const docs = localStore.docs;
      const documentId = crypto.randomUUID();
      docs.push({
        documentId,
        patientId: session.claims.sub,
        fileName: file.name,
        docType,
        contentType,
        uploadedAt: new Date().toISOString(),
        dataUrl: await readAsDataUrl(file),
      });
      localStore.docs = docs;
      log(`[LOCAL] Documento guardado en el navegador: ${documentId}`);
      await loadMyDocs();
      ev.target.reset();
      return;
    }
    const u = await api("POST", "/api/documents/upload-url", { fileName: file.name, docType, contentType });
    const put = await fetch(u.uploadUrl, { method: "PUT", headers: u.requiredHeaders, body: file });
    if (!put.ok) throw new Error(`S3 respondió ${put.status}`);
    log(`Subido (SSE-KMS). Indexando ${u.documentId}…`);
    setTimeout(loadMyDocs, 2500);
  } catch (e) { alert(e.message); }
};

$("consent-form").onsubmit = async (ev) => {
  ev.preventDefault();
  try { await api("POST", "/api/consents", { doctorId: $("doctor-id").value.trim() }); alert("Médico autorizado"); }
  catch (e) { alert(e.message); }
};

$("patient-form").onsubmit = async (ev) => {
  ev.preventDefault();
  try {
    const r = await api("GET", `/api/medico/patients/${$("patient-id").value.trim()}/documents`);
    docsTable("patient-docs", r.documents);
  } catch (e) { alert(e.message); }
};

if (session && session.claims.exp * 1000 < Date.now()) { sessionStorage.removeItem("telemed"); session = null; }
render();
