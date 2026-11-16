# Configuración manual de la plataforma de telemedicina en AWS

Documento cronológico de trabajo y guía de referencia para el proyecto. Se elaboró a partir de la guía original, las capturas compartidas, los valores comunicados durante la configuración y el diagnóstico posterior del frontend. Los nombres reales que se vieron en la cuenta se conservan tal como aparecen; algunos recursos usan `telemet` y el alias de KMS observado usa `telemed`.

> **Estado de la información:** una pantalla o un valor visible confirma lo que se observó en ese momento, no garantiza que siga configurado igual. Las acciones indicadas como **pendiente de verificar** provienen de la guía o del diseño y no cuentan con una confirmación completa en la conversación. No se debe interpretar la carga del frontend como prueba de que todo el flujo clínico funcione.

## 1. Objetivo y arquitectura

La plataforma permite autenticar pacientes y médicos con grupos separados de Cognito, servir una interfaz desde CloudFront, exponer una API REST protegida por un autorizador Lambda, almacenar documentos en S3 con SSE-KMS y registrar metadatos en MySQL de Amazon RDS. El acceso a archivos se hace mediante URLs prefirmadas.

```text
Navegador ── HTTPS ──> CloudFront ──> S3 frontend
                            └── /api/* ──> API Gateway ──> Lambda API
                                                          ├──> RDS MySQL
                                                          └──> S3 documentos + KMS
Navegador ──> Cognito (dos grupos de usuarios)
S3 documentos ── evento de creación ──> Lambda indexador ──> RDS
API Gateway ──> Lambda autorizador ──> validación de tokens Cognito
```

**Alcance:** el repositorio implementa autenticación y gestión de expedientes. No se ha identificado una implementación de videoconferencia; requiere trabajo adicional. Tampoco se ha demostrado todavía el flujo completo de inicio de sesión, carga, indexación y descarga con usuarios reales de prueba.

## 2. Inventario de valores utilizados

| Recurso o dato | Valor observado |
|---|---|
| Región | `us-east-1` (Norte de Virginia) |
| Cuenta AWS | `613591981090` |
| VPC | `Telemet-VPC`, `vpc-05d12b2e4b6032656` |
| Bucket documentos | `telemet-docs-613591981090-us-east-1` |
| Bucket frontend | `telemet-frontend-613591981090` |
| Clave KMS | `arn:aws:kms:us-east-1:613591981090:key/bf601c9e-e5c6-4e43-b426-5b0e970be322` |
| Alias KMS observado | `telemed-docs-key` |
| Grupo Cognito pacientes | `us-east-1_NU3NTGtKE` |
| Cliente Cognito pacientes | `2trkhk63fq6smr9cln916g90jf` |
| Grupo Cognito médicos | `us-east-1_4faUFaOiL` |
| Cliente Cognito médicos | `racpae3o98fpcoqjq0c0799e9` |
| Instancia de base de datos | `telemet-mysql` |
| Grupo de subredes RDS | `telemet-db-subnets` |
| Base de datos y usuario previstos | `telemet`, `telemet_admin`; verificar en RDS |
| Rol Lambda de documentos | `telemet-docs-lambda-role` |
| Política insertada | `telemet-docs-lambda-policy` |
| Funciones | `telemet-api`, `telemet-indexer`, `telemet-authorizer` |
| API REST | `telemet-api`, etapa `prod` |
| URL directa de API | `https://zi790mnx8j.execute-api.us-east-1.amazonaws.com/prod` |
| Distribución CloudFront | `telemet-frontend-cf` |
| Dominio CloudFront correcto | `djilt6to2ngep.cloudfront.net` |
| URL frontend | `https://djilt6to2ngep.cloudfront.net` |

Los identificadores de Cognito no son contraseñas. No incluyas en informes públicos contraseñas, tokens JWT, valores de secretos ni URLs prefirmadas activas. El correo del médico `dra.lopez@example.com` y el del paciente `juan.perez@example.com` aparecieron en formularios de creación; su existencia y estado actual deben verificarse en Cognito.

