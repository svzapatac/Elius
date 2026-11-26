![](elius-logo.png){width=5cm}

# Diccionario de datos

Versión 0.1 · 26 de noviembre de 2026

Cada tabla con sus columnas: tipo, si admite nulos, valor por defecto, restricción de dominio, descripción y nivel de privacidad (Ley 1581). Todas las tablas de negocio tienen además `creado_en` y `actualizado_en`.

**Privacidad:** *Personal* = dato personal; *Sensible* = dato sensible del art. 5 de la Ley 1581; *Restringido* = solo con permiso especial.

**Tipo de tabla:** *entidad*, *transición* (resuelve un muchos a muchos y guarda datos propios) o *referencia* (catálogo global).

## Modelo general

### Esquema `platform` (18 tablas)

#### `platform.planes`

Planes de suscripción y sus límites. Tipo: **referencia**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `codigo` | text | no |  | UNIQUE | free, starter, pro, enterprise |  |
| `nombre` | text | no |  |  | Nombre comercial |  |
| `precio_mensual` | numeric(12,2) | no |  |  | Precio mensual |  |
| `moneda` | char(3) | no | 'USD' |  | Moneda ISO 4217 |  |
| `max_usuarios` | int | no |  |  | Usuarios permitidos por tenant |  |
| `max_conversaciones_mes` | int | no |  |  | Conversaciones de Eli por mes |  |
| `max_tokens_mes` | bigint | no |  |  | Tokens de LLM por mes |  |
| `activo` | boolean | no | true |  | Disponible para nuevos tenants |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.tenants`

Cada negocio cliente de Elius. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `plan_id` | uuid | no |  | FK → `platform.planes` | Plan contratado |  |
| `slug` | text | no |  | UNIQUE | Identificador corto único |  |
| `nombre` | text | no |  |  | Nombre comercial |  |
| `vertical` | text | no | 'otro' | IN (veterinaria, restaurante, aerolinea, otro) | veterinaria, restaurante, aerolinea, otro |  |
| `estado` | text | no | 'prueba' | IN (prueba, activo, suspendido, cancelado) | prueba, activo, suspendido, cancelado |  |
| `fin_prueba` | date | sí |  |  | Último día del periodo de prueba |  |
| `razon_social` | text | sí |  |  | Nombre legal |  |
| `nit` | text | sí |  |  | Identificación tributaria |  |
| `pais` | char(2) | no | 'CO' |  | País ISO 3166 |  |
| `zona_horaria` | text | no | 'America/Bogota' |  | Ej. America/Bogota |  |
| `moneda` | char(3) | no | 'COP' |  | Moneda de operación |  |
| `eliminado_en` | timestamptz | sí |  |  | Borrado lógico |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.usuarios`

Usuarios de la plataforma. Tabla auth.users administrada por Supabase Auth. Tipo: **entidad** · tabla de Supabase Auth (`auth.users`).


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `email` | text | no |  | UNIQUE | Correo de acceso | Personal |
| `telefono` | text | sí |  |  | Teléfono E.164 | Personal |
| `nombre_completo` | text | no |  |  | Nombre para mostrar | Personal |
| `ultimo_ingreso` | timestamptz | sí |  |  | Último inicio de sesión |  |

#### `platform.roles`

Los 6 roles generales y fijos. Tipo: **referencia**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `codigo` | text | no |  | UNIQUE | super_admin, soporte, administrador, operador, analista, eli |  |
| `nombre` | text | no |  |  | Nombre visible |  |
| `nivel` | text | no |  | IN (plataforma, tenant) | plataforma o tenant |  |
| `descripcion` | text | no |  |  | Qué hace el rol |  |
| `orden` | int | no | 0 |  | Orden de presentación |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.plugins`

Catálogo de plugins (microkernel). Tipo: **referencia**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `codigo` | text | no |  | UNIQUE | vet, restaurant, airline |  |
| `nombre` | text | no |  |  | Nombre visible |  |
| `esquema` | text | no |  | UNIQUE | Esquema de la BD del plugin |  |
| `version` | text | no | '1.0.0' |  | Versión semántica |  |
| `verticales` | text[] | no | '{}' |  | Verticales a las que se instala por defecto |  |
| `manifiesto` | jsonb | no | '{}'::jsonb |  | Módulos, permisos y configuración que aporta |  |
| `activo` | boolean | no | true |  | Disponible para instalar |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.permisos`

Módulos y accesos que se pueden otorgar. Tipo: **referencia**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `plugin_id` | uuid | sí |  | FK → `platform.plugins` | Plugin que lo aporta; vacío = núcleo |  |
| `codigo` | text | no |  | UNIQUE | Ej. contactos, vet.historia_clinica |  |
| `modulo` | text | no |  |  | Módulo funcional |  |
| `descripcion` | text | no |  |  | Qué permite |  |
| `es_acceso_especial` | boolean | no | false |  | Se otorga por usuario con un interruptor |  |
| `protege_dato_sensible` | boolean | no | false |  | Da acceso a datos sensibles |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.rol_permisos`

Qué puede hacer cada rol en cada módulo. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `roles` y `permisos`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `rol_id` | uuid | no |  | FK → `platform.roles` | Rol |  |
| `permiso_id` | uuid | no |  | FK → `platform.permisos` | Permiso |  |
| `nivel` | text | no |  | IN (lectura, escritura, total, con_autorizacion) | lectura, escritura, total, con_autorizacion |  |
| `origen` | text | no | 'nucleo' |  | nucleo o código del plugin que lo asignó |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (rol_id, permiso_id)

#### `platform.membresias`

Usuario dentro de un tenant con su rol (tenantUser). Tipo: **transicion**.
 Resuelve el muchos a muchos entre `tenants` y `usuarios`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `usuario_id` | uuid | no |  | FK → `platform.usuarios` | Usuario |  |
| `rol_id` | uuid | no |  | FK → `platform.roles` | Rol general dentro del tenant |  |
| `estado` | text | no | 'activo' | IN (invitado, activo, inactivo) | invitado, activo, inactivo |  |
| `cargo` | text | sí |  |  | Etiqueta visible: Veterinario, Mesero… (no da permisos) |  |
| `es_predeterminada` | boolean | no | false |  | Tenant que se carga en el JWT al iniciar sesión |  |
| `invitado_por` | uuid | sí |  | FK → `platform.usuarios` | Quién lo invitó |  |
| `fecha_ingreso` | timestamptz | no | now() |  | Cuándo aceptó |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, usuario_id)

#### `platform.accesos_especiales`

Accesos especiales del plugin otorgados a un usuario (ej. historia clínica). Tipo: **transicion**.
 Resuelve el muchos a muchos entre `membresias` y `permisos`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `membresia_id` | uuid | no |  | FK → `platform.membresias` | Usuario en el tenant |  |
| `permiso_id` | uuid | no |  | FK → `platform.permisos` | Acceso especial |  |
| `otorgado_por` | uuid | no |  | FK → `platform.usuarios` | Administrador que lo activó |  |
| `motivo` | text | sí |  |  | Justificación |  |
| `vence_en` | timestamptz | sí |  |  | Vencimiento opcional |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (membresia_id, permiso_id)

#### `platform.asignaciones_plataforma`

Roles de plataforma del equipo Elius (Super Admin, Soporte). Tipo: **transicion**.
 Resuelve el muchos a muchos entre `usuarios` y `roles`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `usuario_id` | uuid | no |  | FK → `platform.usuarios` | Persona del equipo Elius |  |
| `rol_id` | uuid | no |  | FK → `platform.roles` | super_admin o soporte |  |
| `asignado_por` | uuid | no |  | FK → `platform.usuarios` | Quién lo asignó |  |
| `desde` | timestamptz | no | now() |  | Inicio |  |
| `hasta` | timestamptz | sí |  |  | Fin; vacío = vigente |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.tenant_plugins`

