-- =============================================================================
-- 4300 · Flujo de prueba 3 (conversación): el cliente reserva, pide hablar con una persona,
--        explica por qué no puede ir y el equipo cancela la reserva.
--   11 llega el cliente y pide mesa · 12 Eli crea la reserva y confirma · 13 el cliente avisa que no puede ir y pide una persona
--   14 Eli escala el caso · 15 el cliente explica la situación
-- Mismas reglas que paso_flujo_prueba: solo Administrador, solo restaurante de demostración.
-- =============================================================================
create or replace function elius.paso_flujo_reserva_prueba(p_paso int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t uuid := app.current_tenant_id();
  c uuid[]; v_conv uuid; v_contacto uuid; v_res uuid; v_cod text; v_ini timestamptz; v_mesa uuid;
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador ejecuta los flujos de prueba' using errcode = '42501'; end if;
  if not exists (select 1 from platform.tenants where id = t and slug like 'demo-restaurante%') then
    raise exception 'Los flujos de prueba son del restaurante de demostración'; end if;

  if p_paso = 11 then
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 3', 'reservas'); v_conv := c[2];
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, quiero reservar una mesa para 4 personas mañana a las 7 pm');
    return jsonb_build_object('mensaje', 'Llegó el cliente y pidió una mesa para 4 personas mañana a las 7 pm.');
  end if;

  select cv.id, i.contacto_id into v_conv, v_contacto from elius.conversaciones cv
    join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
    where cv.tenant_id = t and i.nombre_en_canal = 'Cliente Flujo 3 Prueba' order by cv.creado_en desc limit 1;
  if v_conv is null then raise exception 'Primero ejecuta el paso 11 (llega el cliente)'; end if;

  if p_paso = 12 then
    v_ini := (date_trunc('day', now() at time zone 'America/Bogota') + interval '1 day 19 hours') at time zone 'America/Bogota';
    select id into v_mesa from elius.recursos where tenant_id = t and tipo = 'mesa' and activo and capacidad >= 4 order by capacidad, nombre limit 1;
    v_cod := 'R-' || upper(substr(md5(random()::text), 1, 5));
    insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
      values (t, v_contacto, v_conv, v_cod, 'mesa', 'confirmada', v_ini, v_ini + interval '2 hours', 4, true) returning id into v_res;
    if v_mesa is not null then
      begin
        insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin) values (t, v_res, v_mesa, v_ini, v_ini + interval '2 hours');
      exception when exclusion_violation then null;
      end;
    end if;
    perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', format('¡Listo! Tu mesa para 4 personas quedó reservada para mañana a las 7:00 pm. Tu código es %s.', v_cod));
    return jsonb_build_object('mensaje', format('Eli creó la reserva %s (mesa para 4, mañana 7:00 pm) y se la confirmó al cliente. Míralo en Agenda.', v_cod), 'reserva', v_cod);
  elsif p_paso = 13 then
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Surgió un imprevisto y no voy a poder ir. ¿Puedo hablar con una persona?');
    return jsonb_build_object('mensaje', 'El cliente avisa que no podrá ir y pide hablar con una persona.');
  elsif p_paso = 14 then
    perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Claro, te paso con una persona del equipo para ayudarte con tu reserva.');
    insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
      values (t, v_conv, 'Cancelar reserva', 'Surgió un imprevisto y no voy a poder ir', 'El cliente no puede asistir a su reserva y quiere hablar con una persona');
    return jsonb_build_object('mensaje', 'Eli escaló el caso. Debe aparecer en Pendientes, asignado por turnos a un Operador.');
  elsif p_paso = 15 then
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Mi hijo amaneció enfermo y no podemos salir. Por favor cancelen la reserva, gracias.');
    return jsonb_build_object('mensaje', 'El cliente explicó la situación: su hijo está enfermo y pide cancelar la reserva.');
  end if;
  raise exception 'Paso no válido para el flujo 3';
end $$;

revoke execute on function elius.paso_flujo_reserva_prueba(int) from public, anon;
grant execute on function elius.paso_flujo_reserva_prueba(int) to authenticated;
comment on function elius.paso_flujo_reserva_prueba(int) is 'Flujo de prueba 3 (reserva y petición de cancelación); solo Administrador en el restaurante de demostración';
