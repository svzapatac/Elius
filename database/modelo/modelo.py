"""
Modelo entidad-relación de Elius — fuente única.

De aquí se generan: diagramas E/R, DBML (dbdiagram.io), validación de reglas
y, más adelante, el diccionario de datos y el SQL.

Reglas obligatorias del curso:
  R1. No hay relaciones 1-1.
  R2. No hay relaciones muchos a muchos directas: se resuelven con tablas de transición.
  R3. Toda tabla de transición tiene datos útiles además de sus llaves.

Convenciones de columnas: (nombre, tipo, banderas, descripción)
  banderas: pk · fk:<esquema.tabla> · null · uq · S (dato sensible, Ley 1581 art. 5)
            · P (dato personal) · R (acceso restringido)
"""

TABLAS = []          # lista de dicts
AUDITORIA = {"id", "tenant_id", "creado_en", "actualizado_en", "creado_por"}


def tabla(esquema, nombre, tipo, descripcion, columnas, unicos=(), tenant=True,
          resuelve=None, externa=False):
    """tipo: entidad | transicion | referencia."""
    cols = [("id", "uuid", "pk", "Identificador único")]
    if tenant:
        cols.append(("tenant_id", "uuid", "fk:platform.tenants", "Tenant dueño del registro"))
    cols += columnas
    if not externa:
        cols += [("creado_en", "timestamptz", "", "Fecha de creación"),
                 ("actualizado_en", "timestamptz", "", "Fecha de la última modificación")]
    TABLAS.append(dict(esquema=esquema, nombre=nombre, tipo=tipo, descripcion=descripcion,
                       columnas=cols, unicos=list(unicos), tenant=tenant,
                       resuelve=resuelve, externa=externa))


# =============================================================================
# PLATFORM — lógica del tenant (metadatos del SaaS)
# =============================================================================
P = "platform"

tabla(P, "planes", "referencia", "Planes de suscripción y sus límites", [
    ("codigo", "text", "uq", "free, starter, pro, enterprise"),
    ("nombre", "text", "", "Nombre comercial"),
    ("precio_mensual", "numeric(12,2)", "", "Precio mensual"),
    ("moneda", "char(3)", "", "Moneda ISO 4217"),
    ("max_usuarios", "int", "", "Usuarios permitidos por tenant"),
    ("max_conversaciones_mes", "int", "", "Conversaciones de Eli por mes"),
    ("max_tokens_mes", "bigint", "", "Tokens de LLM por mes"),
    ("activo", "boolean", "", "Disponible para nuevos tenants"),
], tenant=False)

tabla(P, "tenants", "entidad", "Cada negocio cliente de Elius", [
    ("plan_id", "uuid", "fk:platform.planes", "Plan contratado"),
    ("slug", "text", "uq", "Identificador corto único"),
    ("nombre", "text", "", "Nombre comercial"),
    ("vertical", "text", "", "veterinaria, restaurante, aerolinea, otro"),
    ("estado", "text", "", "prueba, activo, suspendido, cancelado"),
    ("fin_prueba", "date", "null", "Último día del periodo de prueba"),
    ("razon_social", "text", "null", "Nombre legal"),
    ("nit", "text", "null", "Identificación tributaria"),
    ("pais", "char(2)", "", "País ISO 3166"),
    ("zona_horaria", "text", "", "Ej. America/Bogota"),
    ("moneda", "char(3)", "", "Moneda de operación"),
    ("eliminado_en", "timestamptz", "null", "Borrado lógico"),
], tenant=False)

tabla(P, "usuarios", "entidad",
      "Usuarios de la plataforma. Tabla auth.users administrada por Supabase Auth", [
    ("email", "text", "uq P", "Correo de acceso"),
    ("telefono", "text", "null P", "Teléfono E.164"),
    ("nombre_completo", "text", "P", "Nombre para mostrar"),
    ("ultimo_ingreso", "timestamptz", "null", "Último inicio de sesión"),
], tenant=False, externa=True)

tabla(P, "roles", "referencia", "Los 6 roles generales y fijos", [
    ("codigo", "text", "uq", "super_admin, soporte, administrador, operador, analista, eli"),
    ("nombre", "text", "", "Nombre visible"),
    ("nivel", "text", "", "plataforma o tenant"),
    ("descripcion", "text", "", "Qué hace el rol"),
    ("orden", "int", "", "Orden de presentación"),
], tenant=False)

tabla(P, "plugins", "referencia", "Catálogo de plugins (microkernel)", [
    ("codigo", "text", "uq", "vet, restaurant, airline"),
    ("nombre", "text", "", "Nombre visible"),
    ("esquema", "text", "uq", "Esquema de la BD del plugin"),
    ("version", "text", "", "Versión semántica"),
    ("verticales", "text[]", "", "Verticales a las que se instala por defecto"),
    ("manifiesto", "jsonb", "", "Módulos, permisos y configuración que aporta"),
    ("activo", "boolean", "", "Disponible para instalar"),
], tenant=False)

tabla(P, "permisos", "referencia", "Módulos y accesos que se pueden otorgar", [
    ("plugin_id", "uuid", "fk:platform.plugins null", "Plugin que lo aporta; vacío = núcleo"),
    ("codigo", "text", "uq", "Ej. contactos, vet.historia_clinica"),
    ("modulo", "text", "", "Módulo funcional"),
    ("descripcion", "text", "", "Qué permite"),
    ("es_acceso_especial", "boolean", "", "Se otorga por usuario con un interruptor"),
    ("protege_dato_sensible", "boolean", "", "Da acceso a datos sensibles"),
], tenant=False)

tabla(P, "rol_permisos", "transicion", "Qué puede hacer cada rol en cada módulo", [
    ("rol_id", "uuid", "fk:platform.roles", "Rol"),
    ("permiso_id", "uuid", "fk:platform.permisos", "Permiso"),
    ("nivel", "text", "", "lectura, escritura, total, con_autorizacion"),
    ("origen", "text", "", "nucleo o código del plugin que lo asignó"),
], unicos=[("rol_id", "permiso_id")], tenant=False, resuelve=("roles", "permisos"))

tabla(P, "membresias", "transicion", "Usuario dentro de un tenant con su rol (tenantUser)", [
    ("usuario_id", "uuid", "fk:platform.usuarios", "Usuario"),
    ("rol_id", "uuid", "fk:platform.roles", "Rol general dentro del tenant"),
    ("estado", "text", "", "invitado, activo, inactivo"),
    ("cargo", "text", "null", "Etiqueta visible: Veterinario, Mesero… (no da permisos)"),
    ("es_predeterminada", "boolean", "", "Tenant que se carga en el JWT al iniciar sesión"),
    ("invitado_por", "uuid", "fk:platform.usuarios null", "Quién lo invitó"),
    ("fecha_ingreso", "timestamptz", "", "Cuándo aceptó"),
], unicos=[("tenant_id", "usuario_id")], resuelve=("tenants", "usuarios"))