## 3. Preparar la red privada

La guía original planteó configurar primero la VPC. Las capturas posteriores muestran la VPC y dos subredes; no se dispone de evidencia completa de cada paso de creación. Si la infraestructura ya existe, inspeccionar antes de crear duplicados.

### 3.1 VPC y subredes

1. En la consola AWS, seleccionar **Estados Unidos (Norte de Virginia)**, `us-east-1`.
2. Ir a **VPC → Sus VPC** y revisar `Telemet-VPC` (`vpc-05d12b2e4b6032656`). La guía usa CIDR `10.20.0.0/16`; verificar el valor en la consola.
3. En las opciones de la VPC, comprobar que la resolución DNS y los nombres de host DNS estén habilitados.
4. En **Subredes**, identificar las dos subredes de la VPC:
   - `telemet-private-1`: `10.20.1.0/24`.
   - `telemet-private-2`: `10.20.2.0/24`.
5. Verificar que estén en dos zonas de disponibilidad distintas y que no asignen IPv4 públicas automáticamente. El nombre de la subred no demuestra por sí mismo que sea privada: revisar sus tablas de rutas.
6. En **Tablas de enrutamiento**, comprobar las asociaciones a ambas subredes y la ruta local de la VPC. La guía planteó una tabla privada sin salida directa a Internet.

### 3.2 Grupos de seguridad y endpoints

1. En **VPC → Grupos de seguridad**, revisar `telemet-lambda-sg`: las funciones necesitan salida hacia RDS y los servicios requeridos.
2. Revisar `telemet-rds-sg`: debe permitir **MySQL/Aurora TCP 3306** desde el grupo de seguridad de Lambda, no desde Internet.
3. La guía planteó un grupo para endpoints con entrada **HTTPS 443** desde el grupo de Lambda.
4. En **VPC → Endpoints**, verificar el endpoint **Gateway** de S3 asociado a la tabla de rutas y el endpoint **Interface** de Secrets Manager en las subredes privadas, con DNS privado y HTTPS permitido. **Pendiente de verificar:** las capturas no confirman su creación ni sus nombres definitivos. Las Lambdas en subredes privadas necesitan conectividad adecuada para acceder a los servicios.

## 4. Roles IAM y clave KMS

### 4.1 Rol de ejecución de documentos

1. Ir a **IAM → Roles → Crear rol**.
2. Seleccionar servicio de AWS y caso de uso **Lambda**.
3. Agregar `AWSLambdaVPCAccessExecutionRole` y crear el rol `telemet-docs-lambda-role`.
4. En **Relaciones de confianza**, comprobar el principal de servicio `lambda.amazonaws.com` con `sts:AssumeRole`. La captura mostró esta relación.
5. Más adelante, con S3, KMS y RDS creados, entrar en **Permisos → Agregar permisos → Crear política insertada** y crear `telemet-docs-lambda-policy`.
6. La pantalla de revisión mostró permisos limitados para S3, KMS y Secrets Manager. Revisar el JSON real antes de concluir que es correcto: S3 para `patients/*`, uso de la clave KMS concreta y lectura del secreto RDS concreto. La captura de resumen no muestra todas las acciones ni condiciones.

### 4.2 Rol del autorizador

La guía plantea un rol separado para `telemet-authorizer`, con permisos básicos de registros CloudWatch y sin permisos sobre documentos. **Pendiente de verificar:** nombre y política exactos del rol efectivamente asignado; revisar **Lambda → telemet-authorizer → Configuración → Permisos**.

### 4.3 Clave KMS administrada por el cliente

