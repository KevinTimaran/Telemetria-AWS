// Configuracion para desarrollo local. Terraform genera y publica su propia
// version de config.js con los IDs reales de Cognito al desplegar en AWS.
window.TELEMED_CONFIG = {
  mode: "local",
  region: "local",
  pools: {
    medico: { clientId: "local" },
    paciente: { clientId: "local" },
  },
};