tabla(P, "accesos_especiales", "transicion",
      "Accesos especiales del plugin otorgados a un usuario (ej. historia clínica)", [
    ("membresia_id", "uuid", "fk:platform.membresias", "Usuario en el tenant"),
    ("permiso_id", "uuid", "fk:platform.permisos", "Acceso especial"),
    ("otorgado_por", "uuid", "fk:platform.usuarios", "Administrador que lo activó"),
    ("motivo", "text", "null", "Justificación"),
    ("vence_en", "timestamptz", "null", "Vencimiento opcional"),
], unicos=[("membresia_id", "permiso_id")], resuelve=("membresias", "permisos"))

tabla(P, "asignaciones_plataforma", "transicion",
      "Roles de plataforma del equipo Elius (Super Admin, Soporte)", [
    ("usuario_id", "uuid", "fk:platform.usuarios", "Persona del equipo Elius"),
    ("rol_id", "uuid", "fk:platform.roles", "super_admin o soporte"),
    ("asignado_por", "uuid", "fk:platform.usuarios", "Quién lo asignó"),
    ("desde", "timestamptz", "", "Inicio"),
    ("hasta", "timestamptz", "null", "Fin; vacío = vigente"),
], tenant=False, resuelve=("usuarios", "roles"))

tabla(P, "tenant_plugins", "transicion", "Plugins instalados en cada tenant", [
    ("plugin_id", "uuid", "fk:platform.plugins", "Plugin"),
    ("habilitado", "boolean", "", "Activo para el tenant"),
    ("configuracion", "jsonb", "", "Configuración propia del tenant"),
    ("version_instalada", "text", "", "Versión instalada"),
    ("instalado_por", "uuid", "fk:platform.usuarios", "Quién lo instaló"),
], unicos=[("tenant_id", "plugin_id")], resuelve=("tenants", "plugins"))

tabla(P, "accesos_soporte", "transicion",
      "Autorización temporal del Administrador para que Soporte entre al tenant", [
    ("usuario_soporte_id", "uuid", "fk:platform.usuarios", "Persona de soporte"),
    ("autorizado_por", "uuid", "fk:platform.usuarios", "Administrador que autoriza"),
    ("motivo", "text", "", "Para qué se necesita el acceso"),
    ("inicio", "timestamptz", "", "Desde cuándo"),
    ("vence_en", "timestamptz", "", "Vence solo"),
    ("revocado_en", "timestamptz", "null", "Revocación anticipada"),
], resuelve=("tenants", "usuarios"))

tabla(P, "invitaciones", "entidad", "Invitaciones por correo a un tenant", [
    ("rol_id", "uuid", "fk:platform.roles", "Rol que tendrá"),
    ("invitado_por", "uuid", "fk:platform.usuarios", "Quién invita"),
    ("email", "text", "P", "Correo invitado"),
    ("hash_token", "text", "uq", "Hash del token (nunca el token)"),
    ("vence_en", "timestamptz", "", "7 días después de creada"),
    ("aceptada_en", "timestamptz", "null", "Cuándo se aceptó"),
])

tabla(P, "llaves_api", "entidad", "Llaves de API por tenant (n8n, integraciones)", [
    ("creado_por", "uuid", "fk:platform.usuarios", "Quién la creó"),
    ("nombre", "text", "", "Nombre descriptivo"),
    ("prefijo", "text", "", "Primeros caracteres visibles"),
    ("hash_llave", "text", "uq", "Hash SHA-256 de la llave"),
    ("alcances", "text[]", "", "Permisos de la llave"),
    ("ultimo_uso", "timestamptz", "null", "Último uso"),
    ("vence_en", "timestamptz", "null", "Vencimiento"),
    ("revocada_en", "timestamptz", "null", "Revocación"),
])

tabla(P, "consumos_periodo", "entidad", "Consumo por mes para límites del plan y cobro", [
    ("periodo", "date", "", "Primer día del mes"),
    ("metrica", "text", "", "conversaciones, mensajes, tokens_llm, almacenamiento_mb"),
    ("valor", "bigint", "", "Cantidad acumulada"),
], unicos=[("tenant_id", "periodo", "metrica")])

tabla("audit", "registros_auditoria", "entidad", "Bitácora de cambios de todas las tablas", [
    ("tenant_id", "uuid", "fk:platform.tenants null", "Tenant afectado"),
    ("usuario_id", "uuid", "fk:platform.usuarios null", "Quién hizo el cambio"),
    ("rol", "text", "", "Rol con el que actuó"),
    ("origen", "text", "", "app, eli, soporte, sistema"),
    ("esquema", "text", "", "Esquema de la tabla"),
    ("tabla", "text", "", "Tabla afectada"),
    ("registro_id", "uuid", "", "Fila afectada"),
    ("operacion", "text", "", "INSERT, UPDATE, DELETE"),
    ("datos_anteriores", "jsonb", "null R", "Valores antes"),
    ("datos_nuevos", "jsonb", "null R", "Valores después"),
], tenant=False)

# =============================================================================
# ELIUS — núcleo de negocio común
# =============================================================================
E = "elius"

tabla(E, "contactos", "entidad", "Cliente final: propietario, comensal, pasajero o comprador", [
    ("tipo", "text", "", "persona o empresa"),
    ("nombres", "text", "P", "Nombres"),
    ("apellidos", "text", "null P", "Apellidos"),
    ("email", "text", "null P", "Correo"),
    ("telefono", "text", "null P", "Teléfono E.164"),
    ("tipo_documento", "text", "null", "CC, CE, PA, NIT…"),
    ("numero_documento", "text", "null P R", "Número de documento"),
    ("fecha_nacimiento", "date", "null P R", "Fecha de nacimiento"),
    ("etiquetas", "text[]", "", "Segmentación libre"),
    ("origen", "text", "", "whatsapp, web, presencial, chrome…"),
    ("eliminado_en", "timestamptz", "null", "Borrado lógico"),
], unicos=[("tenant_id", "telefono"), ("tenant_id", "email")])

tabla(E, "direcciones", "entidad", "Direcciones de un contacto (domicilios)", [
    ("contacto_id", "uuid", "fk:elius.contactos", "Contacto"),
    ("etiqueta", "text", "", "Casa, oficina…"),
    ("direccion", "text", "P", "Dirección"),
    ("ciudad", "text", "", "Ciudad"),
    ("barrio", "text", "null", "Barrio"),
    ("indicaciones", "text", "null P", "Cómo llegar"),
    ("latitud", "numeric(9,6)", "null P", "Ubicación compartida por WhatsApp"),
    ("longitud", "numeric(9,6)", "null P", "Ubicación compartida por WhatsApp"),
    ("es_principal", "boolean", "", "Dirección por defecto"),
])

tabla(E, "consentimientos", "entidad", "Autorizaciones de tratamiento de datos (Ley 1581, art. 9)", [
    ("contacto_id", "uuid", "fk:elius.contactos", "Titular"),
    ("finalidad", "text", "", "Para qué se autoriza"),
    ("canal", "text", "", "Por dónde se obtuvo"),
    ("texto_aceptado", "text", "", "Texto exacto que aceptó"),
    ("aceptado_en", "timestamptz", "", "Fecha de aceptación"),
    ("revocado_en", "timestamptz", "null", "Fecha de revocación"),
])

