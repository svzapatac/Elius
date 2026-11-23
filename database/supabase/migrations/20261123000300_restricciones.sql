-- =============================================================================
-- ELIUS · Migración 0300 · Restricciones de reglas de negocio
-- Reglas que se pueden expresar de forma declarativa (CHECK, UNIQUE, EXCLUDE).
-- Las que necesitan consultar otras tablas van como triggers en la 0500.
-- Cada restricción lleva el código de la regla que garantiza (sección 9 del levantamiento).
-- =============================================================================

-- ---------- platform ---------------------------------------------------------
alter table platform.tenants
  add constraint ck_tenants_slug_formato check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}$');            -- RN-P05
alter table platform.planes
  add constraint ck_planes_limites check (max_usuarios > 0 and max_conversaciones_mes > 0 and max_tokens_mes > 0 and precio_mensual >= 0);
alter table platform.accesos_soporte
  add constraint ck_accesos_soporte_vigencia check (vence_en > inicio and vence_en <= inicio + interval '7 days'); -- RN-P16
alter table platform.asignaciones_plataforma
  add constraint ck_asignaciones_plataforma_vigencia check (hasta is null or hasta > desde);
alter table platform.invitaciones
  add constraint ck_invitaciones_email check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
-- Solo una membresía predeterminada por usuario (es el tenant que va en el JWT)
create unique index uq_membresias_predeterminada on platform.membresias (usuario_id) where es_predeterminada;
-- Una sola invitación pendiente por correo y tenant
create unique index uq_invitaciones_pendiente on platform.invitaciones (tenant_id, lower(email)) where aceptada_en is null;

-- ---------- elius: contactos y conversaciones --------------------------------
alter table elius.contactos
  add constraint ck_contactos_telefono_e164 check (telefono is null or telefono ~ '^\+[1-9][0-9]{6,14}$'),  -- RN-C02
  add constraint ck_contactos_email check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  add constraint ck_contactos_identificable check (telefono is not null or email is not null);              -- RN-C01
create index ix_contactos_nombre_trgm on elius.contactos using gin (nombres extensions.gin_trgm_ops);
-- Una sola conversación abierta por identidad y flujo
create unique index uq_conversaciones_abierta on elius.conversaciones (tenant_id, identidad_id, flujo) where estado <> 'cerrada';
create index ix_mensajes_conversacion_fecha on elius.mensajes (tenant_id, conversacion_id, enviado_en desc);
create index ix_mensajes_sin_procesar on elius.mensajes (tenant_id, conversacion_id) where not procesado;  -- RN-C21
alter table elius.agentes
  add constraint ck_agentes_temperatura check (temperatura between 0 and 2);
-- Solo un agente activo por tenant
create unique index uq_agentes_activo on elius.agentes (tenant_id) where activo;
alter table elius.consumos_llm
  add constraint ck_consumos_llm_positivos check (tokens_entrada >= 0 and tokens_salida >= 0 and tokens_cache >= 0 and costo_usd >= 0 and latencia_ms >= 0);

-- ---------- elius: catálogo ----------------------------------------------------
alter table elius.items_catalogo
  add constraint ck_items_precio check (precio >= 0),
  add constraint ck_items_impuesto check (impuesto_pct between 0 and 100),
  add constraint ck_items_duracion check (duracion_min is null or duracion_min > 0);
alter table elius.item_adicionales
  add constraint ck_item_adicionales_distintos check (item_id <> adicional_id),
  add constraint ck_item_adicionales_cantidad check (cantidad_maxima is null or cantidad_maxima > 0);
alter table elius.categorias_catalogo
  add constraint ck_categorias_horario check (disponible_desde is null or disponible_hasta is null or disponible_desde < disponible_hasta);

-- ---------- elius: reservas y recursos ------------------------------------------
alter table elius.recursos
  add constraint ck_recursos_capacidad check (capacidad > 0);
alter table elius.horarios_atencion
  add constraint ck_horarios_dia check (dia_semana between 1 and 7),
  add constraint ck_horarios_horas check (abre < cierra);
alter table elius.reservas
  add constraint ck_reservas_fin check (fin is null or fin > inicio),                                       -- RN-C08
  add constraint ck_reservas_personas check (personas > 0),
  add constraint ck_reservas_llegada check (salida_en is null or llegada_en is not null and salida_en >= llegada_en);
alter table elius.asignaciones_recurso
  add constraint ck_asignaciones_fin check (fin > inicio),
  -- RN-C07: un recurso no puede tener dos asignaciones activas que se crucen en el tiempo (DT-08)
  add constraint ex_asignaciones_sin_cruce exclude using gist (
    tenant_id with =, recurso_id with =, tstzrange(inicio, fin, '[)') with &&
  ) where (estado = 'activa');
create index ix_reservas_agenda on elius.reservas (tenant_id, inicio) where estado in ('pendiente_pago', 'confirmada');

-- ---------- elius: órdenes, pagos y cobros --------------------------------------
alter table elius.ordenes
  add constraint ck_ordenes_montos check (subtotal >= 0 and descuento >= 0 and impuestos >= 0 and total >= 0),
  -- RN-R05: un domicilio confirmado exige dirección
  add constraint ck_ordenes_domicilio_direccion check (
    tipo_entrega <> 'domicilio' or estado in ('cotizando', 'cancelada') or direccion_entrega_id is not null);
alter table elius.orden_items
  add constraint ck_orden_items_cantidad check (cantidad > 0),
  add constraint ck_orden_items_montos check (precio_unitario >= 0 and descuento >= 0 and total_linea >= 0);