Plugins instalados en cada tenant. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `tenants` y `plugins`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `plugin_id` | uuid | no |  | FK → `platform.plugins` | Plugin |  |
| `habilitado` | boolean | no | true |  | Activo para el tenant |  |
| `configuracion` | jsonb | no | '{}'::jsonb |  | Configuración propia del tenant |  |
| `version_instalada` | text | no | '1.0.0' |  | Versión instalada |  |
| `instalado_por` | uuid | no |  | FK → `platform.usuarios` | Quién lo instaló |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, plugin_id)

#### `platform.accesos_soporte`

Autorización temporal del Administrador para que Soporte entre al tenant. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `tenants` y `usuarios`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `usuario_soporte_id` | uuid | no |  | FK → `platform.usuarios` | Persona de soporte |  |
| `autorizado_por` | uuid | no |  | FK → `platform.usuarios` | Administrador que autoriza |  |
| `motivo` | text | no |  |  | Para qué se necesita el acceso |  |
| `inicio` | timestamptz | no | now() |  | Desde cuándo |  |
| `vence_en` | timestamptz | no |  |  | Vence solo |  |
| `revocado_en` | timestamptz | sí |  |  | Revocación anticipada |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.invitaciones`

Invitaciones por correo a un tenant. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `rol_id` | uuid | no |  | FK → `platform.roles` | Rol que tendrá |  |
| `invitado_por` | uuid | no |  | FK → `platform.usuarios` | Quién invita |  |
| `email` | text | no |  |  | Correo invitado | Personal |
| `hash_token` | text | no |  | UNIQUE | Hash del token (nunca el token) |  |
| `vence_en` | timestamptz | no | now() + interval '7 days' |  | 7 días después de creada |  |
| `aceptada_en` | timestamptz | sí |  |  | Cuándo se aceptó |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.llaves_api`

Llaves de API por tenant (n8n, integraciones). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `creado_por` | uuid | no |  | FK → `platform.usuarios` | Quién la creó |  |
| `nombre` | text | no |  |  | Nombre descriptivo |  |
| `prefijo` | text | no |  |  | Primeros caracteres visibles |  |
| `hash_llave` | text | no |  | UNIQUE | Hash SHA-256 de la llave |  |
| `alcances` | text[] | no | '{}' |  | Permisos de la llave |  |
| `ultimo_uso` | timestamptz | sí |  |  | Último uso |  |
| `vence_en` | timestamptz | sí |  |  | Vencimiento |  |
| `revocada_en` | timestamptz | sí |  |  | Revocación |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `platform.consumos_periodo`

Consumo por mes para límites del plan y cobro. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `periodo` | date | no | date_trunc('month', now())::date |  | Primer día del mes |  |
| `metrica` | text | no |  |  | conversaciones, mensajes, tokens_llm, almacenamiento_mb |  |
| `valor` | bigint | no | 0 |  | Cantidad acumulada |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, periodo, metrica)

#### `platform.ajustes_globales`

Ajustes de toda la plataforma (tema ntfy, llaves VAPID públicas, URL y token del servicio de notificaciones). Sin acceso desde el panel. Tipo: **referencia**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `clave` | text | no | gen_random_uuid() | PK | Nombre del ajuste: ntfy_topic, vapid_public, push_service_url, push_service_token… |  |
| `valor` | text | no | 0 |  | Valor actual |  |
| `descripcion` | text | sí |  |  | Para qué sirve |  |

#### `platform.push_suscripciones`

Dispositivos de cada usuario suscritos a notificaciones push (Web Push): reciben el aviso de comprobante pendiente. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `usuario_id` | uuid | no |  | FK → `platform.usuarios` | Usuario dueño del dispositivo |  |
| `endpoint` | text | no |  | UNIQUE | Dirección única que entrega el navegador |  |
| `p256dh` | text | no |  |  | Llave pública del navegador (cifrado del mensaje) |  |
| `auth` | text | no |  |  | Secreto de autenticación del navegador |  |
| `dispositivo` | text | sí |  |  | Celular, computador… |  |
| `activo` | boolean | no | true |  | false cuando el servicio de push informa que el dispositivo ya no existe |  |
| `creado_en` | timestamptz | no | now() |  | Cuándo se activó |  |

#### `platform.accesos_bd`

Usuarios de base de datos con login (uno por rol) y la identidad de la aplicación que representan. Tipo: **referencia**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `usuario_bd` | text | no | gen_random_uuid() | PK | Nombre del usuario de PostgreSQL |  |
| `usuario_id` | uuid | no |  | FK → `platform.usuarios` | Usuario de la aplicación que representa |  |
| `descripcion` | text | no |  |  | Qué rol y negocio representa |  |
| `creado_en` | timestamptz | no | now() |  | Cuándo se creó |  |

### Esquema `audit` (1 tablas)

#### `audit.registros_auditoria`

Bitácora de cambios de todas las tablas. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | sí |  | FK → `platform.tenants` | Tenant afectado |  |
| `usuario_id` | uuid | sí |  | FK → `platform.usuarios` | Quién hizo el cambio |  |
| `rol` | text | no |  |  | Rol con el que actuó |  |
| `origen` | text | no | 'app' | IN (app, eli, soporte, sistema) | app, eli, soporte, sistema |  |
| `esquema` | text | no |  |  | Esquema de la tabla |  |
| `tabla` | text | no |  |  | Tabla afectada |  |
| `registro_id` | uuid | no |  |  | Fila afectada |  |
| `operacion` | text | no |  | IN (INSERT, UPDATE, DELETE) | INSERT, UPDATE, DELETE |  |
| `datos_anteriores` | jsonb | sí |  |  | Valores antes | Restringido |
| `datos_nuevos` | jsonb | sí |  |  | Valores después | Restringido |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |
| `usuario_email` | text | sí |  |  | Correo de quien hizo el cambio | Personal |
| `instancia` | text | sí |  |  | Servidor de base de datos desde el que se hizo |  |
| `base_datos` | text | sí |  |  | Base de datos usada |  |
| `puerto` | integer | sí |  |  | Puerto de la conexión |  |
| `ip_cliente` | text | sí |  |  | Dirección IP de quien se conectó | Personal |
| `login_bd` | text | sí |  |  | Usuario de base de datos con el que se conectó |  |
| `aplicacion` | text | sí |  |  | Programa que se conectó (panel, DBeaver, psql…) |  |

### Esquema `elius` (33 tablas)

#### `elius.contactos`

Cliente final: propietario, comensal, pasajero o comprador. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `tipo` | text | no | 'persona' | IN (persona, empresa) | persona o empresa |  |
| `nombres` | text | no |  |  | Nombres | Personal |
| `apellidos` | text | sí |  |  | Apellidos | Personal |
| `email` | text | sí |  |  | Correo | Personal |
| `telefono` | text | sí |  |  | Teléfono E.164 | Personal |
| `tipo_documento` | text | sí |  |  | CC, CE, PA, NIT… |  |
| `numero_documento` | text | sí |  |  | Número de documento | Restringido, Personal |
| `fecha_nacimiento` | date | sí |  |  | Fecha de nacimiento | Restringido, Personal |
| `etiquetas` | text[] | no | '{}' |  | Segmentación libre |  |
| `origen` | text | no | 'whatsapp' |  | whatsapp, web, presencial, chrome… |  |
| `eliminado_en` | timestamptz | sí |  |  | Borrado lógico |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, telefono); (tenant_id, email)

#### `elius.direcciones`

