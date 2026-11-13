import { S3Client } from "@aws-sdk/client-s3";

/**
 * Tipos de documento y duración de sus presigned URLs de DESCARGA.
 *  - imagen_diagnostica: 5 minutos
 *  - informe:            1 hora
 */
export const DOC_TYPES = {
  imagen_diagnostica: {
    downloadTtlSeconds: 5 * 60,
    contentTypes: ["image/jpeg", "image/png", "application/dicom"],
  },
  informe: {
    downloadTtlSeconds: 60 * 60,
    contentTypes: ["application/pdf"],
  },
};

// Las URLs de SUBIDA siempre son cortas.
export const UPLOAD_TTL_SECONDS = 5 * 60;

export const DOCS_BUCKET = process.env.DOCS_BUCKET;
export const KMS_KEY_ARN = process.env.KMS_KEY_ARN;

// Sin checksums automáticos: si no, el SDK v3 agrega x-amz-checksum-* a la
// presigned URL y el navegador tendría que enviarlos.
export const s3 = new S3Client({
  requestChecksumCalculation: "WHEN_REQUIRED",
  responseChecksumValidation: "WHEN_REQUIRED",
});

// patients/{patientSub}/{docType}/{documentId}/{fileName}
export const KEY_REGEX =
  /^patients\/([0-9a-f-]{36})\/(imagen_diagnostica|informe)\/([0-9a-f-]{36})\/(.+)$/;

export const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