tabla(E, "agentes", "entidad", "Configuración de Eli por tenant", [
    ("nombre", "text", "", "Nombre del agente"),
    ("modelo_llm", "text", "", "Modelo de lenguaje"),
    ("prompt_sistema", "text", "", "Instrucciones base"),
    ("tono", "text", "", "Ej. empático, cercano, formal"),
    ("temperatura", "numeric(3,2)", "", "Creatividad del modelo"),
    ("version", "int", "", "Versión de la configuración"),
    ("activo", "boolean", "", "En uso"),
])

tabla(E, "canales", "entidad", "Canales del tenant: número de WhatsApp, widget web, extensión", [
    ("agente_id", "uuid", "fk:elius.agentes", "Agente que atiende el canal"),
    ("tipo", "text", "", "whatsapp, web, chrome, api"),
    ("nombre", "text", "", "Nombre visible"),
    ("identificador_externo", "text", "", "Ej. phone_number_id de WhatsApp"),
    ("estado", "text", "", "activo, pausado, error"),
    ("referencia_secreto", "uuid", "null", "Llave en Supabase Vault"),
])

tabla(E, "identidades_contacto", "transicion", "Cómo se identifica un contacto en cada canal", [
    ("contacto_id", "uuid", "fk:elius.contactos", "Contacto"),
    ("canal_id", "uuid", "fk:elius.canales", "Canal"),
    ("id_externo", "text", "P", "Ej. número de WhatsApp"),
    ("nombre_en_canal", "text", "null P", "Nombre que muestra el canal (perfil de WhatsApp)"),
    ("verificado", "boolean", "", "Identidad confirmada"),
    ("primer_contacto_en", "timestamptz", "", "Primera vez por este canal"),
    ("ultimo_contacto_en", "timestamptz", "", "Última vez por este canal"),
], unicos=[("tenant_id", "canal_id", "id_externo")], resuelve=("contactos", "canales"))

tabla(E, "conversaciones", "entidad", "Conversación de un contacto con Eli por un canal", [
    ("identidad_id", "uuid", "fk:elius.identidades_contacto", "Contacto en el canal"),
    ("asignado_a", "uuid", "fk:platform.membresias null", "Humano que la atiende"),
    ("flujo", "text", "", "Flujo de Eli: ventas, reservas, menu_dia, carta…"),
    ("estado", "text", "", "en_progreso, humano, pausa, cerrada"),
    ("borrador", "jsonb", "", "Pedido o reserva que Eli va armando antes de guardarlo"),
    ("bloqueada_en", "timestamptz", "null", "Un proceso la está atendiendo (evita respuestas dobles)"),
    ("intencion", "text", "null", "Intención detectada"),
    ("sentimiento", "text", "null", "positivo, neutro, negativo"),
    ("resumen", "text", "null", "Resumen generado por Eli"),
    ("iniciada_en", "timestamptz", "", "Inicio"),
    ("ultimo_mensaje_en", "timestamptz", "", "Último mensaje"),
    ("cerrada_en", "timestamptz", "null", "Cierre"),
])

tabla(E, "mensajes", "entidad", "Mensajes de cada conversación", [
    ("conversacion_id", "uuid", "fk:elius.conversaciones", "Conversación"),
    ("emisor", "text", "", "cliente, eli, humano, sistema"),
    ("tipo_contenido", "text", "", "texto, imagen, audio, documento, plantilla"),
    ("contenido", "text", "P", "Texto del mensaje"),
    ("url_adjunto", "text", "null", "Archivo adjunto"),
    ("id_externo", "text", "null", "Id del mensaje en WhatsApp"),
    ("estado_entrega", "text", "", "recibido, enviado, entregado, leido, fallido"),
    ("procesado", "boolean", "", "Eli ya lo procesó (agrupa mensajes seguidos)"),
    ("enviado_en", "timestamptz", "", "Hora del mensaje"),
])

tabla(E, "consumos_llm", "entidad", "Cada llamada a un modelo de lenguaje", [
    ("conversacion_id", "uuid", "fk:elius.conversaciones", "Conversación"),
    ("mensaje_id", "uuid", "fk:elius.mensajes null", "Mensaje que la originó"),
    ("proveedor", "text", "", "Proveedor del modelo"),
    ("modelo", "text", "", "Modelo usado"),
    ("tokens_entrada", "int", "", "Tokens enviados"),
    ("tokens_salida", "int", "", "Tokens recibidos"),
    ("tokens_cache", "int", "", "Tokens leídos de caché"),
    ("costo_usd", "numeric(12,6)", "", "Costo estimado"),
    ("latencia_ms", "int", "", "Tiempo de respuesta"),
])

tabla(E, "categorias_catalogo", "entidad", "Categorías del catálogo: secciones del menú, tipos de servicio…", [
    ("nombre", "text", "", "Nombre"),
    ("descripcion", "text", "null", "Descripción"),
    ("orden", "int", "", "Orden de presentación"),
    ("disponible_desde", "time", "null", "Ej. desayunos desde 7:00"),
    ("disponible_hasta", "time", "null", "Ej. desayunos hasta 11:00"),
    ("activa", "boolean", "", "Visible"),
])

tabla(E, "items_catalogo", "entidad",
      "Todo lo que se vende: platos, productos, servicios, vacunas, tarifas aéreas", [
    ("categoria_id", "uuid", "fk:elius.categorias_catalogo", "Categoría"),
    ("tipo", "text", "", "producto, servicio, paquete, adicional, tarifa"),
    ("sku", "text", "null", "Código interno"),
    ("nombre", "text", "", "Nombre"),
    ("descripcion", "text", "null", "Descripción"),
    ("incluye", "text", "null", "Qué incluye un paquete"),
    ("precio", "numeric(14,2)", "", "Precio base"),
    ("impuesto_pct", "numeric(5,2)", "", "IVA o impoconsumo"),
    ("duracion_min", "int", "null", "Duración, para servicios"),
    ("disponible", "boolean", "", "false = agotado"),
    ("atributos", "jsonb", "", "Datos propios de la vertical"),
    ("eliminado_en", "timestamptz", "null", "Borrado lógico"),
], unicos=[("tenant_id", "sku")])

tabla(E, "recursos", "entidad", "Lo que se reserva: mesas, consultorios, salas", [
    ("tipo", "text", "", "mesa, consultorio, sala, equipo"),
    ("nombre", "text", "", "Ej. Mesa 12, Consultorio 2"),
    ("capacidad", "int", "", "Personas o cupos"),
    ("ubicacion", "text", "null", "Zona: terraza, salón…"),
    ("activo", "boolean", "", "Disponible"),
])

tabla(E, "horarios_atencion", "entidad", "Horario de atención del negocio o de un recurso", [
    ("recurso_id", "uuid", "fk:elius.recursos null", "Vacío = horario general"),
    ("dia_semana", "smallint", "", "1 lunes … 7 domingo"),
    ("abre", "time", "", "Hora de apertura"),
    ("cierra", "time", "", "Hora de cierre"),
    ("vigente_desde", "date", "", "Desde"),
    ("vigente_hasta", "date", "null", "Hasta"),
])