1. Ir a **KMS → Claves administradas por el cliente**.
2. Crear o revisar una clave simétrica de cifrado y descifrado.
3. En la captura se observó el alias `telemed-docs-key`, estado habilitado y el ARN indicado en el inventario.
4. En **Política de claves**, separar administración de uso criptográfico: conservar un administrador capaz de administrar la política y permitir el uso necesario al rol Lambda. Revisar el documento completo antes de modificarlo para evitar perder administración de la clave.
5. El requisito es demostrar que el rol de consola no puede descifrar y el rol Lambda sí puede usar la clave para los objetos correspondientes. **Pendiente:** verificar la política completa y realizar la prueba de denegación; la descripción de la clave por sí sola no demuestra los permisos.
6. Revisar la rotación automática si se requiere como evidencia; la guía proponía activarla, pero no se confirmó con una captura.

## 5. S3: documentos y frontend

### 5.1 Bucket de documentos

1. En **S3 → Buckets**, crear o abrir `telemet-docs-613591981090-us-east-1` en `us-east-1`.
2. Mantener bloqueado el acceso público y usar propiedad del bucket con ACL deshabilitadas.
3. En **Propiedades → Cifrado predeterminado**, verificar **SSE-KMS** con la clave administrada por el cliente cuyo ARN figura arriba. Revisar versionado y S3 Bucket Key según la configuración efectiva; no se confirmaron todos esos valores en las capturas.
4. En **Permisos → Política de bucket**, se observaron tres denegaciones: tráfico sin TLS, cifrado explícito distinto de `aws:kms` y clave KMS explícita distinta de la autorizada. La condición relativa a la clave debe coincidir con el identificador exacto que envía el cliente; ARN de clave, alias y ARN de alias son cadenas diferentes. No se confirmó la política final completa tras la corrección.
5. La política permite que una carga sin encabezados de cifrado explícitos use el cifrado predeterminado del bucket; por eso es indispensable verificar también dicho cifrado predeterminado.

### 5.2 CORS de documentos

1. Abrir el bucket de documentos → **Permisos → Uso compartido de recursos entre orígenes (CORS) → Editar**.
2. Configurar el origen real del frontend:

```json
[
  {
    "AllowedHeaders": ["*"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedOrigins": ["https://djilt6to2ngep.cloudfront.net"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 300
  }
]
```

3. Guardar. **Pendiente de verificar:** se guardó anteriormente un dominio mal transcrito; comprobar que fue reemplazado por `djilt6to2ngep` después de descubrir el error. CORS no sustituye autenticación ni permisos S3.

### 5.3 Bucket del frontend

1. Crear o abrir `telemet-frontend-613591981090` en S3.
2. Mantener el bloqueo de acceso público. La distribución CloudFront debe acceder mediante **Origin Access Control (OAC)**.
3. En **Objetos → Cargar → Agregar archivos**, cargar en la raíz `index.html`, `app.js`, `config.js` y `styles.css`. La pantalla mostró los cuatro objetos y una carga satisfactoria.
4. El frontend utiliza SSE-S3 en la configuración mostrada; la CMK de documentos es para el bucket de documentos, no para el frontend.
5. No es necesario habilitar alojamiento web estático para usar el origen S3 privado con OAC.

## 6. Cognito: pacientes y médicos

Se crearon dos grupos de usuarios independientes. El nombre visible de un grupo, el ID del grupo y el ID de cliente son valores distintos: el ID del grupo comienza con `us-east-1_`.

### 6.1 Grupo de pacientes

1. Ir a **Cognito → Grupos de usuarios → Crear grupo de usuarios** y completar el asistente para pacientes. La aplicación se llamó `telemet-pacientes`; el grupo apareció como `User pool - 1sm9gk`.
2. En el grupo, abrir **Registro → Agregar atributos personalizados**. AWS agrega el prefijo `custom:` automáticamente:
   - `role`: cadena.
   - `document_id`: cadena.
   - `eps`: cadena.
3. La guía de trabajo empleó longitudes `role` 1–20, `document_id` 5–20 y `eps` 1–60; verificar los límites efectivos en el esquema. Los atributos personalizados no pueden eliminarse ni renombrarse una vez creados.
4. En **Clientes de aplicación → telemet-pacientes**, anotar el ID del grupo y el ID del cliente de la sección 2. La captura mostró que el cliente no tenía secreto.
5. En **Permisos de atributos**, conservar lectura de los atributos necesarios y evitar que el cliente pueda escribir `custom:role` o `custom:document_id`. Se planteó permitir al usuario editar `custom:eps` y el nombre. Verificar los permisos guardados.

