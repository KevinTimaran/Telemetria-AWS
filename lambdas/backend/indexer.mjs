/**
 * Indexador: se dispara con s3:ObjectCreated:* y guarda los metadatos en RDS MySQL.
 */
import { HeadObjectCommand } from "@aws-sdk/client-s3";
import { DOC_TYPES, KEY_REGEX, KMS_KEY_ARN, s3 } from "./config.mjs";
import { query } from "./db.mjs";

export const handler = async (event) => {
  for (const record of event.Records || []) {
    const bucket = record.s3.bucket.name;
    // Las claves llegan URL-encoded (espacios como '+').
    const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));

    const match = key.match(KEY_REGEX);
    if (!match) {
      console.warn("Clave con formato inesperado, se ignora:", key);
      continue;
    }
    const [, patientId, docType, documentId, fileName] = match;

    const head = await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));

    // Verificación: el objeto debe estar cifrado con NUESTRA CMK.
    if (head.ServerSideEncryption !== "aws:kms" || head.SSEKMSKeyId !== KMS_KEY_ARN) {
      console.error("Objeto sin la CMK esperada, no se indexa:", key, head.SSEKMSKeyId);
      continue;
    }

    if (!DOC_TYPES[docType].contentTypes.includes(head.ContentType)) {
      console.warn(`Content-Type ${head.ContentType} no esperado para ${docType}:`, key);
    }

    await query(
      `INSERT INTO documentos
         (document_id, patient_id, doc_type, file_name, s3_key, content_type,
          size_bytes, kms_key_arn, version_id, uploaded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         size_bytes = VALUES(size_bytes), version_id = VALUES(version_id),
         content_type = VALUES(content_type), uploaded_at = VALUES(uploaded_at)`,
      [
        documentId,
        patientId,
        docType,
        fileName,
        key,
        head.ContentType || null,
        head.ContentLength ?? record.s3.object.size,
        head.SSEKMSKeyId,
        head.VersionId || null,
        new Date(record.eventTime),
      ]
    );

    console.log(JSON.stringify({ indexado: documentId, patientId, docType, key }));
  }
};