tabla(E, "reservas", "entidad", "Citas, reservas de mesa y reservas aéreas", [
    ("contacto_id", "uuid", "fk:elius.contactos", "Titular de la reserva"),
    ("conversacion_id", "uuid", "fk:elius.conversaciones null", "Conversación donde se creó"),
    ("codigo", "text", "", "Código o localizador visible al cliente"),
    ("tipo", "text", "", "cita, mesa, vuelo"),
    ("estado", "text", "", "pendiente_pago, confirmada, asistio, no_asistio, cancelada"),
    ("inicio", "timestamptz", "", "Inicio"),
    ("fin", "timestamptz", "null", "Fin"),
    ("personas", "int", "", "Número de personas"),
    ("responsable_id", "uuid", "fk:platform.membresias null", "Quién la está gestionando"),
    ("urgente", "boolean", "", "Marcada como urgente"),
    ("visto", "boolean", "", "Ya la vio el equipo"),
    ("llegada_en", "timestamptz", "null", "Hora real de llegada"),
    ("salida_en", "timestamptz", "null", "Hora real de salida"),
    ("novedades", "text", "null", "Novedades de la visita"),
    ("notas", "text", "null", "Observaciones"),
    ("creada_por_eli", "boolean", "", "La creó el agente"),
    ("id_evento_calendario", "text", "null", "Evento en Google Calendar"),
], unicos=[("tenant_id", "codigo")])

tabla(E, "asignaciones_recurso", "transicion", "Recursos ocupados por una reserva y en qué horario", [
    ("reserva_id", "uuid", "fk:elius.reservas", "Reserva"),
    ("recurso_id", "uuid", "fk:elius.recursos", "Recurso"),
    ("inicio", "timestamptz", "", "Desde"),
    ("fin", "timestamptz", "", "Hasta"),
    ("estado", "text", "", "activa, liberada"),
    ("notas", "text", "null", "Ej. mesas unidas para grupo"),
], resuelve=("reservas", "recursos"))

tabla(E, "ordenes", "entidad", "Ventas: pedidos, compras de productos, tiquetes", [
    ("contacto_id", "uuid", "fk:elius.contactos null", "Cliente; vacío = venta de mostrador"),
    ("reserva_id", "uuid", "fk:elius.reservas null", "Reserva asociada"),
    ("conversacion_id", "uuid", "fk:elius.conversaciones null", "Conversación donde se tomó"),
    ("direccion_entrega_id", "uuid", "fk:elius.direcciones null", "Para domicilios"),
    ("numero", "bigint", "", "Consecutivo por tenant"),
    ("canal_venta", "text", "", "presencial, whatsapp, web, app"),
    ("responsable_id", "uuid", "fk:platform.membresias null", "Quién la está gestionando"),
    ("tipo_entrega", "text", "", "sitio, recoger, domicilio, no_aplica"),
    ("estado", "text", "", "cotizando, esperando_pago, confirmada, en_preparacion, en_camino, entregada, cancelada"),
    ("urgente", "boolean", "", "Marcada como urgente"),
    ("visto", "boolean", "", "Ya la vio el equipo"),
    ("subtotal", "numeric(14,2)", "", "Suma de líneas"),
    ("descuento", "numeric(14,2)", "", "Descuentos"),
    ("impuestos", "numeric(14,2)", "", "Impuestos"),
    ("total", "numeric(14,2)", "", "Total calculado"),
    ("colocada_en", "timestamptz", "", "Hora del pedido"),
], unicos=[("tenant_id", "numero")])

tabla(E, "orden_items", "transicion", "Líneas de una orden: qué ítems del catálogo y cuánto", [
    ("orden_id", "uuid", "fk:elius.ordenes", "Orden"),
    ("item_id", "uuid", "fk:elius.items_catalogo", "Ítem vendido"),
    ("cantidad", "numeric(10,2)", "", "Cantidad"),
    ("precio_unitario", "numeric(14,2)", "", "Precio al momento de la venta"),
    ("recargos", "numeric(14,2)", "", "Recargos de opciones y adicionales (los suma el plugin)"),
    ("descuento", "numeric(14,2)", "", "Descuento de la línea"),
    ("total_linea", "numeric(14,2)", "", "Total de la línea"),
    ("notas", "text", "null", "Ej. sin cebolla"),
], resuelve=("ordenes", "items_catalogo"))

tabla(E, "pagos", "entidad", "Pagos y reversos de una orden", [
    ("orden_id", "uuid", "fk:elius.ordenes", "Orden"),
    ("pago_original_id", "uuid", "fk:elius.pagos null", "Si es reverso, el pago que reversa"),
    ("comprobante_id", "uuid", "fk:elius.comprobantes_pago null", "Comprobante que lo respalda"),
    ("recaudo_id", "uuid", "fk:elius.recaudos null", "Recaudo de Factus Pay que lo respalda"),
    ("metodo", "text", "", "efectivo, transferencia, breb_factus, nequi, daviplata, tarjeta, link"),
    ("proveedor", "text", "null", "Pasarela"),
    ("referencia_externa", "text", "null", "Id en la pasarela"),
    ("monto", "numeric(14,2)", "", "Monto (negativo en reversos)"),
    ("estado", "text", "", "pendiente, aprobado, rechazado"),
    ("pagado_en", "timestamptz", "", "Fecha del pago"),
])

tabla(E, "comprobantes_pago", "entidad",
      "Comprobantes de pago que el cliente envía por WhatsApp y Eli lee", [
    ("orden_id", "uuid", "fk:elius.ordenes null", "Orden que paga, si ya se identificó"),
    ("conversacion_id", "uuid", "fk:elius.conversaciones", "Conversación donde llegó"),
    ("decidido_por", "uuid", "fk:platform.membresias null", "Quién aprobó o rechazó"),
    ("monto_leido", "numeric(14,2)", "null", "Monto que Eli leyó en la imagen"),
    ("monto_esperado", "numeric(14,2)", "null", "Monto que debía pagar"),
    ("coincide", "boolean", "null", "El monto leído coincide con el esperado"),
    ("remitente", "text", "null P", "Quién envía el dinero"),
    ("destinatario", "text", "null", "A quién llegó el dinero"),
    ("app_origen", "text", "null", "Nequi, Daviplata, Bancolombia, Bre-B…"),
    ("referencia", "text", "null", "Número de la transacción"),
    ("fecha_texto", "text", "null", "Fecha y hora como aparece en el comprobante"),
    ("hash_archivo", "text", "null", "Huella del archivo para detectar repetidos"),
    ("url_archivo", "text", "null", "Imagen en Supabase Storage"),
    ("media_id", "text", "null", "Id del archivo en WhatsApp"),
    ("veredicto", "text", "", "pendiente, aprobado, rechazado"),
    ("motivo", "text", "null", "Razón del veredicto o de la alerta"),
    ("decidido_en", "timestamptz", "null", "Cuándo se decidió"),
])