### 6.2 Grupo de médicos

1. Crear un segundo grupo independiente y su cliente `telemet-medicos`.
2. Agregar los atributos personalizados de tipo cadena `role`, `license` y `specialty`. La guía empleó límites 1–20, 4–30 y 1–60 respectivamente; verificar los valores efectivos.
3. Registrar los IDs mostrados en la sección 2.
4. En permisos del cliente, mantener lectura de los atributos necesarios y evitar que el usuario pueda escribir su rol o licencia. La guía planteó restringir también la escritura de `specialty`.

### 6.3 Configuración de clientes y usuarios

1. En cada cliente, revisar los flujos habilitados. En la captura de pacientes estaban seleccionados `ALLOW_USER_AUTH`, `ALLOW_USER_PASSWORD_AUTH`, `ALLOW_USER_SRP_AUTH` y `ALLOW_REFRESH_TOKEN_AUTH`. El frontend del repositorio utiliza `USER_PASSWORD_AUTH`.
2. Para pacientes se observó un token de actualización de 1 día y tokens de acceso e ID de 60 minutos. En médicos se observó inicialmente un token ID de 6 minutos y una duración de actualización inusual; se editó el formulario posteriormente. **Verificar los valores finales guardados.**
3. En **Administración de usuarios → Usuarios → Crear usuario**, crear usuarios de prueba en el grupo correspondiente. En el flujo se seleccionó contraseña temporal y se experimentó un error `InvalidParameterException` de `username`; se solucionó al volver a escribir el identificador. Se comunicó después que se habían creado médico y pacientes.
4. Editar los atributos de cada usuario desde su ficha: por ejemplo `custom:role=paciente` para pacientes y `custom:role=medico` con una licencia válida, como `RM-123456`, para el médico. **Verificar que estos valores hayan quedado guardados.** El usuario no debe poder asignarse su propio rol o licencia.
5. Si el usuario queda en `FORCE_CHANGE_PASSWORD`, deberá completar el cambio de contraseña por un flujo compatible; el frontend actual indica que no soporta retos de autenticación distintos de una respuesta completa.
6. Un aviso `SubscriptionRequiredException` de AWS End User Messaging SMS apareció en la consola. No demuestra por sí solo que falle la autenticación por correo; revisar SMS solo si ese canal se va a utilizar.

## 7. RDS MySQL

### 7.1 Grupo de subredes

1. En **RDS → Grupos de subredes → Crear grupo**, introducir nombre `telemet-db-subnets` y descripción, por ejemplo `Subredes privadas para MySQL`.
2. Seleccionar `Telemet-VPC`.
3. Seleccionar las dos zonas de disponibilidad que contienen `telemet-private-1` y `telemet-private-2`.
4. Agregar ambas subredes y pulsar **Crear**. La pantalla mostró la VPC con dos subredes en dos zonas.

### 7.2 Instancia y conectividad

1. En **RDS → Bases de datos → Crear base de datos**, elegir **MySQL Community**.
2. Se intentó `MySQL 8.0.46`; AWS rechazó la solicitud porque había finalizado su soporte estándar y requería soporte extendido. Después se creó la instancia; **verificar en RDS la versión final exacta** antes de documentarla como evidencia.
3. Identificador: `telemet-mysql`. Usuario maestro mostrado: `telemet_admin`. Se seleccionó administración de credenciales por **AWS Secrets Manager**, que puede generar cargos.
4. En capacidad se mostró `db.t3.micro`, almacenamiento `gp3` de `20 GiB`. La casilla de escalado automático apareció activada en una captura intermedia; verificar el ajuste final.
5. En **Conectividad**, seleccionar `Telemet-VPC`, `telemet-db-subnets`, **Acceso público: No**, grupo `telemet-rds-sg` y puerto `3306`. No conectar a una instancia EC2 desde el asistente.
6. En **Configuración adicional**, revisar el nombre inicial de base de datos `telemet`, cifrado, respaldos y protección contra eliminación según los requisitos. Los valores finales de todos estos campos no se mostraron.
7. Crear y esperar a que la instancia pase de **Creando** a **Disponible**. Una captura confirmó **Disponible**.
8. Copiar el endpoint y el ARN del secreto desde la consola para la configuración de Lambda. Nunca copiar el valor de la contraseña al informe. Una instancia privada exige conectividad de red y permisos apropiados.