Direcciones de un contacto (domicilios). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `contacto_id` | uuid | no |  | FK → `elius.contactos` | Contacto |  |
| `etiqueta` | text | no |  |  | Casa, oficina… |  |
| `direccion` | text | no |  |  | Dirección | Personal |
| `ciudad` | text | no |  |  | Ciudad |  |
| `barrio` | text | sí |  |  | Barrio |  |
| `indicaciones` | text | sí |  |  | Cómo llegar | Personal |
| `latitud` | numeric(9,6) | sí |  |  | Ubicación compartida por WhatsApp | Personal |
| `longitud` | numeric(9,6) | sí |  |  | Ubicación compartida por WhatsApp | Personal |
| `es_principal` | boolean | no | false |  | Dirección por defecto |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.consentimientos`

Autorizaciones de tratamiento de datos (Ley 1581, art. 9). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `contacto_id` | uuid | no |  | FK → `elius.contactos` | Titular |  |
| `finalidad` | text | no |  |  | Para qué se autoriza |  |
| `canal` | text | no |  |  | Por dónde se obtuvo |  |
| `texto_aceptado` | text | no |  |  | Texto exacto que aceptó |  |
| `aceptado_en` | timestamptz | no | now() |  | Fecha de aceptación |  |
| `revocado_en` | timestamptz | sí |  |  | Fecha de revocación |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.agentes`

Configuración de Eli por tenant. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `nombre` | text | no | 'Eli' |  | Nombre del agente |  |
| `modelo_llm` | text | no |  |  | Modelo de lenguaje |  |
| `prompt_sistema` | text | no |  |  | Instrucciones base |  |
| `tono` | text | no | 'cercano' |  | Ej. empático, cercano, formal |  |
| `temperatura` | numeric(3,2) | no | 0.30 |  | Creatividad del modelo |  |
| `version` | int | no | 1 |  | Versión de la configuración |  |
| `activo` | boolean | no | true |  | En uso |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.canales`

Canales del tenant: número de WhatsApp, widget web, extensión. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `agente_id` | uuid | no |  | FK → `elius.agentes` | Agente que atiende el canal |  |
| `tipo` | text | no |  | IN (whatsapp, web, chrome, api) | whatsapp, web, chrome, api |  |
| `nombre` | text | no |  |  | Nombre visible |  |
| `identificador_externo` | text | no |  |  | Ej. phone_number_id de WhatsApp |  |
| `estado` | text | no | 'activo' | IN (activo, pausado, error) | activo, pausado, error |  |
| `referencia_secreto` | uuid | sí |  |  | Llave en Supabase Vault |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.identidades_contacto`

Cómo se identifica un contacto en cada canal. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `contactos` y `canales`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `contacto_id` | uuid | no |  | FK → `elius.contactos` | Contacto |  |
| `canal_id` | uuid | no |  | FK → `elius.canales` | Canal |  |
| `id_externo` | text | no |  |  | Ej. número de WhatsApp | Personal |
| `nombre_en_canal` | text | sí |  |  | Nombre que muestra el canal (perfil de WhatsApp) | Personal |
| `verificado` | boolean | no | false |  | Identidad confirmada |  |
| `primer_contacto_en` | timestamptz | no | now() |  | Primera vez por este canal |  |
| `ultimo_contacto_en` | timestamptz | no | now() |  | Última vez por este canal |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, canal_id, id_externo)

#### `elius.conversaciones`

Conversación de un contacto con Eli por un canal. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `identidad_id` | uuid | no |  | FK → `elius.identidades_contacto` | Contacto en el canal |  |
| `asignado_a` | uuid | sí |  | FK → `platform.membresias` | Humano que la atiende |  |
| `flujo` | text | no | 'general' |  | Flujo de Eli: ventas, reservas, menu_dia, carta… |  |
| `estado` | text | no | 'en_progreso' | IN (en_progreso, humano, pausa, cerrada) | en_progreso, humano, pausa, cerrada |  |
| `borrador` | jsonb | no | '{}'::jsonb |  | Pedido o reserva que Eli va armando antes de guardarlo |  |
| `bloqueada_en` | timestamptz | sí |  |  | Un proceso la está atendiendo (evita respuestas dobles) |  |
| `intencion` | text | sí |  |  | Intención detectada |  |
| `sentimiento` | text | sí |  | IN (positivo, neutro, negativo) | positivo, neutro, negativo |  |
| `resumen` | text | sí |  |  | Resumen generado por Eli |  |
| `iniciada_en` | timestamptz | no | now() |  | Inicio |  |
| `ultimo_mensaje_en` | timestamptz | no | now() |  | Último mensaje |  |
| `cerrada_en` | timestamptz | sí |  |  | Cierre |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.mensajes`

Mensajes de cada conversación. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `conversacion_id` | uuid | no |  | FK → `elius.conversaciones` | Conversación |  |
| `emisor` | text | no |  | IN (cliente, eli, humano, sistema) | cliente, eli, humano, sistema |  |
| `tipo_contenido` | text | no | 'texto' | IN (texto, imagen, audio, documento, ubicacion, plantilla) | texto, imagen, audio, documento, plantilla |  |
| `contenido` | text | no |  |  | Texto del mensaje | Personal |
| `url_adjunto` | text | sí |  |  | Archivo adjunto |  |
| `id_externo` | text | sí |  |  | Id del mensaje en WhatsApp |  |
| `estado_entrega` | text | no | 'recibido' | IN (recibido, enviado, entregado, leido, fallido) | recibido, enviado, entregado, leido, fallido |  |
| `procesado` | boolean | no | false |  | Eli ya lo procesó (agrupa mensajes seguidos) |  |
| `enviado_en` | timestamptz | no | now() |  | Hora del mensaje |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.consumos_llm`

Cada llamada a un modelo de lenguaje. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `conversacion_id` | uuid | no |  | FK → `elius.conversaciones` | Conversación |  |
| `mensaje_id` | uuid | sí |  | FK → `elius.mensajes` | Mensaje que la originó |  |
| `proveedor` | text | no |  |  | Proveedor del modelo |  |
| `modelo` | text | no |  |  | Modelo usado |  |
| `tokens_entrada` | int | no | 0 |  | Tokens enviados |  |
| `tokens_salida` | int | no | 0 |  | Tokens recibidos |  |
| `tokens_cache` | int | no | 0 |  | Tokens leídos de caché |  |
| `costo_usd` | numeric(12,6) | no | 0 |  | Costo estimado |  |
| `latencia_ms` | int | no | 0 |  | Tiempo de respuesta |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.categorias_catalogo`

Categorías del catálogo: secciones del menú, tipos de servicio…. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `nombre` | text | no |  |  | Nombre |  |
| `descripcion` | text | sí |  |  | Descripción |  |
| `orden` | int | no | 0 |  | Orden de presentación |  |
| `disponible_desde` | time | sí |  |  | Ej. desayunos desde 7:00 |  |
| `disponible_hasta` | time | sí |  |  | Ej. desayunos hasta 11:00 |  |
| `activa` | boolean | no | true |  | Visible |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.items_catalogo`

Todo lo que se vende: platos, productos, servicios, vacunas, tarifas aéreas. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `categoria_id` | uuid | no |  | FK → `elius.categorias_catalogo` | Categoría |  |
| `tipo` | text | no | 'producto' | IN (producto, servicio, paquete, adicional, tarifa) | producto, servicio, paquete, adicional, tarifa |  |
| `sku` | text | sí |  |  | Código interno |  |
| `nombre` | text | no |  |  | Nombre |  |
| `descripcion` | text | sí |  |  | Descripción |  |
| `incluye` | text | sí |  |  | Qué incluye un paquete |  |
| `precio` | numeric(14,2) | no | 0 |  | Precio base |  |
| `impuesto_pct` | numeric(5,2) | no | 0 |  | IVA o impoconsumo |  |
| `duracion_min` | int | sí |  |  | Duración, para servicios |  |
| `disponible` | boolean | no | true |  | false = agotado |  |
| `atributos` | jsonb | no | '{}'::jsonb |  | Datos propios de la vertical |  |
| `eliminado_en` | timestamptz | sí |  |  | Borrado lógico |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, sku)