alter table elius.pagos
  -- un reverso es negativo y apunta al pago original; un pago normal es positivo (RN-C12)
  add constraint ck_pagos_reverso check ((pago_original_id is null and monto > 0) or (pago_original_id is not null and monto < 0)),
  -- un pago con Factus siempre viene de un recaudo (RN-C22)
  add constraint ck_pagos_factus_recaudo check (metodo <> 'breb_factus' or recaudo_id is not null);
alter table elius.comprobantes_pago
  add constraint ck_comprobantes_decision check ((veredicto = 'pendiente') = (decidido_en is null));
-- RN-C16: el mismo archivo no se acepta dos veces en el mismo tenant
create index ix_comprobantes_hash on elius.comprobantes_pago (tenant_id, hash_archivo) where hash_archivo is not null;
create index ix_comprobantes_referencia on elius.comprobantes_pago (tenant_id, app_origen, referencia) where referencia is not null;
alter table elius.pasarelas_pago
  add constraint ck_pasarelas_montos check (monto_minimo >= 1000 and monto_maximo <= 12100000 and monto_minimo < monto_maximo), -- RN-C23
  add constraint ck_pasarelas_expiracion check (expiracion_segundos between 60 and 604800);
alter table elius.recaudos
  add constraint ck_recaudos_monto check (monto >= 1000 and monto <= 12100000),                               -- RN-C23
  add constraint ck_recaudos_referencia check (length(codigo_referencia) between 1 and 100),
  add constraint ck_recaudos_pagado check ((estado = 'pagado') = (cobrado_en is not null));
-- Un solo recaudo listo por orden a la vez
create unique index uq_recaudos_listo_por_orden on elius.recaudos (tenant_id, orden_id) where estado = 'listo';
create index ix_notificaciones_referencia on elius.notificaciones_pasarela (tenant_id, codigo_referencia);
alter table elius.entregas
  add constraint ck_entregas_cobro check (cobro_contra_entrega >= 0);

-- ---------- elius: conocimiento, eventos, parámetros -----------------------------
create index ix_fragmentos_embedding on elius.fragmentos_conocimiento
  using hnsw (embedding extensions.vector_cosine_ops);                                                       -- DT-15
create index ix_eventos_salida_pendientes on elius.eventos_salida (estado, creado_en) where estado = 'pendiente';
alter table elius.parametros_negocio
  add constraint ck_parametros_clave check (clave ~ '^[a-z][a-z0-9_]{2,62}$');
alter table elius.consentimientos
  add constraint ck_consentimientos_revocacion check (revocado_en is null or revocado_en >= aceptado_en);

-- ---------- ext ----------------------------------------------------------------
alter table ext.patrones
  add constraint ck_patrones_confianza check (confianza between 0 and 1),
  add constraint ck_patrones_aprobacion check (estado <> 'aprobado' or aprobado_por is not null);           -- RN-E02
alter table ext.evidencias_patron
  add constraint ck_evidencias_relevancia check (relevancia between 0 and 1);
alter table ext.sitios_autorizados
  add constraint ck_sitios_dominio check (dominio ~ '^[a-z0-9.-]+\.[a-z]{2,}$');

-- ---------- plugin_vet ------------------------------------------------------------
alter table plugin_vet.mascotas
  add constraint ck_mascotas_peso check (peso_kg is null or peso_kg > 0);
alter table plugin_vet.atenciones
  add constraint ck_atenciones_signos check ((peso_kg is null or peso_kg > 0) and (temperatura_c is null or temperatura_c between 30 and 45));
alter table plugin_vet.aplicaciones_vacuna
  add constraint ck_vacunas_proxima check (proxima_dosis_en is null or proxima_dosis_en > aplicada_en);
alter table plugin_vet.registros_clinicos
  add constraint ck_registros_correccion check ((tipo = 'correccion') = (corrige_a is not null));            -- RN-V04
-- Solo un propietario principal por mascota
create unique index uq_propietario_principal on plugin_vet.propietarios_mascota (mascota_id) where tipo = 'principal';

-- ---------- plugin_restaurant ---------------------------------------------------
alter table plugin_restaurant.item_grupos_modificador
  add constraint ck_modificador_rango check (minimo >= 0 and maximo >= 1 and minimo <= maximo);            -- RN-R04
alter table plugin_restaurant.opciones_modificador
  add constraint ck_opciones_precio check (precio_adicional >= 0);
alter table plugin_restaurant.comanda_items
  add constraint ck_comanda_items_cantidad check (cantidad > 0);
alter table plugin_restaurant.menus_dia
  add constraint ck_menus_dia_confirmacion check ((confirmado_en is null) = (confirmado_por is null));
create unique index uq_menu_dia_posicion on plugin_restaurant.menu_dia_items (menu_id, seccion, posicion);

-- ---------- plugin_airline --------------------------------------------------------
alter table plugin_airline.aeropuertos
  add constraint ck_aeropuertos_iata check (codigo_iata ~ '^[A-Z]{3}$');
alter table plugin_airline.rutas
  add constraint ck_rutas_distintas check (origen_id <> destino_id);                                          -- RN-A02
alter table plugin_airline.vuelos
  add constraint ck_vuelos_horario check (llegada_programada > salida_programada);                            -- RN-A03
alter table plugin_airline.aeronaves
  add constraint ck_aeronaves_capacidad check (capacidad > 0);
alter table plugin_airline.tarifas_vuelo
  add constraint ck_tarifas_cupos check (cupos_totales >= 0 and cupos_vendidos between 0 and cupos_totales);  -- RN-A04
alter table plugin_airline.equipajes
  add constraint ck_equipajes_peso check (peso_kg > 0 and peso_kg <= 100);
alter table plugin_airline.tiquetes
  add constraint ck_tiquetes_checkin check (estado <> 'usado' or checkin_en is not null);
create unique index uq_vuelos_numero_salida on plugin_airline.vuelos (tenant_id, numero_vuelo, salida_programada);