## 8. Empaquetado de código y funciones Lambda

Los servicios se configuraron manualmente en AWS; para empaquetar el código se usó PowerShell en la computadora. Antes de ejecutar `Compress-Archive -Force`, confirmar el archivo destino, ya que puede sobrescribir un ZIP existente.

### 8.1 Crear ZIP de backend y autorizador

Desde la carpeta raíz del proyecto, con Node.js y npm instalados:

```powershell
Set-Location .\lambdas\backend
npm install --omit=dev
Compress-Archive -Path * -DestinationPath ..\..\telemet-backend.zip -Force
Set-Location ..\authorizer
npm install --omit=dev
Compress-Archive -Path * -DestinationPath ..\..\telemet-authorizer.zip -Force
```

La captura mostró instalación de dependencias y creación del ZIP de backend; posteriormente se indicó que ambos ZIP estaban listos. Los archivos de código deben quedar en la raíz del ZIP junto a `node_modules`, no dentro de una carpeta extra.

### 8.2 Lambda `telemet-api`

1. En **Lambda → Crear función → Crear desde cero**, indicar `telemet-api`.
2. En la configuración final observada, el runtime era **Node.js 22.x** y la arquitectura `x86_64`.
3. En **Rol de ejecución personalizado**, elegir `telemet-docs-lambda-role`.
4. Activar VPC y seleccionar `Telemet-VPC`, las dos subredes privadas y el grupo de seguridad de Lambda. Una captura mostró una VPC, dos subredes y un grupo.
5. Crear y esperar a que la función deje el estado `Pending/Creating`. Se intentó cargar el ZIP demasiado pronto y Lambda respondió que no podía actualizar mientras se creaba.
6. En **Código → Actualizar → Cargar archivo .zip**, seleccionar `telemet-backend.zip`. La vista mostró `api.mjs`, `config.mjs`, `db.mjs`, `indexer.mjs` y dependencias.
7. En **Configuración de la versión ejecutable → Editar**, configurar el controlador como `api.handler`. Verificar que el campo no contenga prefijos descriptivos.
8. En **Configuración → Configuración general**, se observaron `256 MB` de memoria y `15 s` de tiempo de espera.
9. En **Configuración → Variables de entorno**, configurar las claves que el código espera:

```text
DOCS_BUCKET=telemet-docs-613591981090-us-east-1
KMS_KEY_ARN=arn:aws:kms:us-east-1:613591981090:key/bf601c9e-e5c6-4e43-b426-5b0e970be322
DB_HOST=<endpoint copiado de RDS>
DB_PORT=3306
DB_NAME=telemet
DB_SECRET_ARN=<ARN completo del secreto de RDS>
```

10. Revisar especialmente que la clave se llame `DB_NAME`: una captura parecía mostrar `DB_NAM`. Confirmar que el nombre de base de datos exista y que el ARN esté completo. No guardar la contraseña en texto plano.

### 8.3 Lambda `telemet-indexer`

1. Crear o revisar `telemet-indexer` con el rol de documentos y acceso a la VPC y RDS.
2. Cargar `telemet-backend.zip` y configurar el controlador exacto `indexer.handler`.
3. Configurar las variables de entorno necesarias para RDS, el bucket y la clave, según el código.
4. Configurar y comprobar el desencadenador S3 para eventos de creación en el bucket de documentos y, si corresponde, el prefijo `patients/`. **Pendiente de verificar:** no hay captura que confirme el desencadenador final.