#### `elius.recursos`

Lo que se reserva: mesas, consultorios, salas. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `tipo` | text | no | 'mesa' | IN (mesa, consultorio, sala, equipo, otro) | mesa, consultorio, sala, equipo |  |
| `nombre` | text | no |  |  | Ej. Mesa 12, Consultorio 2 |  |
| `capacidad` | int | no | 1 |  | Personas o cupos |  |
| `ubicacion` | text | sí |  |  | Zona: terraza, salón… |  |
| `activo` | boolean | no | true |  | Disponible |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.horarios_atencion`

Horario de atención del negocio o de un recurso. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `recurso_id` | uuid | sí |  | FK → `elius.recursos` | Vacío = horario general |  |
| `dia_semana` | smallint | no |  |  | 1 lunes … 7 domingo |  |
| `abre` | time | no |  |  | Hora de apertura |  |
| `cierra` | time | no |  |  | Hora de cierre |  |
| `vigente_desde` | date | no | current_date |  | Desde |  |
| `vigente_hasta` | date | sí |  |  | Hasta |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.reservas`

Citas, reservas de mesa y reservas aéreas. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `contacto_id` | uuid | no |  | FK → `elius.contactos` | Titular de la reserva |  |
| `conversacion_id` | uuid | sí |  | FK → `elius.conversaciones` | Conversación donde se creó |  |
| `codigo` | text | no |  |  | Código o localizador visible al cliente |  |
| `tipo` | text | no | 'cita' | IN (cita, mesa, vuelo, otro) | cita, mesa, vuelo |  |
| `estado` | text | no | 'pendiente_pago' | IN (pendiente_pago, confirmada, asistio, no_asistio, cancelada) | pendiente_pago, confirmada, asistio, no_asistio, cancelada |  |
| `inicio` | timestamptz | no |  |  | Inicio |  |
| `fin` | timestamptz | sí |  |  | Fin |  |
| `personas` | int | no | 1 |  | Número de personas |  |
| `responsable_id` | uuid | sí |  | FK → `platform.membresias` | Quién la está gestionando |  |
| `urgente` | boolean | no | false |  | Marcada como urgente |  |
| `visto` | boolean | no | false |  | Ya la vio el equipo |  |
| `llegada_en` | timestamptz | sí |  |  | Hora real de llegada |  |
| `salida_en` | timestamptz | sí |  |  | Hora real de salida |  |
| `novedades` | text | sí |  |  | Novedades de la visita |  |
| `notas` | text | sí |  |  | Observaciones |  |
| `creada_por_eli` | boolean | no | false |  | La creó el agente |  |
| `id_evento_calendario` | text | sí |  |  | Evento en Google Calendar |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |
| `eliminado_en` | timestamptz | sí |  |  | Baja lógica: el Administrador envía la reserva a la Papelera |  |
| `marcada_por` | uuid | sí |  |  | Quién marcó Llegó / No llegó (lo pone un trigger) |  |

Únicos: (tenant_id, codigo)

#### `elius.asignaciones_recurso`

Recursos ocupados por una reserva y en qué horario. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `reservas` y `recursos`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `reserva_id` | uuid | no |  | FK → `elius.reservas` | Reserva |  |
| `recurso_id` | uuid | no |  | FK → `elius.recursos` | Recurso |  |
| `inicio` | timestamptz | no |  |  | Desde |  |
| `fin` | timestamptz | no |  |  | Hasta |  |
| `estado` | text | no | 'activa' | IN (activa, liberada) | activa, liberada |  |
| `notas` | text | sí |  |  | Ej. mesas unidas para grupo |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.ordenes`

Ventas: pedidos, compras de productos, tiquetes. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `contacto_id` | uuid | sí |  | FK → `elius.contactos` | Cliente; vacío = venta de mostrador |  |
| `reserva_id` | uuid | sí |  | FK → `elius.reservas` | Reserva asociada |  |
| `conversacion_id` | uuid | sí |  | FK → `elius.conversaciones` | Conversación donde se tomó |  |
| `direccion_entrega_id` | uuid | sí |  | FK → `elius.direcciones` | Para domicilios |  |
| `numero` | bigint | no |  |  | Consecutivo por tenant |  |
| `canal_venta` | text | no | 'whatsapp' | IN (presencial, whatsapp, web, app) | presencial, whatsapp, web, app |  |
| `responsable_id` | uuid | sí |  | FK → `platform.membresias` | Quién la está gestionando |  |
| `tipo_entrega` | text | no | 'recoger' | IN (sitio, recoger, domicilio, no_aplica) | sitio, recoger, domicilio, no_aplica |  |
| `estado` | text | no | 'cotizando' | IN (cotizando, esperando_pago, confirmada, en_preparacion, en_camino, entregada, cancelada) | cotizando, esperando_pago, confirmada, en_preparacion, en_camino, entregada, cancelada |  |
| `urgente` | boolean | no | false |  | Marcada como urgente |  |
| `visto` | boolean | no | false |  | Ya la vio el equipo |  |
| `subtotal` | numeric(14,2) | no | 0 |  | Suma de líneas |  |
| `descuento` | numeric(14,2) | no | 0 |  | Descuentos |  |
| `impuestos` | numeric(14,2) | no | 0 |  | Impuestos |  |
| `total` | numeric(14,2) | no | 0 |  | Total calculado |  |
| `colocada_en` | timestamptz | no | now() |  | Hora del pedido |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |
| `eliminado_en` | timestamptz | sí |  |  | Baja lógica: el Administrador envía el pedido a la Papelera; solo el CIS adm lo borra de verdad |  |

Únicos: (tenant_id, numero)

#### `elius.orden_items`

Líneas de una orden: qué ítems del catálogo y cuánto. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `ordenes` y `items_catalogo`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `orden_id` | uuid | no |  | FK → `elius.ordenes` | Orden |  |
| `item_id` | uuid | no |  | FK → `elius.items_catalogo` | Ítem vendido |  |
| `cantidad` | numeric(10,2) | no | 1 |  | Cantidad |  |
| `precio_unitario` | numeric(14,2) | no |  |  | Precio al momento de la venta |  |
| `recargos` | numeric(14,2) | no | 0 |  | Recargos de opciones y adicionales (los suma el plugin) |  |
| `descuento` | numeric(14,2) | no | 0 |  | Descuento de la línea |  |
| `total_linea` | numeric(14,2) | no | 0 |  | Total de la línea |  |
| `notas` | text | sí |  |  | Ej. sin cebolla |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.pagos`