tabla(E, "pasarelas_pago", "entidad",
      "Pasarelas de pago del negocio (Factus Pay con llave Bre-B) y su configuración", [
    ("proveedor", "text", "", "factus_pay"),
    ("ambiente", "text", "", "sandbox o produccion"),
    ("email_cuenta", "text", "", "Usuario de la cuenta en Factus Pay"),
    ("referencia_credenciales", "uuid", "", "Contraseña y token guardados en Supabase Vault"),
    ("referencia_clave_webhook", "uuid", "", "Clave secreta del webhook (?key=) en Supabase Vault"),
    ("monto_minimo", "numeric(14,2)", "", "Factus: 1.000 COP"),
    ("monto_maximo", "numeric(14,2)", "", "Factus: 12.100.000 COP"),
    ("expiracion_segundos", "int", "", "Vigencia del QR y la llave; Factus por defecto 86.400 (24 h)"),
    ("activa", "boolean", "", "Si está activa se cobra por llave; si no, por comprobante"),
], unicos=[("tenant_id", "proveedor", "ambiente")])

tabla(E, "recaudos", "entidad",
      "Cobros creados en la pasarela: llave Bre-B y QR por el monto exacto", [
    ("orden_id", "uuid", "fk:elius.ordenes", "Orden que se cobra"),
    ("pasarela_id", "uuid", "fk:elius.pasarelas_pago", "Pasarela usada"),
    ("codigo_referencia", "text", "", "reference_code enviado a Factus (único por empresa)"),
    ("monto", "numeric(14,2)", "", "Monto exacto: Factus no acepta parciales ni montos distintos"),
    ("llave_breb", "text", "null", "breb_key que Eli envía al cliente"),
    ("url_qr", "text", "null", "Imagen del QR en Supabase Storage"),
    ("expira_en", "timestamptz", "null", "qr_expires_at"),
    ("estado", "text", "", "listo, pagado, vencido, anulado"),
    ("cobrado_en", "timestamptz", "null", "collected_at"),
    ("pagador_nombre", "text", "null P", "payer.name del webhook"),
    ("pagador_documento", "text", "null P", "payer.document_type y document_number"),
    ("confirmado_por_api", "boolean", "", "Se verificó con GET /v1/collections/{reference}"),
    ("renovaciones", "int", "", "Veces que se renovó la expiración"),
], unicos=[("pasarela_id", "codigo_referencia")])

tabla(E, "notificaciones_pasarela", "entidad",
      "Bandeja de webhooks recibidos de la pasarela (se guardan antes de responder 2xx)", [
    ("pasarela_id", "uuid", "fk:elius.pasarelas_pago", "Pasarela que envía"),
    ("recaudo_id", "uuid", "fk:elius.recaudos null", "Recaudo identificado"),
    ("codigo_referencia", "text", "", "reference_code recibido"),
    ("carga", "jsonb", "", "Cuerpo completo del webhook"),
    ("clave_valida", "boolean", "", "La clave ?key= coincidió (comparación de tiempo constante)"),
    ("recibida_en", "timestamptz", "", "Hora de llegada"),
    ("procesada_en", "timestamptz", "null", "Cuándo se aplicó"),
    ("resultado", "text", "null", "aplicado, duplicado, rechazado, sin_recaudo"),
])

tabla(E, "entregas", "entidad", "Domicilios: quién lleva la orden y cómo va", [
    ("orden_id", "uuid", "fk:elius.ordenes", "Orden"),
    ("repartidor_id", "uuid", "fk:platform.membresias null", "Domiciliario"),
    ("estado", "text", "", "pendiente, en_camino, entregada, fallida"),
    ("cobro_contra_entrega", "numeric(14,2)", "", "Saldo que se cobra en efectivo al entregar"),
    ("tomada_en", "timestamptz", "null", "Cuándo la tomó el domiciliario"),
    ("entregada_en", "timestamptz", "null", "Cuándo se entregó"),
    ("notas", "text", "null", "Novedades de la entrega"),
])

tabla(E, "item_adicionales", "transicion", "Adicionales que se pueden sumar a cada producto o paquete", [
    ("item_id", "uuid", "fk:elius.items_catalogo", "Producto o paquete principal"),
    ("adicional_id", "uuid", "fk:elius.items_catalogo", "Ítem adicional (tipo adicional)"),
    ("precio_especial", "numeric(14,2)", "null", "Precio del adicional con este producto"),
    ("cantidad_maxima", "int", "null", "Máximo que se puede agregar"),
    ("orden", "int", "", "Orden de presentación"),
], unicos=[("item_id", "adicional_id")], resuelve=("items_catalogo", "items_catalogo"))

tabla(E, "medios_item", "entidad", "Fotos y videos de cada ítem que Eli envía al cliente", [
    ("item_id", "uuid", "fk:elius.items_catalogo", "Ítem"),
    ("tipo_archivo", "text", "", "foto, video"),
    ("url", "text", "", "Archivo"),
    ("descripcion", "text", "null", "Texto que acompaña el envío"),
    ("orden", "int", "", "Orden de envío"),
    ("activo", "boolean", "", "Se envía"),
])

tabla(E, "escalamientos", "entidad", "Casos que Eli pasa a una persona (pendientes)", [
    ("conversacion_id", "uuid", "fk:elius.conversaciones", "Conversación"),
    ("asignado_a", "uuid", "fk:platform.membresias null", "Operador asignado por turnos"),
    ("resuelto_por", "uuid", "fk:platform.membresias null", "Quién lo resolvió"),
    ("motivo", "text", "", "Por qué Eli lo escaló"),
    ("mensaje_cliente", "text", "null P", "Mensaje que lo disparó"),
    ("resumen", "text", "null", "Resumen de Eli para el humano"),
    ("resuelto_en", "timestamptz", "null", "Cuándo se resolvió"),
])

tabla(E, "eventos_embudo", "entidad", "Fases por las que pasa cada conversación (métricas de conversión)", [
    ("conversacion_id", "uuid", "fk:elius.conversaciones", "Conversación"),
    ("fase", "text", "", "mensaje_recibido, cotizo, pedido_guardado, pago_enviado, escalado…"),
    ("detalle", "jsonb", "", "Datos de la fase"),
    ("ocurrido_en", "timestamptz", "", "Cuándo"),
])

tabla(E, "errores_agente", "entidad", "Errores de Eli o de los flujos de n8n, para Soporte", [
    ("conversacion_id", "uuid", "fk:elius.conversaciones null", "Conversación afectada"),
    ("resuelto_por", "uuid", "fk:platform.usuarios null", "Quién lo resolvió (Soporte)"),
    ("origen", "text", "", "Nodo o paso donde ocurrió"),
    ("mensaje", "text", "", "Mensaje de error"),
    ("detalle", "jsonb", "", "Datos técnicos"),
    ("resuelto_en", "timestamptz", "null", "Cuándo se resolvió"),
    ("notas", "text", "null", "Notas de Soporte"),
])

