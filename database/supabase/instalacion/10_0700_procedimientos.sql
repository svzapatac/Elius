-- =============================================================================
-- ELIUS · Migración 0700 · Procedimientos (funciones RPC)
-- Operaciones de negocio que cambian varias tablas a la vez y deben ser atómicas.
-- Se llaman desde los paneles, Eli o las Edge Functions con supabase.rpc('nombre', {...}).
--
-- SECURITY INVOKER (por defecto): corren con los permisos de quien llama, así que
-- RLS sigue aplicando. Solo son SECURITY DEFINER los que necesitan crear filas que
-- el usuario aún no puede ver (crear un tenant, aceptar una invitación) o los que
-- solo puede ejecutar el backend (webhook de Factus, tareas programadas).
-- =============================================================================

-- =============================================================================
-- PLATFORM
-- =============================================================================

-- Crea un negocio: tenant, su Administrador, el plugin de su vertical, Eli y parámetros base (RN-P08)
create or replace function platform.crear_tenant(p_nombre text, p_slug text, p_vertical text, p_plan text default 'free')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_admin uuid;
begin
  if v_uid is null then
    raise exception 'Debe iniciar sesión para crear un negocio' using errcode = '42501';
  end if;
  insert into platform.tenants (plan_id, slug, nombre, vertical, fin_prueba)
  select id, lower(p_slug), p_nombre, p_vertical, current_date + 14 from platform.planes where codigo = p_plan and activo
  returning id into v_tenant;
  if v_tenant is null then
    raise exception 'El plan % no existe', p_plan;
  end if;

  select id into v_admin from platform.roles where codigo = 'administrador';
  insert into platform.membresias (tenant_id, usuario_id, rol_id, cargo, es_predeterminada)
  values (v_tenant, v_uid, v_admin, 'Dueño',
          not exists (select 1 from platform.membresias where usuario_id = v_uid and es_predeterminada));

  insert into platform.tenant_plugins (tenant_id, plugin_id, instalado_por, version_instalada)
  select v_tenant, p.id, v_uid, p.version from platform.plugins p where p_vertical = any (p.verticales) and p.activo;

  insert into elius.agentes (tenant_id, nombre, modelo_llm, prompt_sistema, tono, activo)
  values (v_tenant, 'Eli', 'por-definir', 'Eres Eli, el asistente de ' || p_nombre || '.',
          case p_vertical when 'veterinaria' then 'empatico' else 'cercano' end, true);

  insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion)
  select v_tenant, x.clave, x.valor, x.tipo, x.descr from (values
    ('dias_anticipacion_max', case p_vertical when 'restaurante' then '120' else '365' end, 'numero', 'Días máximos para reservar con anticipación'),
    ('tolerancia_minutos_llegada', '20', 'numero', 'Minutos de espera antes de marcar no asistió'),
    ('umbral_grupo_grande', '20', 'numero', 'Personas a partir de las cuales se avisa al Administrador'),
    ('porcentaje_minimo_grupo', '80', 'porcentaje', 'Porcentaje del grupo que debe llegar'),
    ('politica_consignacion', 'No reembolsable; se puede reagendar según disponibilidad', 'texto', 'Política de la consignación de reservas')
  ) as x(clave, valor, tipo, descr);
  return v_tenant;
end $$;