Pagos y reversos de una orden. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `orden_id` | uuid | no |  | FK → `elius.ordenes` | Orden |  |
| `pago_original_id` | uuid | sí |  | FK → `elius.pagos` | Si es reverso, el pago que reversa |  |
| `comprobante_id` | uuid | sí |  | FK → `elius.comprobantes_pago` | Comprobante que lo respalda |  |
| `metodo` | text | no |  | IN (efectivo, transferencia, nequi, daviplata, tarjeta, link) | efectivo, transferencia, nequi, daviplata, tarjeta, link |  |
| `monto` | numeric(14,2) | no |  |  | Monto (negativo en reversos) |  |
| `estado` | text | no | 'pendiente' | IN (pendiente, aprobado, rechazado) | pendiente, aprobado, rechazado |  |
| `pagado_en` | timestamptz | no | now() |  | Fecha del pago |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.comprobantes_pago`

Comprobantes de pago que el cliente envía por WhatsApp y Eli lee. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `orden_id` | uuid | sí |  | FK → `elius.ordenes` | Orden que paga, si ya se identificó |  |
| `conversacion_id` | uuid | no |  | FK → `elius.conversaciones` | Conversación donde llegó |  |
| `decidido_por` | uuid | sí |  | FK → `platform.membresias` | Quién aprobó o rechazó |  |
| `monto_leido` | numeric(14,2) | sí |  |  | Monto que Eli leyó en la imagen |  |
| `monto_esperado` | numeric(14,2) | sí |  |  | Monto que debía pagar |  |
| `coincide` | boolean | sí |  |  | El monto leído coincide con el esperado |  |
| `remitente` | text | sí |  |  | Quién envía el dinero | Personal |
| `destinatario` | text | sí |  |  | A quién llegó el dinero |  |
| `app_origen` | text | sí |  |  | Nequi, Daviplata, Bancolombia, Bre-B… |  |
| `referencia` | text | sí |  |  | Número de la transacción |  |
| `fecha_texto` | text | sí |  |  | Fecha y hora como aparece en el comprobante |  |
| `hash_archivo` | text | sí |  |  | Huella del archivo para detectar repetidos |  |
| `url_archivo` | text | sí |  |  | Imagen en Supabase Storage |  |
| `media_id` | text | sí |  |  | Id del archivo en WhatsApp |  |
| `veredicto` | text | no | 'pendiente' | IN (pendiente, aprobado, rechazado) | pendiente, aprobado, rechazado |  |
| `motivo` | text | sí |  |  | Razón del veredicto o de la alerta |  |
| `decidido_en` | timestamptz | sí |  |  | Cuándo se decidió |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.entregas`

Domicilios: quién lleva la orden y cómo va. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `orden_id` | uuid | no |  | FK → `elius.ordenes` | Orden |  |
| `repartidor_id` | uuid | sí |  | FK → `platform.membresias` | Domiciliario |  |
| `estado` | text | no | 'pendiente' | IN (pendiente, en_camino, entregada, fallida) | pendiente, en_camino, entregada, fallida |  |
| `cobro_contra_entrega` | numeric(14,2) | no | 0 |  | Saldo que se cobra en efectivo al entregar |  |
| `tomada_en` | timestamptz | sí |  |  | Cuándo la tomó el domiciliario |  |
| `entregada_en` | timestamptz | sí |  |  | Cuándo se entregó |  |
| `notas` | text | sí |  |  | Novedades de la entrega |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.item_adicionales`

Adicionales que se pueden sumar a cada producto o paquete. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `items_catalogo` y `items_catalogo`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `item_id` | uuid | no |  | FK → `elius.items_catalogo` | Producto o paquete principal |  |
| `adicional_id` | uuid | no |  | FK → `elius.items_catalogo` | Ítem adicional (tipo adicional) |  |
| `precio_especial` | numeric(14,2) | sí |  |  | Precio del adicional con este producto |  |
| `cantidad_maxima` | int | sí |  |  | Máximo que se puede agregar |  |
| `orden` | int | no | 0 |  | Orden de presentación |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (item_id, adicional_id)

#### `elius.medios_item`

Fotos y videos de cada ítem que Eli envía al cliente. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `item_id` | uuid | no |  | FK → `elius.items_catalogo` | Ítem |  |
| `tipo_archivo` | text | no | 'foto' | IN (foto, video) | foto, video |  |
| `url` | text | no |  |  | Archivo |  |
| `descripcion` | text | sí |  |  | Texto que acompaña el envío |  |
| `orden` | int | no | 0 |  | Orden de envío |  |
| `activo` | boolean | no | true |  | Se envía |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.escalamientos`

Casos que Eli pasa a una persona (pendientes). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `conversacion_id` | uuid | no |  | FK → `elius.conversaciones` | Conversación |  |
| `asignado_a` | uuid | sí |  | FK → `platform.membresias` | Operador asignado por turnos |  |
| `resuelto_por` | uuid | sí |  | FK → `platform.membresias` | Quién lo resolvió |  |
| `motivo` | text | no |  |  | Por qué Eli lo escaló |  |
| `mensaje_cliente` | text | sí |  |  | Mensaje que lo disparó | Personal |
| `resumen` | text | sí |  |  | Resumen de Eli para el humano |  |
| `resuelto_en` | timestamptz | sí |  |  | Cuándo se resolvió |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.eventos_embudo`

Fases por las que pasa cada conversación (métricas de conversión). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `conversacion_id` | uuid | no |  | FK → `elius.conversaciones` | Conversación |  |
| `fase` | text | no |  |  | mensaje_recibido, cotizo, pedido_guardado, pago_enviado, escalado… |  |
| `detalle` | jsonb | no | '{}'::jsonb |  | Datos de la fase |  |
| `ocurrido_en` | timestamptz | no | now() |  | Cuándo |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.errores_agente`

Errores de Eli o de los flujos de n8n, para Soporte. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `conversacion_id` | uuid | sí |  | FK → `elius.conversaciones` | Conversación afectada |  |
| `resuelto_por` | uuid | sí |  | FK → `platform.usuarios` | Quién lo resolvió (Soporte) |  |
| `origen` | text | no |  |  | Nodo o paso donde ocurrió |  |
| `mensaje` | text | no |  |  | Mensaje de error |  |
| `detalle` | jsonb | no | '{}'::jsonb |  | Datos técnicos |  |
| `resuelto_en` | timestamptz | sí |  |  | Cuándo se resolvió |  |
| `notas` | text | sí |  |  | Notas de Soporte |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.parametros_negocio`

Reglas configurables del negocio (umbral de grupo, tolerancia, cuentas de pago…). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `clave` | text | no |  |  | Ej. umbral_grupo_grande, tolerancia_minutos_llegada |  |
| `valor` | text | no | 0 |  | Valor actual |  |
| `tipo_dato` | text | no | 'texto' | IN (numero, texto, booleano, porcentaje) | numero, texto, booleano, porcentaje |  |
| `descripcion` | text | no |  |  | Qué controla, en palabras del dueño |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, clave)

#### `elius.suscripciones_push`

Dispositivos que reciben notificaciones push. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `membresia_id` | uuid | no |  | FK → `platform.membresias` | Usuario que las recibe |  |
| `endpoint` | text | no |  | UNIQUE | Endpoint del navegador |  |
| `p256dh` | text | no |  |  | Llave pública del navegador |  |
| `auth` | text | no |  |  | Secreto de autenticación del navegador |  |
| `dispositivo` | text | sí |  |  | Celular, computador… |  |
| `activa` | boolean | no | true |  | Recibe notificaciones |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.documentos_conocimiento`

Documentos que Eli usa para responder (RAG). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `titulo` | text | no |  |  | Título |  |
| `tipo_fuente` | text | no |  | IN (archivo, url, faq, manual) | archivo, url, faq, manual |  |
| `url_fuente` | text | sí |  |  | Origen |  |
| `ruta_archivo` | text | sí |  |  | Ruta en Supabase Storage |  |
| `estado` | text | no | 'procesando' | IN (procesando, listo, error) | procesando, listo, error |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.fragmentos_conocimiento`

Fragmentos de los documentos con su embedding. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `documento_id` | uuid | no |  | FK → `elius.documentos_conocimiento` | Documento |  |
| `orden` | int | no | 0 |  | Posición en el documento |  |
| `contenido` | text | no |  |  | Texto del fragmento |  |
| `tokens` | int | no |  |  | Tamaño en tokens |  |
| `embedding` | vector(1536) | no |  |  | Vector para búsqueda semántica |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.eventos_salida`