tabla(E, "parametros_negocio", "entidad", "Reglas configurables del negocio (umbral de grupo, tolerancia, cuentas de pago…)", [
    ("clave", "text", "", "Ej. umbral_grupo_grande, tolerancia_minutos_llegada"),
    ("valor", "text", "", "Valor actual"),
    ("tipo_dato", "text", "", "numero, texto, booleano, porcentaje"),
    ("descripcion", "text", "", "Qué controla, en palabras del dueño"),
], unicos=[("tenant_id", "clave")])

tabla(E, "suscripciones_push", "entidad", "Dispositivos que reciben notificaciones push", [
    ("membresia_id", "uuid", "fk:platform.membresias", "Usuario que las recibe"),
    ("endpoint", "text", "uq", "Endpoint del navegador"),
    ("p256dh", "text", "", "Llave pública del navegador"),
    ("auth", "text", "", "Secreto de autenticación del navegador"),
    ("dispositivo", "text", "null", "Celular, computador…"),
    ("activa", "boolean", "", "Recibe notificaciones"),
])

tabla(E, "documentos_conocimiento", "entidad", "Documentos que Eli usa para responder (RAG)", [
    ("titulo", "text", "", "Título"),
    ("tipo_fuente", "text", "", "archivo, url, faq, manual"),
    ("url_fuente", "text", "null", "Origen"),
    ("ruta_archivo", "text", "null", "Ruta en Supabase Storage"),
    ("estado", "text", "", "procesando, listo, error"),
])

tabla(E, "fragmentos_conocimiento", "entidad", "Fragmentos de los documentos con su embedding", [
    ("documento_id", "uuid", "fk:elius.documentos_conocimiento", "Documento"),
    ("orden", "int", "", "Posición en el documento"),
    ("contenido", "text", "", "Texto del fragmento"),
    ("tokens", "int", "", "Tamaño en tokens"),
    ("embedding", "vector(1536)", "", "Vector para búsqueda semántica"),
])

tabla(E, "eventos_salida", "entidad", "Eventos para n8n: reserva creada, vuelo cancelado…", [
    ("tipo_evento", "text", "", "Ej. reserva.creada"),
    ("entidad", "text", "", "Tabla de origen"),
    ("entidad_id", "uuid", "", "Fila de origen"),
    ("carga", "jsonb", "", "Datos del evento"),
    ("estado", "text", "", "pendiente, enviado, fallido"),
    ("intentos", "int", "", "Reintentos"),
    ("procesado_en", "timestamptz", "null", "Cuándo se envió"),
])

# =============================================================================
# EXT — extensión de Chrome
# =============================================================================
X = "ext"

tabla(X, "instalaciones_extension", "entidad", "Extensión instalada por un usuario del tenant", [
    ("membresia_id", "uuid", "fk:platform.membresias", "Usuario en el tenant"),
    ("navegador", "text", "", "Chrome, Edge…"),
    ("version_extension", "text", "", "Versión"),
    ("ultimo_uso_en", "timestamptz", "null", "Última actividad"),
    ("activa", "boolean", "", "En uso"),
])

tabla(X, "sitios_autorizados", "entidad", "Sitios donde el tenant permite capturar (RN-E03)", [
    ("autorizado_por", "uuid", "fk:platform.usuarios", "Administrador"),
    ("dominio", "text", "", "Ej. web.whatsapp.com"),
    ("nombre", "text", "", "Nombre visible"),
    ("activo", "boolean", "", "Vigente"),
], unicos=[("tenant_id", "dominio")])

tabla(X, "conversaciones_capturadas", "entidad", "Conversaciones capturadas desde el navegador", [
    ("instalacion_id", "uuid", "fk:ext.instalaciones_extension", "Quién la capturó"),
    ("sitio_id", "uuid", "fk:ext.sitios_autorizados", "Dónde"),
    ("contacto_id", "uuid", "fk:elius.contactos null", "Contacto reconocido"),
    ("id_hilo_externo", "text", "", "Id del chat en el sitio"),
    ("titulo", "text", "null", "Título del hilo"),
    ("capturada_en", "timestamptz", "", "Fecha de captura"),
])

tabla(X, "mensajes_capturados", "entidad", "Mensajes de una conversación capturada", [
    ("conversacion_id", "uuid", "fk:ext.conversaciones_capturadas", "Conversación"),
    ("autor_rol", "text", "", "cliente, agente, desconocido"),
    ("autor_nombre", "text", "null P", "Nombre del autor"),
    ("contenido", "text", "P", "Texto"),
    ("enviado_en", "timestamptz", "", "Hora del mensaje"),
    ("embedding", "vector(1536)", "null", "Vector para detectar patrones"),
])

tabla(X, "patrones", "entidad", "Patrones detectados: preguntas frecuentes, objeciones, intenciones", [
    ("aprobado_por", "uuid", "fk:platform.membresias null", "Quién lo aprobó"),
    ("tipo", "text", "", "faq, objecion, intencion, plantilla"),
    ("nombre", "text", "", "Nombre"),
    ("descripcion", "text", "", "Descripción"),
    ("respuesta_sugerida", "text", "null", "Respuesta para Eli"),
    ("frecuencia", "int", "", "Veces observado"),
    ("confianza", "numeric(4,3)", "", "0 a 1"),
    ("estado", "text", "", "sugerido, aprobado, rechazado"),
    ("embedding", "vector(1536)", "null", "Vector del patrón"),
])

tabla(X, "evidencias_patron", "transicion", "Mensajes que respaldan cada patrón", [
    ("patron_id", "uuid", "fk:ext.patrones", "Patrón"),
    ("mensaje_id", "uuid", "fk:ext.mensajes_capturados", "Mensaje"),
    ("relevancia", "numeric(4,3)", "", "Qué tanto lo respalda, 0 a 1"),
    ("fragmento", "text", "", "Parte del mensaje que lo evidencia"),
    ("detectado_en", "timestamptz", "", "Cuándo se asoció"),
], unicos=[("patron_id", "mensaje_id")], resuelve=("patrones", "mensajes_capturados"))

# =============================================================================
# PLUGIN VETERINARIA
# =============================================================================
V = "plugin_vet"

tabla(V, "mascotas", "entidad", "Pacientes de la clínica", [
    ("nombre", "text", "", "Nombre"),
    ("especie", "text", "", "perro, gato, ave, exótico, otro"),
    ("raza", "text", "null", "Raza"),
    ("sexo", "text", "", "macho, hembra"),
    ("fecha_nacimiento", "date", "null", "Nacimiento aproximado"),
    ("peso_kg", "numeric(6,2)", "null", "Último peso"),
    ("microchip", "text", "null", "Número de microchip"),
    ("esterilizada", "boolean", "", "Esterilizada"),
    ("alergias", "text[]", "R", "Alergias conocidas"),
    ("fallecida_en", "date", "null", "Fecha de fallecimiento"),
])