-- Cambia el tenant que va en el JWT; el cliente debe refrescar la sesión después
create or replace function platform.cambiar_tenant(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not app.tiene_acceso_tenant(auth.uid(), p_tenant) then
    raise exception 'No pertenece a ese negocio' using errcode = '42501';
  end if;
  update platform.membresias set es_predeterminada = false where usuario_id = auth.uid() and es_predeterminada;
  update platform.membresias set es_predeterminada = true where usuario_id = auth.uid() and tenant_id = p_tenant;
end $$;

-- Invita a un usuario con un rol general. Devuelve el token una sola vez; se guarda su hash.
create or replace function platform.invitar_usuario(p_email text, p_rol text)
returns text language plpgsql set search_path = '' as $$
declare v_token text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  insert into platform.invitaciones (tenant_id, rol_id, invitado_por, email, hash_token)
  select app.current_tenant_id(), r.id, auth.uid(), lower(p_email), encode(extensions.digest(v_token, 'sha256'), 'hex')
  from platform.roles r where r.codigo = p_rol and r.nivel = 'tenant';
  if not found then
    raise exception 'Rol % no válido para un negocio', p_rol;
  end if;
  return v_token;
end $$;

create or replace function platform.aceptar_invitacion(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_inv record; v_email text;
begin
  select email into v_email from auth.users where id = auth.uid();
  select * into v_inv from platform.invitaciones
  where hash_token = encode(extensions.digest(p_token, 'sha256'), 'hex') and aceptada_en is null and vence_en > now()
  for update;
  if not found or lower(v_inv.email) <> lower(v_email) then
    raise exception 'RN-P12: invitación inválida, vencida o de otro correo' using errcode = '42501';
  end if;
  insert into platform.membresias (tenant_id, usuario_id, rol_id, invitado_por, es_predeterminada)
  values (v_inv.tenant_id, auth.uid(), v_inv.rol_id, v_inv.invitado_por,
          not exists (select 1 from platform.membresias where usuario_id = auth.uid() and es_predeterminada));
  update platform.invitaciones set aceptada_en = now() where id = v_inv.id;
  return v_inv.tenant_id;
end $$;

-- Activa un acceso especial del plugin para un usuario (ej. historia clínica) — sección 10.2
create or replace function platform.otorgar_acceso_especial(p_membresia uuid, p_permiso text, p_motivo text default null,
                                                            p_vence timestamptz default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into platform.accesos_especiales (tenant_id, membresia_id, permiso_id, otorgado_por, motivo, vence_en)
  select app.current_tenant_id(), p_membresia, p.id, auth.uid(), p_motivo, p_vence
  from platform.permisos p where p.codigo = p_permiso and p.es_acceso_especial
  returning id into v_id;
  if v_id is null then
    raise exception '% no es un acceso especial', p_permiso;
  end if;
  return v_id;
end $$;

-- El Administrador autoriza a Soporte por unas horas (RN-P16)
create or replace function platform.autorizar_soporte(p_usuario_soporte uuid, p_motivo text, p_horas int default 24)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into platform.accesos_soporte (tenant_id, usuario_soporte_id, autorizado_por, motivo, vence_en)
  values (app.current_tenant_id(), p_usuario_soporte, auth.uid(), p_motivo, now() + make_interval(hours => p_horas))
  returning id into v_id;
  return v_id;
end $$;

-- =============================================================================
-- ELIUS · conversaciones
-- =============================================================================

-- RN-C21: solo un proceso atiende la conversación a la vez (bloqueo con vencimiento)
create or replace function elius.tomar_bloqueo(p_conversacion uuid, p_segundos int default 60)
returns boolean language sql set search_path = '' as $$
  with t as (
    update elius.conversaciones set bloqueada_en = now()
    where id = p_conversacion and tenant_id = app.current_tenant_id()
      and (bloqueada_en is null or bloqueada_en < now() - make_interval(secs => p_segundos))
    returning 1)
  select exists (select 1 from t);
$$;

create or replace function elius.soltar_bloqueo(p_conversacion uuid)
returns void language sql set search_path = '' as $$
  update elius.conversaciones set bloqueada_en = null where id = p_conversacion and tenant_id = app.current_tenant_id();
$$;

-- Eli pasa la conversación a una persona (RN-C18: el trigger asigna por turnos)
create or replace function elius.escalar_conversacion(p_conversacion uuid, p_motivo text, p_mensaje text default null,
                                                      p_resumen text default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into elius.escalamientos (conversacion_id, motivo, mensaje_cliente, resumen)
  values (p_conversacion, p_motivo, p_mensaje, p_resumen) returning id into v_id;
  return v_id;
end $$;

-- Un Operador toma la conversación: Eli deja de responder (RN-C19)
create or replace function elius.tomar_conversacion(p_conversacion uuid)
returns void language plpgsql set search_path = '' as $$
begin
  update elius.conversaciones set estado = 'humano', asignado_a = app.mi_membresia()
  where id = p_conversacion and tenant_id = app.current_tenant_id();
  if not found then
    raise exception 'Conversación no encontrada' using errcode = 'P0002';
  end if;
end $$;

-- Devuelve la conversación a Eli y cierra sus escalamientos abiertos
create or replace function elius.devolver_a_eli(p_conversacion uuid)
returns void language plpgsql set search_path = '' as $$
begin
  update elius.escalamientos set resuelto_en = now(), resuelto_por = app.mi_membresia()
  where conversacion_id = p_conversacion and tenant_id = app.current_tenant_id() and resuelto_en is null;
  update elius.conversaciones set estado = 'en_progreso', asignado_a = null
  where id = p_conversacion and tenant_id = app.current_tenant_id();
end $$;

create or replace function elius.resolver_escalamiento(p_escalamiento uuid)
returns void language sql set search_path = '' as $$
  update elius.escalamientos set resuelto_en = now(), resuelto_por = app.mi_membresia()
  where id = p_escalamiento and tenant_id = app.current_tenant_id() and resuelto_en is null;
$$;

-- RN-C20: interruptor de emergencia de Eli
create or replace function elius.encender_eli(p_activo boolean)
returns void language plpgsql set search_path = '' as $$
begin
  if not app.puede('configuracion', 'total') then
    raise exception 'RN-C20: solo el Administrador o Soporte pueden apagar o encender a Eli' using errcode = '42501';
  end if;
  update elius.agentes set activo = p_activo
  where tenant_id = app.current_tenant_id()
    and id = (select id from elius.agentes where tenant_id = app.current_tenant_id() order by version desc limit 1);
end $$;

-- =============================================================================
-- ELIUS · reservas
-- =============================================================================

-- Agenda una reserva y ocupa sus recursos. Valida horario (RN-R02) y capacidad (RN-R01).
-- Los cruces los impide la restricción de exclusión (RN-C07).
create or replace function elius.agendar_reserva(p_contacto uuid, p_tipo text, p_inicio timestamptz, p_fin timestamptz,
                                                 p_personas int default 1, p_recursos uuid[] default '{}',
                                                 p_notas text default null, p_conversacion uuid default null)
returns uuid language plpgsql set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_id uuid;
  v_capacidad int;
  v_zona text;
  v_dia int := extract(isodow from p_inicio at time zone 'America/Bogota');
begin
  select t.zona_horaria into v_zona from platform.tenants t where t.id = v_tenant;
  v_dia := extract(isodow from p_inicio at time zone coalesce(v_zona, 'America/Bogota'));
  if exists (select 1 from elius.horarios_atencion h where h.tenant_id = v_tenant and h.recurso_id is null)
     and not exists (
       select 1 from elius.horarios_atencion h
       where h.tenant_id = v_tenant and h.recurso_id is null and h.dia_semana = v_dia
         and (p_inicio at time zone coalesce(v_zona, 'America/Bogota'))::time >= h.abre
         and (p_fin at time zone coalesce(v_zona, 'America/Bogota'))::time <= h.cierra
         and current_date >= h.vigente_desde and (h.vigente_hasta is null or current_date <= h.vigente_hasta)) then
    raise exception 'RN-R02: el negocio no atiende en ese horario' using errcode = '23514';
  end if;

  if cardinality(p_recursos) > 0 and p_tipo = 'mesa' then
    select coalesce(sum(capacidad), 0) into v_capacidad from elius.recursos
    where tenant_id = v_tenant and id = any (p_recursos) and activo;
    if v_capacidad < p_personas then
      raise exception 'RN-R01: las mesas elegidas tienen capacidad para % y la reserva es de %', v_capacidad, p_personas
        using errcode = '23514';
    end if;
  end if;

  insert into elius.reservas (contacto_id, conversacion_id, tipo, inicio, fin, personas, notas, creada_por_eli)
  values (p_contacto, p_conversacion, p_tipo, p_inicio, p_fin, p_personas, p_notas, app.mi_rol() = 'eli')
  returning id into v_id;

  insert into elius.asignaciones_recurso (reserva_id, recurso_id, inicio, fin)
  select v_id, r, p_inicio, p_fin from unnest(p_recursos) r;
  return v_id;
end $$;

-- Registra la llegada del cliente (operación del día)
create or replace function elius.marcar_llegada(p_reserva uuid)
returns void language sql set search_path = '' as $$
  update elius.reservas set llegada_en = now(), estado = 'asistio', visto = true
  where id = p_reserva and tenant_id = app.current_tenant_id() and estado = 'confirmada';
$$;

-- RN-R07: tarea programada. Marca no asistió después de la tolerancia y libera los recursos.
-- Solo para el backend (cron de Supabase o n8n), en el tenant fijado con app.tenant_id.
create or replace function elius.marcar_no_asistidas()
returns int language plpgsql set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id(); v_n int;
        v_tol int := coalesce(app.parametro(v_tenant, 'tolerancia_minutos_llegada')::int, 20);
begin
  with r as (
    update elius.reservas set estado = 'no_asistio'
    where tenant_id = v_tenant and estado = 'confirmada' and llegada_en is null
      and inicio < now() - make_interval(mins => v_tol)
    returning id)
  update elius.asignaciones_recurso a set estado = 'liberada'
  from r where a.tenant_id = v_tenant and a.reserva_id = r.id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- =============================================================================
-- ELIUS · órdenes y pagos
-- =============================================================================

create or replace function elius.crear_orden(p_contacto uuid, p_canal text default 'whatsapp', p_tipo_entrega text default 'recoger',
                                             p_reserva uuid default null, p_conversacion uuid default null,
                                             p_direccion uuid default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into elius.ordenes (contacto_id, canal_venta, tipo_entrega, reserva_id, conversacion_id, direccion_entrega_id)
  values (p_contacto, p_canal, p_tipo_entrega, p_reserva, p_conversacion, p_direccion)
  returning id into v_id;
  return v_id;
end $$;

create or replace function elius.agregar_item(p_orden uuid, p_item uuid, p_cantidad numeric default 1, p_notas text default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into elius.orden_items (orden_id, item_id, cantidad, notas)
  values (p_orden, p_item, p_cantidad, p_notas) returning id into v_id;   -- precio y total los pone el trigger T41
  return v_id;
end $$;

-- Eli registra el comprobante que mandó el cliente; el monto esperado es el saldo de la orden
create or replace function elius.registrar_comprobante(p_conversacion uuid, p_orden uuid, p_monto_leido numeric,
       p_remitente text default null, p_destinatario text default null, p_app text default null,
       p_referencia text default null, p_fecha_texto text default null, p_hash text default null,
       p_url text default null, p_media_id text default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid; v_esperado numeric;
begin
  select saldo_pendiente into v_esperado from elius.v_saldo_ordenes
  where orden_id = p_orden and tenant_id = app.current_tenant_id();
  insert into elius.comprobantes_pago (orden_id, conversacion_id, monto_leido, monto_esperado, remitente, destinatario,
                                       app_origen, referencia, fecha_texto, hash_archivo, url_archivo, media_id)
  values (p_orden, p_conversacion, p_monto_leido, v_esperado, p_remitente, p_destinatario,
          p_app, p_referencia, p_fecha_texto, p_hash, p_url, p_media_id)
  returning id into v_id;
  return v_id;
end $$;

-- Una persona aprueba el comprobante. Atómico (DT corrige el problema 11 de Potrillos):
-- crea el pago, deja el resto contra entrega si se pide, y el trigger T51 confirma la orden.
create or replace function elius.aprobar_comprobante(p_comprobante uuid, p_resto_contra_entrega boolean default false)
returns text language plpgsql set search_path = '' as $$
declare
  v_c record;
  v_saldo numeric;
  v_tenant uuid := app.current_tenant_id();
begin
  if not app.puede('pagos', 'escritura') then
    raise exception 'No tiene permiso para aprobar pagos' using errcode = '42501';
  end if;
  select * into v_c from elius.comprobantes_pago where id = p_comprobante and tenant_id = v_tenant for update;
  if not found or v_c.veredicto <> 'pendiente' then
    raise exception 'El comprobante no existe o ya fue decidido' using errcode = '23514';
  end if;
  if v_c.orden_id is null then
    raise exception 'Asocie el comprobante a una orden antes de aprobarlo' using errcode = '23514';
  end if;

  update elius.comprobantes_pago set veredicto = 'aprobado', decidido_por = app.mi_membresia(), decidido_en = now()
  where id = p_comprobante;

  select saldo_pendiente into v_saldo from elius.v_saldo_ordenes where orden_id = v_c.orden_id and tenant_id = v_tenant;
  if v_saldo <= 0 then
    return 'ya_pagada';   -- comprobante repetido del mismo pago: no se cobra dos veces
  end if;

  if p_resto_contra_entrega and coalesce(v_c.monto_leido, 0) < v_saldo then
    insert into elius.entregas (orden_id, cobro_contra_entrega)
    values (v_c.orden_id, v_saldo - coalesce(v_c.monto_leido, 0));
  end if;

  insert into elius.pagos (orden_id, comprobante_id, metodo, proveedor, referencia_externa, monto, estado)
  values (v_c.orden_id, p_comprobante, 'transferencia', v_c.app_origen, v_c.referencia,
          least(coalesce(v_c.monto_leido, v_saldo), v_saldo), 'aprobado');

  select saldo_pendiente into v_saldo from elius.v_saldo_ordenes where orden_id = v_c.orden_id and tenant_id = v_tenant;
  return case when v_saldo > 0 then 'pago_parcial' else 'pagada' end;
end $$;

create or replace function elius.rechazar_comprobante(p_comprobante uuid, p_motivo text)
returns void language plpgsql set search_path = '' as $$
begin
  update elius.comprobantes_pago set veredicto = 'rechazado', motivo = p_motivo,
         decidido_por = app.mi_membresia(), decidido_en = now()
  where id = p_comprobante and tenant_id = app.current_tenant_id() and veredicto = 'pendiente';
  if not found then
    raise exception 'El comprobante no existe o ya fue decidido' using errcode = '23514';
  end if;
end $$;

-- ---------- Factus Pay (DT-18) ----------------------------------------------------
-- Decide la estrategia de cobro de una orden: llave Bre-B con Factus si el negocio
-- la tiene activa y el monto cabe en sus límites; si no, comprobante tradicional.
create or replace function elius.estrategia_cobro(p_monto numeric)
returns text language sql stable set search_path = '' as $$
  select case when exists (
           select 1 from elius.pasarelas_pago p
           where p.tenant_id = app.current_tenant_id() and p.activa and p.proveedor = 'factus_pay'
             and p_monto between p.monto_minimo and p.monto_maximo)
         then 'llave_breb_factus' else 'comprobante' end;
$$;

-- La Edge Function llama a POST /v1/collections y guarda aquí lo que respondió Factus
create or replace function elius.registrar_recaudo(p_orden uuid, p_codigo text, p_monto numeric, p_llave text,
                                                   p_url_qr text, p_expira timestamptz)
returns uuid language plpgsql set search_path = '' as $$
declare v_pasarela uuid; v_id uuid;
begin
  select id into v_pasarela from elius.pasarelas_pago
  where tenant_id = app.current_tenant_id() and activa and proveedor = 'factus_pay'
    and p_monto between monto_minimo and monto_maximo
  order by ambiente desc limit 1;
  if v_pasarela is null then
    raise exception 'RN-C23: sin pasarela activa para este monto; use el comprobante tradicional' using errcode = '23514';
  end if;
  insert into elius.recaudos (orden_id, pasarela_id, codigo_referencia, monto, llave_breb, url_qr, expira_en)
  values (p_orden, v_pasarela, p_codigo, p_monto, p_llave, p_url_qr, p_expira)
  on conflict (pasarela_id, codigo_referencia) do update
    set expira_en = excluded.expira_en, llave_breb = excluded.llave_breb, url_qr = excluded.url_qr,
        estado = case when elius.recaudos.estado = 'vencido' then 'listo' else elius.recaudos.estado end,
        renovaciones = elius.recaudos.renovaciones + 1
  returning id into v_id;
  update elius.ordenes set estado = 'esperando_pago'
  where tenant_id = app.current_tenant_id() and id = p_orden and estado = 'cotizando';
  return v_id;
end $$;

-- Webhook de Factus (RN-C24). Lo llama SOLO la Edge Function, con el tenant fijado.
-- La Edge Function compara ?key= en tiempo constante y pasa el resultado en p_clave_valida.
-- Primero se guarda la notificación (para poder responder 2xx), luego se aplica. Idempotente.
create or replace function elius.procesar_webhook_factus(p_pasarela uuid, p_clave_valida boolean, p_carga jsonb)
returns text language plpgsql set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_ref text := p_carga -> 'data' ->> 'reference_code';
  v_monto numeric := (p_carga -> 'data' ->> 'amount')::numeric;
  v_notif uuid;
  v_rec record;
  v_recaudo uuid;
  v_resultado text;
begin
  if auth.uid() is not null then
    raise exception 'Solo el backend procesa webhooks' using errcode = '42501';
  end if;
  insert into elius.notificaciones_pasarela (pasarela_id, codigo_referencia, carga, clave_valida)
  values (p_pasarela, coalesce(v_ref, ''), p_carga, p_clave_valida) returning id into v_notif;

  if not p_clave_valida or p_carga -> 'data' ->> 'status' is distinct from 'paid' then
    v_resultado := 'rechazado';
  else
    select * into v_rec from elius.recaudos
    where tenant_id = v_tenant and pasarela_id = p_pasarela and codigo_referencia = v_ref for update;
    v_recaudo := v_rec.id;
    if not found then
      v_resultado := 'sin_recaudo';
    elsif v_rec.estado = 'pagado' then
      v_resultado := 'duplicado';
    elsif v_monto is distinct from v_rec.monto then
      v_resultado := 'rechazado';   -- Factus solo acepta el monto exacto: si no coincide, no se aplica
    else
      update elius.recaudos set estado = 'pagado', cobrado_en = now(),
             pagador_nombre = p_carga -> 'data' -> 'payer' ->> 'name',
             pagador_documento = nullif(concat_ws(' ', p_carga -> 'data' -> 'payer' ->> 'document_type',
                                                       p_carga -> 'data' -> 'payer' ->> 'document_number'), '')
      where id = v_rec.id;          -- T54 crea el pago y T51 confirma la orden
      v_resultado := 'aplicado';
    end if;
  end if;
  update elius.notificaciones_pasarela set procesada_en = now(), resultado = v_resultado, recaudo_id = v_recaudo
  where id = v_notif;
  return v_resultado;
end $$;

-- =============================================================================
-- PLUGINS
-- =============================================================================

-- Restaurante: el dueño confirma el menú del día; sin confirmar, Eli no lo ofrece (RN-R11)
create or replace function plugin_restaurant.confirmar_menu_dia(p_menu uuid)
returns void language sql set search_path = '' as $$
  update plugin_restaurant.menus_dia set confirmado_por = app.mi_membresia(), confirmado_en = now()
  where id = p_menu and tenant_id = app.current_tenant_id();
$$;

-- Restaurante: agrega una opción a una línea respetando el máximo del grupo (RN-R04)
create or replace function plugin_restaurant.agregar_opcion(p_linea uuid, p_opcion uuid, p_cantidad int default 1)
returns uuid language plpgsql set search_path = '' as $$
declare v_grupo uuid; v_max int; v_actual int; v_id uuid; v_item uuid;
begin
  select grupo_id into v_grupo from plugin_restaurant.opciones_modificador where id = p_opcion and disponible;
  select item_id into v_item from elius.orden_items where id = p_linea;
  select maximo into v_max from plugin_restaurant.item_grupos_modificador where item_id = v_item and grupo_id = v_grupo;
  if v_max is null then
    raise exception 'RN-R04: esa opción no aplica a este plato' using errcode = '23514';
  end if;
  select coalesce(sum(o.cantidad), 0) into v_actual from plugin_restaurant.orden_item_opciones o
  join plugin_restaurant.opciones_modificador om on om.id = o.opcion_id
  where o.orden_item_id = p_linea and om.grupo_id = v_grupo;
  if v_actual + p_cantidad > v_max then
    raise exception 'RN-R04: máximo % opciones de este grupo', v_max using errcode = '23514';
  end if;
  insert into plugin_restaurant.orden_item_opciones (orden_item_id, opcion_id, cantidad)
  values (p_linea, p_opcion, p_cantidad) returning id into v_id;
  return v_id;
end $$;

-- Veterinaria: registra una vacuna y calcula la próxima dosis (RN-V05)
-- La vacuna del catálogo puede traer en atributos {"refuerzo_dias": 365}
create or replace function plugin_vet.registrar_vacuna(p_mascota uuid, p_vacuna uuid, p_lote text,
                                                       p_atencion uuid default null, p_proxima date default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid; v_dias int;
begin
  select (atributos ->> 'refuerzo_dias')::int into v_dias from elius.items_catalogo where id = p_vacuna;
  insert into plugin_vet.aplicaciones_vacuna (mascota_id, vacuna_id, atencion_id, aplicada_por, lote, proxima_dosis_en)
  values (p_mascota, p_vacuna, p_atencion, app.mi_membresia(), p_lote,
          coalesce(p_proxima, current_date + v_dias))
  returning id into v_id;
  return v_id;
end $$;

-- Aerolínea: check-in entre 48 h y 1 h antes de la salida (RN-A08)
create or replace function plugin_airline.hacer_checkin(p_tiquete uuid, p_silla text)
returns void language plpgsql set search_path = '' as $$
declare v_salida timestamptz;
begin
  select v.salida_programada into v_salida
  from plugin_airline.tiquetes t
  join plugin_airline.tramos_reserva tr on tr.id = t.tramo_id
  join plugin_airline.tarifas_vuelo tv on tv.id = tr.tarifa_vuelo_id
  join plugin_airline.vuelos v on v.id = tv.vuelo_id
  where t.id = p_tiquete and t.estado = 'emitido';
  if v_salida is null then
    raise exception 'Tiquete no encontrado o no emitido' using errcode = 'P0002';
  end if;
  if now() < v_salida - interval '48 hours' or now() > v_salida - interval '1 hour' then
    raise exception 'RN-A08: el check-in abre 48 h y cierra 1 h antes de la salida' using errcode = '23514';
  end if;
  update plugin_airline.tiquetes set silla = p_silla, checkin_en = now() where id = p_tiquete;
end $$;

-- ---------- Permisos de ejecución ----------
grant execute on all functions in schema platform, elius, plugin_vet, plugin_restaurant, plugin_airline
  to authenticated, service_role, elius_app;
-- En PostgreSQL toda función nace ejecutable por PUBLIC: hay que quitárselo explícitamente
revoke execute on function elius.procesar_webhook_factus(uuid, boolean, jsonb) from public, anon, authenticated;
revoke execute on function elius.marcar_no_asistidas() from public, anon, authenticated;
grant execute on function elius.procesar_webhook_factus(uuid, boolean, jsonb) to service_role, elius_app;
grant execute on function elius.marcar_no_asistidas() to service_role, elius_app;