Eventos para n8n: reserva creada, vuelo cancelado…. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `tipo_evento` | text | no |  |  | Ej. reserva.creada |  |
| `entidad` | text | no |  |  | Tabla de origen |  |
| `entidad_id` | uuid | no |  |  | Fila de origen |  |
| `carga` | jsonb | no | '{}'::jsonb |  | Datos del evento |  |
| `estado` | text | no | 'pendiente' | IN (pendiente, enviado, fallido) | pendiente, enviado, fallido |  |
| `intentos` | int | no | 0 |  | Reintentos |  |
| `procesado_en` | timestamptz | sí |  |  | Cuándo se envió |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.tickets`

Tickets de soporte: lo que el Administrador, el Operador o Soporte reportan, con categoría, prioridad y solución. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Negocio dueño del ticket |  |
| `numero` | int | no |  |  | Consecutivo por negocio |  |
| `codigo` | text | no |  |  | Código visible, TCK-0001 |  |
| `categoria` | text | no |  |  | 01 General · 02 Reservas · 03 Pedidos · 04 Pagos · 05 Contabilidad · 06 Usuarios · 07 Integraciones |  |
| `prioridad` | text | no |  |  | baja, media, alta, critica |  |
| `estado` | text | no |  |  | abierto, en_proceso, resuelto |  |
| `asunto` | text | no |  |  | Resumen (mínimo 5 caracteres) |  |
| `descripcion` | text | no |  |  | Detalle del problema |  |
| `origen` | text | no |  |  | panel, reporte, soporte, demo |  |
| `creado_por` | uuid | sí |  | FK → `platform.usuarios` | Quién lo creó |  |
| `creado_por_rol` | text | sí |  |  | Rol con el que lo creó |  |
| `contacto_id` | uuid | sí |  | FK → `elius.contactos` | Cliente al que se refiere (opcional) |  |
| `asignado_a` | uuid | sí |  | FK → `platform.usuarios` | Quién de Soporte lo atiende |  |
| `resuelto_por` | uuid | sí |  | FK → `platform.usuarios` | Quién lo resolvió |  |
| `solucion` | text | sí |  |  | Qué se hizo (obligatoria al resolver) |  |
| `resuelto_en` | timestamptz | sí |  |  | Cuándo se resolvió |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, numero)

#### `elius.ticket_notas`

Cronología de un ticket: notas, cambios de estado, solución y datos corregidos. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Negocio dueño |  |
| `ticket_id` | uuid | no |  | FK → `elius.tickets` | Ticket al que pertenece |  |
| `autor_id` | uuid | sí |  | FK → `platform.usuarios` | Quién escribió |  |
| `autor_rol` | text | no |  |  | Rol de quien escribió |  |
| `tipo` | text | no |  |  | nota, estado, solucion, dato_corregido, usuario |  |
| `texto` | text | no |  |  | Contenido |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `elius.manual_soporte`

Manual de Soporte: pasos para resolver cada categoría de ticket (igual para todos los negocios). Tipo: **referencia**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `categoria` | text | no |  |  | 01 a 07, igual que los tickets |  |
| `titulo` | text | no |  |  | Título del procedimiento |  |
| `pasos` | text | no |  |  | Pasos a seguir |  |
| `orden` | int | no | 0 |  | Orden dentro de la categoría |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

### Esquema `ext` (6 tablas)

#### `ext.instalaciones_extension`

Extensión instalada por un usuario del tenant. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `membresia_id` | uuid | no |  | FK → `platform.membresias` | Usuario en el tenant |  |
| `navegador` | text | no |  |  | Chrome, Edge… |  |
| `version_extension` | text | no |  |  | Versión |  |
| `ultimo_uso_en` | timestamptz | sí |  |  | Última actividad |  |
| `activa` | boolean | no | true |  | En uso |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `ext.sitios_autorizados`

Sitios donde el tenant permite capturar (RN-E03). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `autorizado_por` | uuid | no |  | FK → `platform.usuarios` | Administrador |  |
| `dominio` | text | no |  |  | Ej. web.whatsapp.com |  |
| `nombre` | text | no |  |  | Nombre visible |  |
| `activo` | boolean | no | true |  | Vigente |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, dominio)

#### `ext.conversaciones_capturadas`

Conversaciones capturadas desde el navegador. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `instalacion_id` | uuid | no |  | FK → `ext.instalaciones_extension` | Quién la capturó |  |
| `sitio_id` | uuid | no |  | FK → `ext.sitios_autorizados` | Dónde |  |
| `contacto_id` | uuid | sí |  | FK → `elius.contactos` | Contacto reconocido |  |
| `id_hilo_externo` | text | no |  |  | Id del chat en el sitio |  |
| `titulo` | text | sí |  |  | Título del hilo |  |
| `capturada_en` | timestamptz | no | now() |  | Fecha de captura |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `ext.mensajes_capturados`

Mensajes de una conversación capturada. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `conversacion_id` | uuid | no |  | FK → `ext.conversaciones_capturadas` | Conversación |  |
| `autor_rol` | text | no | 'desconocido' | IN (cliente, agente, desconocido) | cliente, agente, desconocido |  |
| `autor_nombre` | text | sí |  |  | Nombre del autor | Personal |
| `contenido` | text | no |  |  | Texto | Personal |
| `enviado_en` | timestamptz | no | now() |  | Hora del mensaje |  |
| `embedding` | vector(1536) | sí |  |  | Vector para detectar patrones |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `ext.patrones`

Patrones detectados: preguntas frecuentes, objeciones, intenciones. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `aprobado_por` | uuid | sí |  | FK → `platform.membresias` | Quién lo aprobó |  |
| `tipo` | text | no |  | IN (faq, objecion, intencion, plantilla) | faq, objecion, intencion, plantilla |  |
| `nombre` | text | no |  |  | Nombre |  |
| `descripcion` | text | no |  |  | Descripción |  |
| `respuesta_sugerida` | text | sí |  |  | Respuesta para Eli |  |
| `frecuencia` | int | no | 0 |  | Veces observado |  |
| `confianza` | numeric(4,3) | no | 0 |  | 0 a 1 |  |
| `estado` | text | no | 'sugerido' | IN (sugerido, aprobado, rechazado) | sugerido, aprobado, rechazado |  |
| `embedding` | vector(1536) | sí |  |  | Vector del patrón |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `ext.evidencias_patron`

Mensajes que respaldan cada patrón. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `patrones` y `mensajes_capturados`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `patron_id` | uuid | no |  | FK → `ext.patrones` | Patrón |  |
| `mensaje_id` | uuid | no |  | FK → `ext.mensajes_capturados` | Mensaje |  |
| `relevancia` | numeric(4,3) | no |  |  | Qué tanto lo respalda, 0 a 1 |  |
| `fragmento` | text | no |  |  | Parte del mensaje que lo evidencia |  |
| `detectado_en` | timestamptz | no | now() |  | Cuándo se asoció |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (patron_id, mensaje_id)

## Plugins

### Esquema `plugin_vet` (5 tablas)

#### `plugin_vet.mascotas`

Pacientes de la clínica. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `nombre` | text | no |  |  | Nombre |  |
| `especie` | text | no |  |  | perro, gato, ave, exótico, otro |  |
| `raza` | text | sí |  |  | Raza |  |
| `sexo` | text | no |  | IN (macho, hembra) | macho, hembra |  |
| `fecha_nacimiento` | date | sí |  |  | Nacimiento aproximado |  |
| `peso_kg` | numeric(6,2) | sí |  |  | Último peso |  |
| `microchip` | text | sí |  |  | Número de microchip |  |
| `esterilizada` | boolean | no | false |  | Esterilizada |  |
| `alergias` | text[] | no | '{}' |  | Alergias conocidas | Restringido |
| `fallecida_en` | date | sí |  |  | Fecha de fallecimiento |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_vet.propietarios_mascota`

