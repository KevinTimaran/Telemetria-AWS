import mysql from "mysql2/promise";
import awsCaBundle from "aws-ssl-profiles";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";

const sm = new SecretsManagerClient({});
let poolPromise;

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS documentos (
     document_id   CHAR(36)      NOT NULL PRIMARY KEY,
     patient_id    VARCHAR(64)   NOT NULL,
     doc_type      ENUM('imagen_diagnostica','informe') NOT NULL,
     file_name     VARCHAR(255)  NOT NULL,
     s3_key        VARCHAR(1024) NOT NULL,
     content_type  VARCHAR(100),
     size_bytes    BIGINT,
     kms_key_arn   VARCHAR(255),
     version_id    VARCHAR(255),
     uploaded_at   DATETIME      NOT NULL,
     INDEX idx_patient (patient_id, uploaded_at)
   )`,
  `CREATE TABLE IF NOT EXISTS consentimientos (
     patient_id  VARCHAR(64) NOT NULL,
     doctor_id   VARCHAR(64) NOT NULL,
     created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
     PRIMARY KEY (patient_id, doctor_id)
   )`,
  `CREATE TABLE IF NOT EXISTS auditoria_accesos (
     id           BIGINT AUTO_INCREMENT PRIMARY KEY,
     document_id  CHAR(36),
     actor_sub    VARCHAR(64) NOT NULL,
     actor_role   VARCHAR(20) NOT NULL,
     accion       VARCHAR(40) NOT NULL,
     resultado    VARCHAR(20) NOT NULL,
     expires_in   INT,
     created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
     INDEX idx_doc (document_id)
   )`,
];

async function createPool() {
  const secret = await sm.send(new GetSecretValueCommand({ SecretId: process.env.DB_SECRET_ARN }));
  const { username, password } = JSON.parse(secret.SecretString);

  const pool = mysql.createPool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: username,
    password,
    database: process.env.DB_NAME,
    ssl: awsCaBundle, // TLS verificado con los certificados de RDS
    connectionLimit: 2,
    timezone: "Z",
  });

  for (const ddl of SCHEMA) await pool.query(ddl);
  return pool;
}

export async function getPool() {
  if (!poolPromise) {
    poolPromise = createPool().catch((err) => {
      poolPromise = undefined; // reintentar en la siguiente invocación (p. ej. secreto rotado)
      throw err;
    });
  }
  return poolPromise;
}

export async function query(sql, params = []) {
  const pool = await getPool();
  const [rows] = await pool.execute(sql, params);
  return rows;
}

export async function audit({ documentId = null, user, accion, resultado, expiresIn = null }) {
  try {
    await query(
      `INSERT INTO auditoria_accesos (document_id, actor_sub, actor_role, accion, resultado, expires_in)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [documentId, user.sub, user.role, accion, resultado, expiresIn]
    );
  } catch (err) {
    console.error("No se pudo registrar auditoría:", err);
  }
}