tabla(V, "propietarios_mascota", "transicion", "Personas responsables de cada mascota", [
    ("contacto_id", "uuid", "fk:elius.contactos", "Propietario"),
    ("mascota_id", "uuid", "fk:plugin_vet.mascotas", "Mascota"),
    ("tipo", "text", "", "principal, secundario"),
    ("puede_autorizar", "boolean", "", "Puede autorizar procedimientos"),
    ("desde", "date", "", "Desde cuándo es responsable"),
], unicos=[("mascota_id", "contacto_id")], resuelve=("contactos", "mascotas"))

tabla(V, "atenciones", "transicion", "Atención de una mascota dentro de una cita", [
    ("reserva_id", "uuid", "fk:elius.reservas", "Cita"),
    ("mascota_id", "uuid", "fk:plugin_vet.mascotas", "Mascota atendida"),
    ("servicio_id", "uuid", "fk:elius.items_catalogo", "Servicio del catálogo"),
    ("profesional_id", "uuid", "fk:platform.membresias", "Veterinario que atiende"),
    ("motivo", "text", "", "Motivo de consulta"),
    ("estado", "text", "", "programada, en_curso, finalizada"),
    ("peso_kg", "numeric(6,2)", "null", "Peso en la atención"),
    ("temperatura_c", "numeric(4,1)", "null R", "Temperatura"),
], resuelve=("reservas", "mascotas"))

tabla(V, "registros_clinicos", "entidad", "Historia clínica: anotaciones de cada atención", [
    ("atencion_id", "uuid", "fk:plugin_vet.atenciones", "Atención"),
    ("autor_id", "uuid", "fk:platform.membresias", "Veterinario"),
    ("corrige_a", "uuid", "fk:plugin_vet.registros_clinicos null", "Registro que corrige (RN-V04)"),
    ("tipo", "text", "", "anamnesis, examen, diagnostico, tratamiento, correccion"),
    ("contenido", "text", "R", "Texto clínico"),
    ("registrado_en", "timestamptz", "", "Fecha del registro"),
])

tabla(V, "aplicaciones_vacuna", "transicion", "Vacunas aplicadas a cada mascota", [
    ("mascota_id", "uuid", "fk:plugin_vet.mascotas", "Mascota"),
    ("vacuna_id", "uuid", "fk:elius.items_catalogo", "Vacuna del catálogo"),
    ("atencion_id", "uuid", "fk:plugin_vet.atenciones null", "Atención en que se aplicó"),
    ("aplicada_por", "uuid", "fk:platform.membresias", "Quién la aplicó"),
    ("lote", "text", "", "Lote del biológico"),
    ("aplicada_en", "date", "", "Fecha de aplicación"),
    ("proxima_dosis_en", "date", "null", "Próxima dosis (RN-V05)"),
], resuelve=("mascotas", "items_catalogo"))

# =============================================================================
# PLUGIN RESTAURANTE
# =============================================================================
R = "plugin_restaurant"

tabla(R, "alergenos", "entidad", "Alérgenos que el restaurante informa", [
    ("nombre", "text", "", "Ej. maní, gluten, lácteos"),
    ("descripcion", "text", "null", "Descripción"),
])

tabla(R, "item_alergenos", "transicion", "Alérgenos de cada plato", [
    ("item_id", "uuid", "fk:elius.items_catalogo", "Plato"),
    ("alergeno_id", "uuid", "fk:plugin_restaurant.alergenos", "Alérgeno"),
    ("nivel", "text", "", "contiene, trazas"),
    ("nota", "text", "null", "Aclaración"),
], unicos=[("item_id", "alergeno_id")], resuelve=("items_catalogo", "alergenos"))

tabla(R, "grupos_modificador", "entidad", "Grupos de opciones: término de la carne, acompañante…", [
    ("nombre", "text", "", "Nombre"),
    ("descripcion", "text", "null", "Descripción"),
])

tabla(R, "opciones_modificador", "entidad", "Opciones de un grupo: término medio, papas…", [
    ("grupo_id", "uuid", "fk:plugin_restaurant.grupos_modificador", "Grupo"),
    ("nombre", "text", "", "Nombre"),
    ("precio_adicional", "numeric(14,2)", "", "Recargo"),
    ("disponible", "boolean", "", "false = agotado"),
    ("orden", "int", "", "Orden de presentación"),
])

tabla(R, "item_grupos_modificador", "transicion", "Qué grupos de opciones aplica cada plato", [
    ("item_id", "uuid", "fk:elius.items_catalogo", "Plato"),
    ("grupo_id", "uuid", "fk:plugin_restaurant.grupos_modificador", "Grupo"),
    ("minimo", "int", "", "Mínimo de opciones (RN-R04)"),
    ("maximo", "int", "", "Máximo de opciones (RN-R04)"),
    ("orden", "int", "", "Orden en pantalla"),
], unicos=[("item_id", "grupo_id")], resuelve=("items_catalogo", "grupos_modificador"))

tabla(R, "orden_item_opciones", "transicion", "Opciones elegidas en cada línea del pedido", [
    ("orden_item_id", "uuid", "fk:elius.orden_items", "Línea del pedido"),
    ("opcion_id", "uuid", "fk:plugin_restaurant.opciones_modificador", "Opción"),
    ("cantidad", "int", "", "Cantidad"),
    ("precio_aplicado", "numeric(14,2)", "", "Recargo cobrado"),
], resuelve=("orden_items", "opciones_modificador"))

tabla(R, "estaciones_cocina", "entidad", "Estaciones de producción: parrilla, bar, fríos", [
    ("nombre", "text", "", "Nombre"),
    ("tiempo_objetivo_min", "int", "", "Tiempo objetivo de preparación"),
    ("activa", "boolean", "", "En uso"),
])

tabla(R, "comandas", "entidad", "Envíos de un pedido a cocina, por estación y por ronda", [
    ("orden_id", "uuid", "fk:elius.ordenes", "Pedido"),
    ("estacion_id", "uuid", "fk:plugin_restaurant.estaciones_cocina", "Estación"),
    ("ronda", "int", "", "1, 2, 3… en la misma mesa"),
    ("estado", "text", "", "recibida, en_preparacion, lista, entregada"),
    ("enviada_en", "timestamptz", "", "Cuándo se envió"),
    ("lista_en", "timestamptz", "null", "Cuándo quedó lista"),
])

tabla(R, "comanda_items", "transicion", "Qué líneas del pedido van en cada comanda", [
    ("comanda_id", "uuid", "fk:plugin_restaurant.comandas", "Comanda"),
    ("orden_item_id", "uuid", "fk:elius.orden_items", "Línea del pedido"),
    ("cantidad", "numeric(10,2)", "", "Cantidad enviada en esta comanda"),
    ("estado", "text", "", "pendiente, preparando, listo"),
    ("nota_cocina", "text", "null", "Indicación para cocina"),
], resuelve=("comandas", "orden_items"))

tabla(R, "menus_dia", "entidad", "Menú del día: uno por fecha, confirmado por el dueño", [
    ("confirmado_por", "uuid", "fk:platform.membresias null", "Quién lo confirmó"),
    ("fecha", "date", "", "Día del menú"),
    ("precio_base", "numeric(14,2)", "", "Precio del menú"),
    ("url_foto", "text", "null", "Foto del menú que Eli envía"),
    ("confirmado_en", "timestamptz", "null", "Eli solo lo ofrece si está confirmado"),
    ("activo", "boolean", "", "Disponible ese día"),
], unicos=[("tenant_id", "fecha")])