Personas responsables de cada mascota. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `contactos` y `mascotas`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `contacto_id` | uuid | no |  | FK → `elius.contactos` | Propietario |  |
| `mascota_id` | uuid | no |  | FK → `plugin_vet.mascotas` | Mascota |  |
| `tipo` | text | no | 'principal' | IN (principal, secundario) | principal, secundario |  |
| `puede_autorizar` | boolean | no | false |  | Puede autorizar procedimientos |  |
| `desde` | date | no | current_date |  | Desde cuándo es responsable |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (mascota_id, contacto_id)

#### `plugin_vet.atenciones`

Atención de una mascota dentro de una cita. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `reservas` y `mascotas`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `reserva_id` | uuid | no |  | FK → `elius.reservas` | Cita |  |
| `mascota_id` | uuid | no |  | FK → `plugin_vet.mascotas` | Mascota atendida |  |
| `servicio_id` | uuid | no |  | FK → `elius.items_catalogo` | Servicio del catálogo |  |
| `profesional_id` | uuid | no |  | FK → `platform.membresias` | Veterinario que atiende |  |
| `motivo` | text | no |  |  | Motivo de consulta |  |
| `estado` | text | no | 'programada' | IN (programada, en_curso, finalizada, cancelada) | programada, en_curso, finalizada |  |
| `peso_kg` | numeric(6,2) | sí |  |  | Peso en la atención |  |
| `temperatura_c` | numeric(4,1) | sí |  |  | Temperatura | Restringido |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_vet.registros_clinicos`

Historia clínica: anotaciones de cada atención. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `atencion_id` | uuid | no |  | FK → `plugin_vet.atenciones` | Atención |  |
| `autor_id` | uuid | no |  | FK → `platform.membresias` | Veterinario |  |
| `corrige_a` | uuid | sí |  | FK → `plugin_vet.registros_clinicos` | Registro que corrige (RN-V04) |  |
| `tipo` | text | no |  | IN (anamnesis, examen, diagnostico, tratamiento, correccion) | anamnesis, examen, diagnostico, tratamiento, correccion |  |
| `contenido` | text | no |  |  | Texto clínico | Restringido |
| `registrado_en` | timestamptz | no | now() |  | Fecha del registro |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_vet.aplicaciones_vacuna`

Vacunas aplicadas a cada mascota. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `mascotas` y `items_catalogo`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `mascota_id` | uuid | no |  | FK → `plugin_vet.mascotas` | Mascota |  |
| `vacuna_id` | uuid | no |  | FK → `elius.items_catalogo` | Vacuna del catálogo |  |
| `atencion_id` | uuid | sí |  | FK → `plugin_vet.atenciones` | Atención en que se aplicó |  |
| `aplicada_por` | uuid | no |  | FK → `platform.membresias` | Quién la aplicó |  |
| `lote` | text | no |  |  | Lote del biológico |  |
| `aplicada_en` | date | no | current_date |  | Fecha de aplicación |  |
| `proxima_dosis_en` | date | sí |  |  | Próxima dosis (RN-V05) |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

### Esquema `plugin_restaurant` (12 tablas)

#### `plugin_restaurant.alergenos`

Alérgenos que el restaurante informa. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `nombre` | text | no |  |  | Ej. maní, gluten, lácteos |  |
| `descripcion` | text | sí |  |  | Descripción |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_restaurant.item_alergenos`

Alérgenos de cada plato. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `items_catalogo` y `alergenos`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `item_id` | uuid | no |  | FK → `elius.items_catalogo` | Plato |  |
| `alergeno_id` | uuid | no |  | FK → `plugin_restaurant.alergenos` | Alérgeno |  |
| `nivel` | text | no | 'contiene' | IN (contiene, trazas) | contiene, trazas |  |
| `nota` | text | sí |  |  | Aclaración |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (item_id, alergeno_id)

#### `plugin_restaurant.grupos_modificador`

Grupos de opciones: término de la carne, acompañante…. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `nombre` | text | no |  |  | Nombre |  |
| `descripcion` | text | sí |  |  | Descripción |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_restaurant.opciones_modificador`

Opciones de un grupo: término medio, papas…. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `grupo_id` | uuid | no |  | FK → `plugin_restaurant.grupos_modificador` | Grupo |  |
| `nombre` | text | no |  |  | Nombre |  |
| `precio_adicional` | numeric(14,2) | no | 0 |  | Recargo |  |
| `disponible` | boolean | no | true |  | false = agotado |  |
| `orden` | int | no | 0 |  | Orden de presentación |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_restaurant.item_grupos_modificador`

Qué grupos de opciones aplica cada plato. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `items_catalogo` y `grupos_modificador`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `item_id` | uuid | no |  | FK → `elius.items_catalogo` | Plato |  |
| `grupo_id` | uuid | no |  | FK → `plugin_restaurant.grupos_modificador` | Grupo |  |
| `minimo` | int | no | 0 |  | Mínimo de opciones (RN-R04) |  |
| `maximo` | int | no | 1 |  | Máximo de opciones (RN-R04) |  |
| `orden` | int | no | 0 |  | Orden en pantalla |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (item_id, grupo_id)

#### `plugin_restaurant.orden_item_opciones`

Opciones elegidas en cada línea del pedido. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `orden_items` y `opciones_modificador`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `orden_item_id` | uuid | no |  | FK → `elius.orden_items` | Línea del pedido |  |
| `opcion_id` | uuid | no |  | FK → `plugin_restaurant.opciones_modificador` | Opción |  |
| `cantidad` | int | no | 1 |  | Cantidad |  |
| `precio_aplicado` | numeric(14,2) | no | 0 |  | Recargo cobrado |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_restaurant.estaciones_cocina`

Estaciones de producción: parrilla, bar, fríos. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `nombre` | text | no |  |  | Nombre |  |
| `tiempo_objetivo_min` | int | no | 15 |  | Tiempo objetivo de preparación |  |
| `activa` | boolean | no | true |  | En uso |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_restaurant.comandas`

Envíos de un pedido a cocina, por estación y por ronda. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `orden_id` | uuid | no |  | FK → `elius.ordenes` | Pedido |  |
| `estacion_id` | uuid | no |  | FK → `plugin_restaurant.estaciones_cocina` | Estación |  |
| `ronda` | int | no | 1 |  | 1, 2, 3… en la misma mesa |  |
| `estado` | text | no | 'recibida' | IN (recibida, en_preparacion, lista, entregada) | recibida, en_preparacion, lista, entregada |  |
| `enviada_en` | timestamptz | no |  |  | Cuándo se envió |  |
| `lista_en` | timestamptz | sí |  |  | Cuándo quedó lista |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_restaurant.comanda_items`

