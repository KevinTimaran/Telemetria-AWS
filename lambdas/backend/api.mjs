/**
 * Lambda de la API de documentos (integración proxy de API Gateway).
 * La identidad llega desde el Lambda Authorizer en requestContext.authorizer.
 */
import { randomUUID } from "node:crypto";
import { GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { DOC_TYPES, DOCS_BUCKET, UPLOAD_TTL_SECONDS, UUID_REGEX, s3 } from "./config.mjs";
import { audit, query } from "./db.mjs";

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const json = (statusCode, body) => ({
  statusCode,
  headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  const a = event.requestContext?.authorizer || {};
  const user = { sub: a.sub, role: a.role, license: a.license, email: a.email };
  const route = `${event.httpMethod} ${event.resource}`;

  try {
    if (!user.sub || !user.role) throw new HttpError(401, "Sin identidad");

    switch (route) {
      case "GET /api/me":
        return json(200, user);

      case "POST /api/documents/upload-url":
        requireRole(user, "paciente");
        return json(200, await createUploadUrl(user, parseBody(event)));

      case "GET /api/documents":
        requireRole(user, "paciente");
        return json(200, await listDocuments(user.sub));

      case "GET /api/documents/{documentId}/download-url":
        return json(200, await createDownloadUrl(user, event.pathParameters?.documentId));

      case "POST /api/consents":
        requireRole(user, "paciente");
        return json(201, await grantConsent(user, parseBody(event)));

      case "GET /api/medico/patients/{patientId}/documents": {
        requireRole(user, "medico");
        const patientId = event.pathParameters?.patientId;
        await requireConsent(user, patientId);
        return json(200, await listDocuments(patientId));
      }

      default:
        throw new HttpError(404, `Ruta no encontrada: ${route}`);
    }
  } catch (err) {
    if (err instanceof HttpError) return json(err.status, { error: err.message });
    console.error(err);
    return json(500, { error: "Error interno" });
  }
};

// ---------------------------------------------------------------------------

function requireRole(user, role) {
  // Defensa en profundidad: el authorizer ya filtra, pero se revalida aquí.
  if (user.role !== role) throw new HttpError(403, `Solo el rol '${role}' puede usar este endpoint`);
}

function parseBody(event) {
  try {
    return JSON.parse(event.body || "{}");
  } catch {
    throw new HttpError(400, "JSON inválido");
  }
}

function sanitizeFileName(name) {
  const clean = String(name || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9._-]/g, "_")
    .slice(-100);
  if (!clean || /^\.+$/.test(clean)) throw new HttpError(400, "fileName inválido");
  return clean;
}

/** Presigned PUT: el paciente sube a su propio prefijo patients/{sub}/... */
async function createUploadUrl(user, { fileName, docType, contentType }) {
  const cfg = DOC_TYPES[docType];
  if (!cfg) throw new HttpError(400, `docType debe ser uno de: ${Object.keys(DOC_TYPES).join(", ")}`);
  if (!cfg.contentTypes.includes(contentType)) {
    throw new HttpError(400, `contentType no permitido para ${docType}: ${cfg.contentTypes.join(", ")}`);
  }

  const documentId = randomUUID();
  const safeName = sanitizeFileName(fileName);
  const key = `patients/${user.sub}/${docType}/${documentId}/${safeName}`;

  // No se especifica SSE en la URL: el bucket aplica por defecto SSE-KMS con la CMK,
  // y como la URL la firma el rol Lambda, KMS autoriza al rol Lambda.
  const uploadUrl = await getSignedUrl(
    s3,
    new PutObjectCommand({ Bucket: DOCS_BUCKET, Key: key, ContentType: contentType }),
    { expiresIn: UPLOAD_TTL_SECONDS }
  );

  await audit({ documentId, user, accion: "UPLOAD_URL", resultado: "OK", expiresIn: UPLOAD_TTL_SECONDS });

  return {
    documentId,
    uploadUrl,
    method: "PUT",
    requiredHeaders: { "Content-Type": contentType },
    expiresIn: UPLOAD_TTL_SECONDS,
  };
}

async function listDocuments(patientId) {
  if (!UUID_REGEX.test(patientId || "")) throw new HttpError(400, "patientId inválido");
  const rows = await query(
    `SELECT document_id AS documentId, doc_type AS docType, file_name AS fileName,
            content_type AS contentType, size_bytes AS sizeBytes, uploaded_at AS uploadedAt
       FROM documentos WHERE patient_id = ? ORDER BY uploaded_at DESC LIMIT 100`,
    [patientId]
  );
  return { patientId, documents: rows };
}

/**
 * Presigned GET con duración dinámica según el tipo de documento.
 * REGLA CLAVE: para un paciente, el sub del token DEBE ser igual al patientId
 * del documento. Para un médico, debe existir consentimiento del paciente.
 */
async function createDownloadUrl(user, documentId) {
  if (!UUID_REGEX.test(documentId || "")) throw new HttpError(400, "documentId inválido");

  const [doc] = await query(
    `SELECT document_id, patient_id, doc_type, file_name, s3_key FROM documentos WHERE document_id = ?`,
    [documentId]
  );
  if (!doc) throw new HttpError(404, "Documento no encontrado");

  if (user.role === "paciente") {
    // Se valida contra la BD y también contra el prefijo de la clave S3.
    const ownsRecord = doc.patient_id === user.sub;
    const ownsKey = doc.s3_key.startsWith(`patients/${user.sub}/`);
    if (!ownsRecord || !ownsKey) {
      await audit({ documentId, user, accion: "DOWNLOAD_URL", resultado: "DENEGADO" });
      throw new HttpError(403, "El sub del token no coincide con el patientId del documento");
    }
  } else if (user.role === "medico") {
    await requireConsent(user, doc.patient_id, documentId);
  } else {
    throw new HttpError(403, "Rol desconocido");
  }

  const expiresIn = DOC_TYPES[doc.doc_type].downloadTtlSeconds;
  const url = await getSignedUrl(
    s3,
    new GetObjectCommand({
      Bucket: DOCS_BUCKET,
      Key: doc.s3_key,
      ResponseContentDisposition: `inline; filename="${doc.file_name}"`,
      ResponseCacheControl: "no-store",
    }),
    { expiresIn }
  );

  await audit({ documentId, user, accion: "DOWNLOAD_URL", resultado: "OK", expiresIn });

  return {
    documentId,
    docType: doc.doc_type,
    url,
    expiresIn,
    expiresAt: new Date(Date.now() + expiresIn * 1000).toISOString(),
  };
}

async function grantConsent(user, { doctorId }) {
  if (!UUID_REGEX.test(doctorId || "")) throw new HttpError(400, "doctorId (sub del médico) inválido");
  await query(`INSERT IGNORE INTO consentimientos (patient_id, doctor_id) VALUES (?, ?)`, [user.sub, doctorId]);
  await audit({ user, accion: `CONSENT:${doctorId}`, resultado: "OK" });
  return { patientId: user.sub, doctorId };
}

async function requireConsent(user, patientId, documentId = null) {
  if (!UUID_REGEX.test(patientId || "")) throw new HttpError(400, "patientId inválido");
  const rows = await query(
    `SELECT 1 FROM consentimientos WHERE patient_id = ? AND doctor_id = ?`,
    [patientId, user.sub]
  );
  if (rows.length === 0) {
    await audit({ documentId, user, accion: "ACCESO_MEDICO", resultado: "DENEGADO" });
    throw new HttpError(403, "El paciente no ha autorizado a este médico");
  }
}
