-- =============================================================================
-- 4500 · Flujos de prueba 4 y 5 de veterinaria y aerolínea (conversaciones predeterminadas)
--   Veterinaria  4: cita de vacunación por WhatsApp con pago · 5: urgencia (Eli escala y una persona atiende)
--   Aerolínea    4: reserva de vuelo con pago y tiquete · 5: imprevisto, una persona atiende y se cancela la reserva
-- Mismas reglas que paso_flujo_prueba: solo Administrador, solo en el negocio de demostración de ese tipo.
-- =============================================================================
create or replace function elius.paso_flujo_vertical_prueba(p_flujo int, p_paso int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t uuid := app.current_tenant_id();
  v_vert text; v_nombre text; v_canal text;
  v_conv uuid; v_contacto uuid; v_res uuid; v_cod text; v_ini timestamptz; v_orden uuid; v_num bigint; v_total numeric;
  v_item record; v_masc uuid; v_tv record; v_rp uuid; v_tr uuid; v_comp uuid; v_estado text; c uuid[];
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador ejecuta los flujos de prueba' using errcode = '42501'; end if;
  select vertical into v_vert from platform.tenants where id = t and slug like 'demo-%';
  if v_vert not in ('veterinaria', 'aerolinea') then raise exception 'Estos flujos son de los negocios de demostración de veterinaria y aerolínea'; end if;
  if p_flujo not in (4, 5) then raise exception 'Flujo no válido'; end if;
  v_nombre := case v_vert when 'veterinaria' then 'Cliente Vet ' else 'Cliente Air ' end || p_flujo;
  v_canal := case when v_vert = 'veterinaria' and p_flujo = 5 then 'ventas' else 'reservas' end;

  -- ───────── Paso 11: llega el cliente (crea contacto y conversación) ─────────
  if p_paso = 11 then
    c := elius.flujo_cliente_prueba(t, v_nombre, v_canal); v_conv := c[2]; v_contacto := c[1];
    if v_vert = 'veterinaria' and p_flujo = 4 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, quiero agendar la vacuna múltiple para mi perro Toby mañana a las 10 am');
      return jsonb_build_object('mensaje', 'Llegó el cliente y pidió la vacuna múltiple para su perro Toby, mañana a las 10 am.');
    elsif v_vert = 'veterinaria' then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '¡Ayuda! Mi perro Rocky se comió media barra de chocolate hace 20 minutos y está temblando');
      return jsonb_build_object('mensaje', 'Llegó el cliente con una urgencia: su perro comió chocolate y está temblando.');
    elsif p_flujo = 4 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, quiero un vuelo Bogotá – Medellín para mañana, para 1 pasajero');
      return jsonb_build_object('mensaje', 'Llegó el cliente y pidió un vuelo Bogotá – Medellín para mañana, 1 pasajero.');
    else
      -- el cliente ya tenía un vuelo reservado y confirmado
      select tv.id, v.salida_programada into v_tv from plugin_airline.tarifas_vuelo tv
        join plugin_airline.vuelos v on v.tenant_id = tv.tenant_id and v.id = tv.vuelo_id
        where tv.tenant_id = t and v.estado = 'programado' and tv.cupos_vendidos < tv.cupos_totales order by v.salida_programada, tv.precio limit 1;
      if v_tv.id is null then raise exception 'No hay vuelos con cupo: pulsa «Reiniciar prueba»'; end if;
      v_cod := 'R-' || upper(substr(md5(random()::text), 1, 5));
      insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
        values (t, v_contacto, v_conv, v_cod, 'vuelo', 'confirmada', v_tv.salida_programada, v_tv.salida_programada + interval '1 hour', 1, true) returning id into v_res;
      insert into plugin_airline.reserva_pasajeros (tenant_id, reserva_id, contacto_id, tipo_pasajero) values (t, v_res, v_contacto, 'ADT') returning id into v_rp;
      insert into plugin_airline.tramos_reserva (tenant_id, reserva_id, tarifa_vuelo_id, orden_tramo, estado) values (t, v_res, v_tv.id, 1, 'confirmado');
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, tengo una reserva de vuelo para mañana. Surgió un imprevisto y no voy a poder viajar. ¿Puedo hablar con una persona?');
      return jsonb_build_object('mensaje', format('El cliente, que ya tenía la reserva %s confirmada, avisa que no podrá viajar y pide hablar con una persona.', v_cod), 'reserva', v_cod);
    end if;
  end if;

  select cv.id, i.contacto_id into v_conv, v_contacto from elius.conversaciones cv
    join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
    where cv.tenant_id = t and i.nombre_en_canal = v_nombre || ' Prueba' order by cv.creado_en desc limit 1;
  if v_conv is null then raise exception 'Primero ejecuta el paso 11 (llega el cliente)'; end if;

  -- ───────── Veterinaria 4: cita de vacunación con pago ─────────
  if v_vert = 'veterinaria' and p_flujo = 4 then
    if p_paso = 12 then
      select id, nombre into v_item from elius.items_catalogo where tenant_id = t and sku = 'VET-02' and eliminado_en is null;
      if v_item.id is null then raise exception 'No existe el servicio de vacuna múltiple en el catálogo'; end if;
      v_ini := (date_trunc('day', now() at time zone 'America/Bogota') + interval '1 day 10 hours') at time zone 'America/Bogota';
      v_cod := 'R-' || upper(substr(md5(random()::text), 1, 5));
      insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
        values (t, v_contacto, v_conv, v_cod, 'cita', 'pendiente_pago', v_ini, v_ini + interval '30 minutes', 1, true) returning id into v_res;
      begin
        insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
          select t, v_res, rc.id, v_ini, v_ini + interval '30 minutes' from elius.recursos rc where rc.tenant_id = t and rc.tipo = 'consultorio' and rc.activo order by rc.nombre limit 1;
      exception when exclusion_violation then null;
      end;
      insert into plugin_vet.mascotas (tenant_id, nombre, especie, raza, sexo, peso_kg) values (t, 'Toby', 'perro', 'Beagle', 'macho', 11.3) returning id into v_masc;
      insert into plugin_vet.propietarios_mascota (tenant_id, contacto_id, mascota_id, tipo, puede_autorizar) values (t, v_contacto, v_masc, 'principal', true);
      insert into plugin_vet.atenciones (tenant_id, reserva_id, mascota_id, servicio_id, profesional_id, motivo)
        values (t, v_res, v_masc, v_item.id, app.mi_membresia(), 'Vacuna múltiple');
      insert into elius.ordenes (tenant_id, contacto_id, reserva_id, conversacion_id, canal_venta, tipo_entrega)
        values (t, v_contacto, v_res, v_conv, 'whatsapp', 'sitio') returning id, numero into v_orden, v_num;
      insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (t, v_orden, v_item.id, 1);
      update elius.ordenes set estado = 'esperando_pago' where tenant_id = t and id = v_orden;
      select total into v_total from elius.ordenes where id = v_orden;
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', format('¡Listo! Agendé la vacuna múltiple de Toby para mañana a las 10:00 am (código %s). El valor es $%s; envíame el comprobante para confirmar la cita.', v_cod, v_total));
      return jsonb_build_object('mensaje', format('Eli agendó la cita %s (vacuna múltiple de Toby, mañana 10:00 am) y le pidió el pago de $%s. La cita queda «Falta el pago».', v_cod, v_total), 'reserva', v_cod, 'total', v_total);
    elsif p_paso = 3 then
      select o.id, o.total into v_orden, v_total from elius.ordenes o where o.tenant_id = t and o.conversacion_id = v_conv order by o.creado_en desc limit 1;
      if v_orden is null then raise exception 'Primero ejecuta el paso 12 (Eli agenda la cita)'; end if;
      insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, remitente, app_origen, referencia, hash_archivo)
        values (t, v_orden, v_conv, v_total, v_total, 'Cliente Vet 4', 'Nequi', 'V4' || floor(random() * 1000000)::int, 'flujo-' || gen_random_uuid()::text);
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '📎 Listo, ya pagué por Nequi', '/demo/comprobante-res-1.jpg');
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Recibí tu comprobante. La clínica lo está verificando y te confirmo en un momento.');
      return jsonb_build_object('mensaje', format('El cliente envió el comprobante por $%s (el valor exacto). Está pendiente en Comprobantes.', v_total));
    end if;

  -- ───────── Veterinaria 5: urgencia ─────────
  elsif v_vert = 'veterinaria' and p_flujo = 5 then
    if p_paso = 12 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Esto es una urgencia. Te comunico ahora mismo con una persona de la clínica. Mientras tanto no le des nada de comer ni intentes hacerlo vomitar.');
      insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
        values (t, v_conv, 'Urgencia', 'Mi perro Rocky se comió media barra de chocolate hace 20 minutos y está temblando', 'Urgencia veterinaria: perro con posible intoxicación por chocolate');
      return jsonb_build_object('mensaje', 'Eli escaló la urgencia. Debe aparecer en Pendientes, asignada por turnos a un Operador.');
    elsif p_paso = 13 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Pesa 8 kilos. ¿Lo puedo llevar ahora mismo?');
      return jsonb_build_object('mensaje', 'El cliente da más datos (8 kilos) y pregunta si puede llevarlo ya.');
    elsif p_paso = 14 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Voy saliendo, llego en 15 minutos. Gracias.');
      return jsonb_build_object('mensaje', 'El cliente avisa que sale hacia la clínica.');
    end if;

  -- ───────── Aerolínea 4: reserva de vuelo con pago y tiquete ─────────
  elsif v_vert = 'aerolinea' and p_flujo = 4 then
    if p_paso = 12 then
      select tv.id as tv_id, tv.precio, v.salida_programada, v.numero_vuelo, i.id as item_id into v_tv
        from plugin_airline.tarifas_vuelo tv
        join plugin_airline.vuelos v on v.tenant_id = tv.tenant_id and v.id = tv.vuelo_id
        join elius.items_catalogo i on i.tenant_id = tv.tenant_id and i.id = tv.tarifa_id and i.sku = 'AER-01'
        where tv.tenant_id = t and v.estado = 'programado' and tv.cupos_vendidos < tv.cupos_totales order by v.salida_programada limit 1;
      if v_tv.tv_id is null then raise exception 'No hay vuelos Bogotá – Medellín con cupo: pulsa «Reiniciar prueba»'; end if;
      v_cod := 'R-' || upper(substr(md5(random()::text), 1, 5));
      insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
        values (t, v_contacto, v_conv, v_cod, 'vuelo', 'pendiente_pago', v_tv.salida_programada, v_tv.salida_programada + interval '1 hour', 1, true) returning id into v_res;
      insert into plugin_airline.reserva_pasajeros (tenant_id, reserva_id, contacto_id, tipo_pasajero) values (t, v_res, v_contacto, 'ADT');
      insert into plugin_airline.tramos_reserva (tenant_id, reserva_id, tarifa_vuelo_id, orden_tramo, estado) values (t, v_res, v_tv.tv_id, 1, 'confirmado');
      insert into elius.ordenes (tenant_id, contacto_id, reserva_id, conversacion_id, canal_venta, tipo_entrega)
        values (t, v_contacto, v_res, v_conv, 'whatsapp', 'no_aplica') returning id, numero into v_orden, v_num;
      insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (t, v_orden, v_tv.item_id, 1);
      update elius.ordenes set estado = 'esperando_pago' where tenant_id = t and id = v_orden;
      select total into v_total from elius.ordenes where id = v_orden;
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', format('Tengo el vuelo %s de mañana, Bogotá – Medellín, tarifa Light por $%s. Tu reserva es %s: envíame el comprobante de pago para emitir el tiquete.', v_tv.numero_vuelo, v_total, v_cod));
      return jsonb_build_object('mensaje', format('Eli reservó 1 cupo en el vuelo %s (reserva %s) y pidió el pago de $%s. La reserva queda «Falta el pago».', v_tv.numero_vuelo, v_cod, v_total), 'reserva', v_cod, 'total', v_total);
    elsif p_paso = 3 then
      select o.id, o.total into v_orden, v_total from elius.ordenes o where o.tenant_id = t and o.conversacion_id = v_conv order by o.creado_en desc limit 1;
      if v_orden is null then raise exception 'Primero ejecuta el paso 12 (Eli reserva el vuelo)'; end if;
      insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, remitente, app_origen, referencia, hash_archivo)
        values (t, v_orden, v_conv, v_total, v_total, 'Cliente Air 4', 'Nequi', 'A4' || floor(random() * 1000000)::int, 'flujo-' || gen_random_uuid()::text);
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '📎 Listo, ya pagué por Nequi', '/demo/comprobante-res-1.jpg');
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Recibí tu comprobante. Lo está verificando el equipo y te emito el tiquete en un momento.');
      return jsonb_build_object('mensaje', format('El cliente envió el comprobante por $%s (el valor exacto). Está pendiente en Comprobantes.', v_total));
    elsif p_paso = 14 then
      select r.id, r.codigo, r.estado into v_res, v_cod, v_estado from elius.reservas r where r.tenant_id = t and r.conversacion_id = v_conv order by r.creado_en desc limit 1;
      if v_res is null then raise exception 'Primero ejecuta los pasos anteriores'; end if;
      if v_estado <> 'confirmada' then raise exception 'La reserva sigue en «%»: primero el Administrador debe aprobar el comprobante', v_estado; end if;
      select rp.id, tr.id into v_rp, v_tr from plugin_airline.reserva_pasajeros rp
        join plugin_airline.tramos_reserva tr on tr.tenant_id = rp.tenant_id and tr.reserva_id = rp.reserva_id where rp.tenant_id = t and rp.reserva_id = v_res limit 1;
      insert into plugin_airline.tiquetes (tenant_id, reserva_pasajero_id, tramo_id, numero_tiquete, estado)
        values (t, v_rp, v_tr, '8' || substr(md5(random()::text), 1, 12), 'emitido') returning numero_tiquete into v_cod;
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', format('¡Pago confirmado! Tu tiquete %s está emitido. El check-in abre 48 horas antes del vuelo.', v_cod));
      return jsonb_build_object('mensaje', format('Eli emitió el tiquete %s y se lo avisó al cliente. Ya aparece en Mi trabajo → Check-in.', v_cod), 'tiquete', v_cod);
    end if;

  -- ───────── Aerolínea 5: imprevisto y cancelación ─────────
  elsif v_vert = 'aerolinea' and p_flujo = 5 then
    if p_paso = 12 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Claro, te paso con una persona del equipo para ayudarte con tu reserva.');
      insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
        values (t, v_conv, 'Cancelar vuelo', 'Surgió un imprevisto y no voy a poder viajar', 'El cliente no puede viajar y quiere hablar con una persona');
      return jsonb_build_object('mensaje', 'Eli escaló el caso. Debe aparecer en Pendientes, asignado por turnos a un Operador.');
    elsif p_paso = 13 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Mi mamá fue hospitalizada y tengo que quedarme con ella. Por favor cancelen mi reserva, gracias.');
      return jsonb_build_object('mensaje', 'El cliente explicó la situación: su mamá fue hospitalizada y pide cancelar la reserva.');
    end if;
  end if;
  raise exception 'Paso no válido para este flujo';
end $$;

revoke execute on function elius.paso_flujo_vertical_prueba(int, int) from public, anon;
grant execute on function elius.paso_flujo_vertical_prueba(int, int) to authenticated;
comment on function elius.paso_flujo_vertical_prueba(int, int) is 'Flujos de prueba 4 y 5 de veterinaria y aerolínea (conversaciones predeterminadas); solo Administrador en el negocio de demostración';