Qué líneas del pedido van en cada comanda. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `comandas` y `orden_items`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `comanda_id` | uuid | no |  | FK → `plugin_restaurant.comandas` | Comanda |  |
| `orden_item_id` | uuid | no |  | FK → `elius.orden_items` | Línea del pedido |  |
| `cantidad` | numeric(10,2) | no | 1 |  | Cantidad enviada en esta comanda |  |
| `estado` | text | no | 'pendiente' | IN (pendiente, preparando, listo) | pendiente, preparando, listo |  |
| `nota_cocina` | text | sí |  |  | Indicación para cocina |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_restaurant.menus_dia`

Menú del día: uno por fecha, confirmado por el dueño. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `confirmado_por` | uuid | sí |  | FK → `platform.membresias` | Quién lo confirmó |  |
| `fecha` | date | no |  |  | Día del menú |  |
| `precio_base` | numeric(14,2) | no |  |  | Precio del menú |  |
| `url_foto` | text | sí |  |  | Foto del menú que Eli envía |  |
| `confirmado_en` | timestamptz | sí |  |  | Eli solo lo ofrece si está confirmado |  |
| `activo` | boolean | no | true |  | Disponible ese día |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, fecha)

#### `plugin_restaurant.menu_dia_items`

Platos que componen el menú de cada día. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `menus_dia` y `items_catalogo`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `menu_id` | uuid | no |  | FK → `plugin_restaurant.menus_dia` | Menú del día |  |
| `item_id` | uuid | no |  | FK → `elius.items_catalogo` | Plato |  |
| `seccion` | text | no | 'principal' | IN (entrada, principal, bebida, postre) | entrada, principal, bebida, postre |  |
| `posicion` | int | no | 0 |  | Posición en la sección (Eli lee en este orden) |  |
| `disponible` | boolean | no | true |  | false = se acabó hoy |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (menu_id, item_id)

#### `plugin_restaurant.celebraciones`

Celebraciones dentro de una reserva (cumpleaños, aniversarios). Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `reserva_id` | uuid | no |  | FK → `elius.reservas` | Reserva |  |
| `tipo_celebracion` | text | no |  |  | cumpleaños, aniversario, grado… |  |
| `festejado` | text | no |  |  | Nombre del festejado | Personal |
| `decoracion` | text | sí |  |  | Decoración solicitada |  |
| `notas` | text | sí |  |  | Indicaciones |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

### Esquema `plugin_airline` (9 tablas)

#### `plugin_airline.aeropuertos`

Aeropuertos con código IATA, comunes a todos los tenants. Tipo: **referencia**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `codigo_iata` | char(3) | no |  | UNIQUE | Ej. BOG |  |
| `nombre` | text | no |  |  | Nombre |  |
| `ciudad` | text | no |  |  | Ciudad |  |
| `pais` | char(2) | no |  |  | País ISO 3166 |  |
| `zona_horaria` | text | no |  |  | Zona horaria |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_airline.aeronaves`

Flota de la aerolínea. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `matricula` | text | no |  |  | Matrícula |  |
| `modelo` | text | no |  |  | Ej. A320 |  |
| `capacidad` | int | no |  |  | Sillas totales (RN-A04) |  |
| `mapa_sillas` | jsonb | no | '{}'::jsonb |  | Distribución de sillas |  |
| `activa` | boolean | no | true |  | En servicio |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, matricula)

#### `plugin_airline.rutas`

Rutas entre dos aeropuertos. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `aeropuertos` y `aeropuertos`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `origen_id` | uuid | no |  | FK → `plugin_airline.aeropuertos` | Aeropuerto de origen |  |
| `destino_id` | uuid | no |  | FK → `plugin_airline.aeropuertos` | Aeropuerto de destino (RN-A02) |  |
| `distancia_km` | int | no |  |  | Distancia |  |
| `duracion_min` | int | no |  |  | Duración estimada |  |
| `activa` | boolean | no | true |  | En operación |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (tenant_id, origen_id, destino_id)

#### `plugin_airline.vuelos`

Vuelos programados. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `ruta_id` | uuid | no |  | FK → `plugin_airline.rutas` | Ruta |  |
| `aeronave_id` | uuid | no |  | FK → `plugin_airline.aeronaves` | Aeronave |  |
| `numero_vuelo` | text | no |  |  | Ej. EL123 |  |
| `salida_programada` | timestamptz | no |  |  | Salida |  |
| `llegada_programada` | timestamptz | no |  |  | Llegada (RN-A03) |  |
| `estado` | text | no | 'programado' | IN (programado, abordando, salio, llego, retrasado, cancelado) | programado, abordando, salio, llego, retrasado, cancelado |  |
| `puerta` | text | sí |  |  | Puerta |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_airline.tarifas_vuelo`

Precio y cupos de cada tarifa del catálogo en cada vuelo. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `vuelos` y `items_catalogo`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `vuelo_id` | uuid | no |  | FK → `plugin_airline.vuelos` | Vuelo |  |
| `tarifa_id` | uuid | no |  | FK → `elius.items_catalogo` | Tarifa (ítem del catálogo) |  |
| `precio` | numeric(14,2) | no | 0 |  | Precio en este vuelo |  |
| `cupos_totales` | int | no |  |  | Cupos asignados |  |
| `cupos_vendidos` | int | no | 0 |  | Cupos vendidos |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (vuelo_id, tarifa_id)

#### `plugin_airline.reserva_pasajeros`

Pasajeros de cada reserva aérea. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `reservas` y `contactos`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `reserva_id` | uuid | no |  | FK → `elius.reservas` | Reserva |  |
| `contacto_id` | uuid | no |  | FK → `elius.contactos` | Pasajero |  |
| `tipo_pasajero` | text | no | 'ADT' | IN (ADT, CHD, INF) | ADT adulto, CHD niño, INF infante (RN-A06) |  |
| `necesidades_especiales` | text | sí |  |  | Asistencia o condición de salud | Sensible |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (reserva_id, contacto_id)

#### `plugin_airline.tramos_reserva`

Vuelos que componen una reserva, en orden. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `reservas` y `tarifas_vuelo`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `reserva_id` | uuid | no |  | FK → `elius.reservas` | Reserva |  |
| `tarifa_vuelo_id` | uuid | no |  | FK → `plugin_airline.tarifas_vuelo` | Vuelo y tarifa |  |
| `orden_tramo` | int | no | 1 |  | 1 = ida, 2 = regreso… |  |
| `estado` | text | no | 'confirmado' | IN (confirmado, cambiado, cancelado) | confirmado, cambiado, cancelado |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

#### `plugin_airline.tiquetes`

Tiquete de un pasajero en un tramo. Tipo: **transicion**.
 Resuelve el muchos a muchos entre `reserva_pasajeros` y `tramos_reserva`.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `reserva_pasajero_id` | uuid | no |  | FK → `plugin_airline.reserva_pasajeros` | Pasajero |  |
| `tramo_id` | uuid | no |  | FK → `plugin_airline.tramos_reserva` | Tramo |  |
| `numero_tiquete` | text | no |  | UNIQUE | Número de tiquete |  |
| `silla` | text | sí |  |  | Silla asignada (RN-A07) |  |
| `estado` | text | no | 'emitido' | IN (emitido, usado, anulado) | emitido, usado, anulado |  |
| `checkin_en` | timestamptz | sí |  |  | Hora de check-in (RN-A08) |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

Únicos: (reserva_pasajero_id, tramo_id)

#### `plugin_airline.equipajes`

Equipaje registrado en un tiquete. Tipo: **entidad**.


| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |
| --- | --- | --- | --- | --- | --- | --- |
| `id` | uuid | no | gen_random_uuid() | PK | Identificador único |  |
| `tenant_id` | uuid | no | app.current_tenant_id() | FK → `platform.tenants` | Tenant dueño del registro |  |
| `tiquete_id` | uuid | no |  | FK → `plugin_airline.tiquetes` | Tiquete |  |
| `tipo` | text | no |  | IN (mano, bodega, especial) | mano, bodega, especial |  |
| `peso_kg` | numeric(5,2) | no |  |  | Peso |  |
| `etiqueta` | text | no |  |  | Número de etiqueta |  |
| `estado` | text | no | 'registrado' | IN (registrado, cargado, entregado, perdido) | registrado, cargado, entregado, perdido |  |
| `creado_en` | timestamptz | no | now() |  | Fecha de creación |  |
| `actualizado_en` | timestamptz | no | now() |  | Fecha de la última modificación |  |