### 8.4 Lambda `telemet-authorizer`

1. Crear `telemet-authorizer` con **Node.js 22.x** y un rol de ejecución apropiado para registros.
2. Dejar la VPC desactivada si no necesita acceder a recursos privados; el código valida los tokens de Cognito.
3. Cargar `telemet-authorizer.zip`.
4. Configurar el controlador exacto `index.handler`.
5. En **Variables de entorno**, revisar:

```text
MEDICOS_POOL_ID=us-east-1_4faUFaOiL
MEDICOS_CLIENT_ID=racpae3o98fpcoqjq0c0799e9
PACIENTES_POOL_ID=us-east-1_NU3NTGtKE
PACIENTES_CLIENT_ID=2trkhk63fq6smr9cln916g90jf
LICENSE_REGEX=^RM-[0-9]{4,10}$
```

6. El autorizador comprueba el ID token, su emisor, firma, expiración y cliente; compara el rol con el grupo emisor y exige una licencia válida a los médicos.

## 9. API Gateway REST

### 9.1 API y autorizador

1. Crear una API REST regional llamada `telemet-api` en `us-east-1`.
2. Ir a **Autorizadores → Crear autorizador**.
3. Nombre: `CognitoRoleAuthorizer`; tipo **Lambda**; función `telemet-authorizer`.
4. Seleccionar carga de entrada **Token** y origen `Authorization`. La consola agrega el prefijo `method.request.header.` automáticamente.
5. La captura mostró almacenamiento en caché de autorización activado con TTL `300` segundos. La caché de autorización es independiente de la caché de respuestas de CloudFront; comprobar que las políticas generadas por el autorizador cubran correctamente las rutas permitidas durante ese TTL.
6. Crear y permitir que API Gateway invoque la función.

### 9.2 Recursos y métodos

En **Recursos**, crear la jerarquía y asociar cada método con integración de proxy Lambda hacia `telemet-api` y autorización `CognitoRoleAuthorizer`:

| Método | Ruta |
|---|---|
| GET | `/api/me` |
| POST | `/api/documents/upload-url` |
| GET | `/api/documents` |
| GET | `/api/documents/{documentId}/download-url` |
| POST | `/api/consents` |
| GET | `/api/medico/patients/{patientId}/documents` |

En la captura final del árbol se observaron los seis métodos. En la pantalla del método médico se vio integración de proxy y el autorizador; revisar individualmente los demás si se necesita evidencia de su configuración.

### 9.3 Implementar etapa

1. En **Recursos**, pulsar **Implementar API** en la parte superior derecha.
2. Crear o seleccionar la etapa `prod` y desplegar.
3. En **Etapas → prod**, copiar la URL de invocación:

```text
https://zi790mnx8j.execute-api.us-east-1.amazonaws.com/prod
```

4. La captura mostró la etapa `prod` con una implementación activa. La caché de etapa estaba desactivada. Después de modificar métodos o integraciones, desplegar de nuevo los cambios en la etapa.

## 10. CloudFront: frontend y API

### 10.1 Crear distribución y origen frontend

1. En **CloudFront → Distributions → Create distribution**, nombre `telemet-frontend-cf`.
2. Elegir una configuración de sitio único y dejar el dominio personalizado vacío si se usa el dominio predeterminado.
3. Seleccionar **Amazon S3** y el bucket `telemet-frontend-613591981090` como origen.
4. Mantener activada la opción de permitir acceso privado al bucket desde CloudFront mediante OAC. La revisión indicó que CloudFront podía actualizar la política del bucket. Verificar que la política permita a CloudFront acceder a ese origen restringido a la distribución.
5. Para el comportamiento estático, seleccionar redirección HTTP a HTTPS y métodos `GET, HEAD`.
6. Se seleccionó una política `telemet-static-1d`, prevista para un TTL de un día. **Verificar los TTL mínimos, predeterminados y máximos reales** y las cabeceras de caché de los objetos.
7. En seguridad se eligió no habilitar WAF durante el laboratorio; la pantalla mostraba una estimación de cargo si se habilitaba. La decisión debe revisarse para un entorno real.
8. Crear la distribución y esperar su despliegue. `Enabled` indica que está habilitada; por sí solo no es evidencia del estado exacto de propagación de un cambio.