tabla(R, "menu_dia_items", "transicion", "Platos que componen el menú de cada día", [
    ("menu_id", "uuid", "fk:plugin_restaurant.menus_dia", "Menú del día"),
    ("item_id", "uuid", "fk:elius.items_catalogo", "Plato"),
    ("seccion", "text", "", "entrada, principal, bebida, postre"),
    ("posicion", "int", "", "Posición en la sección (Eli lee en este orden)"),
    ("disponible", "boolean", "", "false = se acabó hoy"),
], unicos=[("menu_id", "item_id")], resuelve=("menus_dia", "items_catalogo"))

tabla(R, "celebraciones", "entidad", "Celebraciones dentro de una reserva (cumpleaños, aniversarios)", [
    ("reserva_id", "uuid", "fk:elius.reservas", "Reserva"),
    ("tipo_celebracion", "text", "", "cumpleaños, aniversario, grado…"),
    ("festejado", "text", "P", "Nombre del festejado"),
    ("decoracion", "text", "null", "Decoración solicitada"),
    ("notas", "text", "null", "Indicaciones"),
])

# =============================================================================
# PLUGIN AEROLÍNEA
# =============================================================================
A = "plugin_airline"

tabla(A, "aeropuertos", "referencia", "Aeropuertos con código IATA, comunes a todos los tenants", [
    ("codigo_iata", "char(3)", "uq", "Ej. BOG"),
    ("nombre", "text", "", "Nombre"),
    ("ciudad", "text", "", "Ciudad"),
    ("pais", "char(2)", "", "País ISO 3166"),
    ("zona_horaria", "text", "", "Zona horaria"),
], tenant=False)

tabla(A, "aeronaves", "entidad", "Flota de la aerolínea", [
    ("matricula", "text", "", "Matrícula"),
    ("modelo", "text", "", "Ej. A320"),
    ("capacidad", "int", "", "Sillas totales (RN-A04)"),
    ("mapa_sillas", "jsonb", "", "Distribución de sillas"),
    ("activa", "boolean", "", "En servicio"),
], unicos=[("tenant_id", "matricula")])

tabla(A, "rutas", "transicion", "Rutas entre dos aeropuertos", [
    ("origen_id", "uuid", "fk:plugin_airline.aeropuertos", "Aeropuerto de origen"),
    ("destino_id", "uuid", "fk:plugin_airline.aeropuertos", "Aeropuerto de destino (RN-A02)"),
    ("distancia_km", "int", "", "Distancia"),
    ("duracion_min", "int", "", "Duración estimada"),
    ("activa", "boolean", "", "En operación"),
], unicos=[("tenant_id", "origen_id", "destino_id")], resuelve=("aeropuertos", "aeropuertos"))

tabla(A, "vuelos", "entidad", "Vuelos programados", [
    ("ruta_id", "uuid", "fk:plugin_airline.rutas", "Ruta"),
    ("aeronave_id", "uuid", "fk:plugin_airline.aeronaves", "Aeronave"),
    ("numero_vuelo", "text", "", "Ej. EL123"),
    ("salida_programada", "timestamptz", "", "Salida"),
    ("llegada_programada", "timestamptz", "", "Llegada (RN-A03)"),
    ("estado", "text", "", "programado, abordando, salio, llego, retrasado, cancelado"),
    ("puerta", "text", "null", "Puerta"),
])

tabla(A, "tarifas_vuelo", "transicion", "Precio y cupos de cada tarifa del catálogo en cada vuelo", [
    ("vuelo_id", "uuid", "fk:plugin_airline.vuelos", "Vuelo"),
    ("tarifa_id", "uuid", "fk:elius.items_catalogo", "Tarifa (ítem del catálogo)"),
    ("precio", "numeric(14,2)", "", "Precio en este vuelo"),
    ("cupos_totales", "int", "", "Cupos asignados"),
    ("cupos_vendidos", "int", "", "Cupos vendidos"),
], unicos=[("vuelo_id", "tarifa_id")], resuelve=("vuelos", "items_catalogo"))

tabla(A, "reserva_pasajeros", "transicion", "Pasajeros de cada reserva aérea", [
    ("reserva_id", "uuid", "fk:elius.reservas", "Reserva"),
    ("contacto_id", "uuid", "fk:elius.contactos", "Pasajero"),
    ("tipo_pasajero", "text", "", "ADT adulto, CHD niño, INF infante (RN-A06)"),
    ("necesidades_especiales", "text", "null S", "Asistencia o condición de salud"),
], unicos=[("reserva_id", "contacto_id")], resuelve=("reservas", "contactos"))

tabla(A, "tramos_reserva", "transicion", "Vuelos que componen una reserva, en orden", [
    ("reserva_id", "uuid", "fk:elius.reservas", "Reserva"),
    ("tarifa_vuelo_id", "uuid", "fk:plugin_airline.tarifas_vuelo", "Vuelo y tarifa"),
    ("orden_tramo", "int", "", "1 = ida, 2 = regreso…"),
    ("estado", "text", "", "confirmado, cambiado, cancelado"),
], resuelve=("reservas", "tarifas_vuelo"))

tabla(A, "tiquetes", "transicion", "Tiquete de un pasajero en un tramo", [
    ("reserva_pasajero_id", "uuid", "fk:plugin_airline.reserva_pasajeros", "Pasajero"),
    ("tramo_id", "uuid", "fk:plugin_airline.tramos_reserva", "Tramo"),
    ("numero_tiquete", "text", "uq", "Número de tiquete"),
    ("silla", "text", "null", "Silla asignada (RN-A07)"),
    ("estado", "text", "", "emitido, usado, anulado"),
    ("checkin_en", "timestamptz", "null", "Hora de check-in (RN-A08)"),
], unicos=[("reserva_pasajero_id", "tramo_id")], resuelve=("reserva_pasajeros", "tramos_reserva"))

tabla(A, "equipajes", "entidad", "Equipaje registrado en un tiquete", [
    ("tiquete_id", "uuid", "fk:plugin_airline.tiquetes", "Tiquete"),
    ("tipo", "text", "", "mano, bodega, especial"),
    ("peso_kg", "numeric(5,2)", "", "Peso"),
    ("etiqueta", "text", "", "Número de etiqueta"),
    ("estado", "text", "", "registrado, cargado, entregado, perdido"),
])


# =============================================================================
# Utilidades
# =============================================================================
def nombre_completo(t):
    return f"{t['esquema']}.{t['nombre']}"


def por_nombre():
    return {nombre_completo(t): t for t in TABLAS}


def fks(t):
    """[(columna, destino, nullable)]"""
    out = []
    for c, _tipo, flags, _d in t["columnas"]:
        for f in flags.split():
            if f.startswith("fk:"):
                out.append((c, f[3:], "null" in flags.split()))
    return out
