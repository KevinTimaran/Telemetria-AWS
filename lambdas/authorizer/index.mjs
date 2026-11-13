/**
 * Lambda Authorizer (tipo TOKEN) para API Gateway REST.
 *
 * 1. Verifica firma, expiración, issuer y audience del ID token contra
 *    AMBOS User Pools (médicos y pacientes).
 * 2. Lee los claims personalizados custom:role y custom:license.
 * 3. Comprueba que el rol sea coherente con el pool que emitió el token
 *    (un paciente no puede declararse médico) y que el médico tenga licencia.
 * 4. Devuelve una política IAM que SOLO permite los endpoints de ese rol.
 *    Esta es la "política IAM basada en el rol de Cognito".
 */
import { CognitoJwtVerifier } from "aws-jwt-verify";

const {
  MEDICOS_POOL_ID,
  MEDICOS_CLIENT_ID,
  PACIENTES_POOL_ID,
  PACIENTES_CLIENT_ID,
  LICENSE_REGEX = "^RM-[0-9]{4,10}$",
} = process.env;

const verifier = CognitoJwtVerifier.create([
  { userPoolId: MEDICOS_POOL_ID, tokenUse: "id", clientId: MEDICOS_CLIENT_ID },
  { userPoolId: PACIENTES_POOL_ID, tokenUse: "id", clientId: PACIENTES_CLIENT_ID },
]);

// Rol que DEBE tener un token según el pool que lo emitió.
const ROL_POR_POOL = {
  [MEDICOS_POOL_ID]: "medico",
  [PACIENTES_POOL_ID]: "paciente",
};

// Matriz de permisos: rol -> [método, ruta]. "*" = un segmento variable.
export const PERMISOS = {
  paciente: [
    ["GET", "/api/me"],
    ["POST", "/api/documents/upload-url"],
    ["GET", "/api/documents"],
    ["GET", "/api/documents/*/download-url"],
    ["POST", "/api/consents"],
  ],
  medico: [
    ["GET", "/api/me"],
    ["GET", "/api/medico/patients/*/documents"],
    ["GET", "/api/documents/*/download-url"],
  ],
};

const licenseRe = new RegExp(LICENSE_REGEX);

export const handler = async (event) => {
  const token = (event.authorizationToken || "").replace(/^Bearer\s+/i, "").trim();
  // arn:aws:execute-api:region:account:apiId/stage/METHOD/resource
  const [arnApi, stage] = event.methodArn.split("/");
  const base = `${arnApi}/${stage}`;

  let claims;
  try {
    claims = await verifier.verify(token);
  } catch (err) {
    console.warn("Token rechazado:", err.message);
    throw new Error("Unauthorized"); // => 401
  }

  const poolId = claims.iss.split("/").pop();
  const role = claims["custom:role"];
  const license = claims["custom:license"] || "";

  if (!role || role !== ROL_POR_POOL[poolId]) {
    console.warn(`Rol '${role}' no coincide con el pool ${poolId} (sub=${claims.sub})`);
    return policy(claims.sub, "Deny", [`${base}/*`]);
  }

  if (role === "medico" && !licenseRe.test(license)) {
    console.warn(`Médico sin licencia válida (sub=${claims.sub}, license='${license}')`);
    return policy(claims.sub, "Deny", [`${base}/*`]);
  }

  const resources = PERMISOS[role].map(([method, path]) => `${base}/${method}${path}`);
  console.log(JSON.stringify({ sub: claims.sub, role, allowed: resources.length }));

  return policy(claims.sub, "Allow", resources, {
    sub: claims.sub,
    role,
    license,
    email: claims.email || "",
  });
};

function policy(principalId, effect, resources, context) {
  return {
    principalId,
    policyDocument: {
      Version: "2012-10-17",
      Statement: [{ Action: "execute-api:Invoke", Effect: effect, Resource: resources }],
    },
    ...(context ? { context } : {}),
  };
}