### 10.2 Agregar origen de API y comportamiento

1. Abrir la distribución → **Origins → Create origin**.
2. En **Origin domain**, ingresar solo `zi790mnx8j.execute-api.us-east-1.amazonaws.com`.
3. Seleccionar **HTTPS only**, puerto `443`, TLS mínimo `TLSv1.2` y **Origin path** `/prod`.
4. Crear el origen.
5. En **Behaviors → Create behavior**, indicar el patrón `/api/*` y seleccionar el origen API Gateway.
6. Permitir los métodos necesarios, incluyendo `GET`, `POST` y `OPTIONS`; se eligió la opción que incluye también `HEAD`, `PUT`, `PATCH` y `DELETE`.
7. En política de caché seleccionar `CachingDisabled`.
8. En política de solicitudes al origen se indicó `AllViewerExceptHostHeader`, recomendada por la consola para API Gateway sin dominio personalizado; reenvía `Authorization`, pero también otros datos de la solicitud, de modo que no equivale a una lista mínima de solo tres encabezados. Confirmar su selección efectiva en el comportamiento.
9. Guardar y comprobar que las solicitudes de API llegan al stage correcto.

### 10.3 Restricción geográfica y objeto raíz

1. En la distribución, buscar **Security → Geographic restrictions**.
2. Configurar **Allow list** con **Colombia (CO)**. El diagnóstico posterior informó que la restricción estaba correcta; comprobar su estado actual antes de tomar evidencia.
3. En **General → Settings → Edit**, configurar **Default root object** como `index.html` y guardar. Este ajuste fue parte de la solución posterior: antes, `/index.html` respondía pero `/` devolvía 403.
4. La restricción de CloudFront no impide por sí sola el acceso a la URL directa de API Gateway; esa diferencia debe tenerse en cuenta si se necesita limitar geográficamente también la API.

## 11. Configuración y actualización del frontend

El archivo `config.js` publicado debe contener los valores de Cognito reales:

```javascript
window.TELEMED_CONFIG = {
  mode: "aws",
  region: "us-east-1",
  pools: {
    medico: {
      userPoolId: "us-east-1_4faUFaOiL",
      clientId: "racpae3o98fpcoqjq0c0799e9"
    },
    paciente: {
      userPoolId: "us-east-1_NU3NTGtKE",
      clientId: "2trkhk63fq6smr9cln916g90jf"
    }
  }
};
```

1. Editar y guardar el archivo local `frontend/config.js`.
2. Abrir el bucket **frontend**, no el de documentos.
3. Pulsar **Cargar → Agregar archivos**, seleccionar `config.js` y cargarlo en la raíz. Si el objeto ya existe, la carga reemplaza el objeto actual; con versionado pueden conservarse versiones anteriores.
4. En CloudFront → **Invalidations → Create invalidation**, introducir `/config.js` y crear la invalidación. Esperar a que termine antes de comprobar el contenido servido. **Pendiente de verificar:** no se mostró la confirmación final de la invalidación.
5. El frontend del repositorio usa rutas relativas `/api/*`; no requiere colocar la URL directa de la API en este `config.js`.

## 12. Incidente: el frontend no cargaba

El diagnóstico posterior comunicado identificó tres fallos diferentes:

1. **Dominio transcrito incorrectamente:** se usó `dljit6to2ngep.cloudfront.net`, pero el dominio real era `djilt6to2ngep.cloudfront.net`. El nombre incorrecto causó el error DNS. Durante la asistencia también se repitió el nombre incorrecto; no era correcto concluir que la única causa era la propagación.
2. **Objeto raíz sin configurar:** con el dominio correcto, `/` devolvía 403 mientras que `/index.html` respondía 200. Se configuró `index.html` como **Default root object**.
3. **Controladores Lambda con prefijo sobrante:** `telemet-authorizer` tenía `Handler:index.handler` y `telemet-indexer` `Handler:indexer.handler`. El campo debía contener solo `index.handler` e `indexer.handler`. En CloudWatch aparecía `Cannot find module 'Handler:index'` y un token inválido producía 500.

### Resultado de la corrección comunicado

- `/`, `/index.html`, `/config.js`, `/app.js` y `/styles.css` respondieron 200.
- El frontend mostró el inicio de sesión sin errores de consola.
- Una solicitud con token inválido respondió 401, tanto por CloudFront como por API Gateway directamente.
- No se probó el inicio de sesión de pacientes ni médicos por falta de credenciales durante ese diagnóstico. El 401 con token inválido no demuestra que funcionen los tokens válidos, la base de datos o las subidas.

## 13. Pruebas finales pendientes y evidencias

Usar datos ficticios, no expedientes médicos reales, mientras se valida el laboratorio.

1. **Cognito:** iniciar sesión como paciente y médico. Confirmar `sub`, `custom:role` y, para médico, `custom:license`; comprobar que cada rol solo accede a sus rutas autorizadas.
2. **API:** probar `/api/me`, listados y operaciones protegidas con tokens válidos, así como denegación de acceso con el rol incorrecto.
3. **CORS:** verificar el dominio corregido `https://djilt6to2ngep.cloudfront.net` en el bucket de documentos y comprobar la carga desde el navegador.
4. **Carga y cifrado:** subir un archivo ficticio mediante una URL prefirmada. En el objeto S3, comprobar SSE-KMS y el ARN de clave. Desde una identidad sin permiso KMS, intentar una descarga directa para demostrar la denegación, contrastándola con la URL autorizada.
5. **Indexación:** confirmar que el evento de S3 invoca `telemet-indexer`, revisar CloudWatch y comprobar los metadatos en RDS mediante una conexión autorizada. El código crea tablas durante la inicialización, pero aún debe verificarse que la conexión real funcione.
6. **Expiración:** verificar que las URLs de descarga sean de `300` segundos para imágenes diagnósticas y `3600` segundos para informes; las URLs de subida son de `300` segundos según el código. Las credenciales temporales pueden limitar la duración real.
7. **Propiedad y consentimiento:** confirmar que un paciente no obtiene URLs de documentos ajenos y que un médico solo accede cuando tiene consentimiento. El código verifica el `sub` del paciente y, en el caso médico, el consentimiento.
8. **CloudFront:** verificar los TTL, el reenvío de `Authorization`, el origen `/prod`, la restricción geográfica y el acceso privado OAC.
9. **Costos:** revisar RDS, Secrets Manager, KMS, endpoints de interfaz y CloudFront en la cuenta. No eliminar ni modificar recursos sin decidir antes si se deben conservar las evidencias y los datos.

### Lista de capturas sugeridas

- VPC, subredes, rutas, grupos de seguridad y endpoints.
- Política del rol Lambda y política de clave KMS, sin credenciales.
- Buckets, bloqueo de acceso público, cifrado y CORS.
- Dos grupos Cognito, atributos y permisos de cliente.
- RDS disponible, conectividad privada y grupo de subredes.
- Controladores, variables no sensibles y desencadenador S3 de Lambda.
- Recursos y métodos de API Gateway, autorizador y etapa `prod`.
- Distribución CloudFront, dominio correcto, objeto raíz, dos orígenes y comportamientos.
- Pruebas de login, carga, indexación, descarga, autorización denegada y expiración.

Las capturas deben ocultar contraseñas, tokens y URLs prefirmadas. No se incluyen capturas en este documento: las imágenes originales se compartieron en la conversación y deben seleccionarse o capturarse nuevamente para un informe ilustrado.
