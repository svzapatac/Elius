-- =============================================================================
-- 4600 · Flujos 4 y 5 de veterinaria y aerolínea, distintos a los del restaurante
--   Veterinaria  4: cita de control y Eli anota la alergia de la mascota · 5: urgencia (Eli escala y una persona atiende)
--   Aerolínea    4: pasajero con silla de ruedas y maleta de bodega (Eli lo registra) · 5: vuelo retrasado y cambio con una persona
-- Reemplaza la función de la migración 4500 (mismo nombre y permisos).
-- =============================================================================
create or replace function elius.paso_flujo_vertical_prueba(p_flujo int, p_paso int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t uuid := app.current_tenant_id();
  v_vert text; v_nombre text; v_canal text;
  v_conv uuid; v_contacto uuid; v_res uuid; v_cod text; v_ini timestamptz;
  v_item record; v_masc uuid; v_tv record; v_rp uuid; v_tr uuid; v_tiq uuid; c uuid[];
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador ejecuta los flujos de prueba' using errcode = '42501'; end if;
  select vertical into v_vert from platform.tenants where id = t and slug like 'demo-%';
  if v_vert not in ('veterinaria', 'aerolinea') then raise exception 'Estos flujos son de los negocios de demostración de veterinaria y aerolínea'; end if;
  if p_flujo not in (4, 5) then raise exception 'Flujo no válido'; end if;
  v_nombre := case v_vert when 'veterinaria' then 'Cliente Vet ' else 'Cliente Air ' end || p_flujo;
  v_canal := case when v_vert = 'veterinaria' and p_flujo = 5 then 'ventas' else 'reservas' end;

  -- ───────── Paso 11: llega el cliente ─────────
  if p_paso = 11 then
    c := elius.flujo_cliente_prueba(t, v_nombre, v_canal); v_conv := c[2]; v_contacto := c[1];
    if v_vert = 'veterinaria' and p_flujo = 4 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, quiero una cita de control para mi gata Pelusa, mañana a las 9 am');
      return jsonb_build_object('mensaje', 'Llegó el cliente y pidió una cita de control para su gata Pelusa, mañana a las 9 am.');
    elsif v_vert = 'veterinaria' then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '¡Ayuda! Mi perro Rocky se comió media barra de chocolate hace 20 minutos y está temblando');
      return jsonb_build_object('mensaje', 'Llegó el cliente con una urgencia: su perro comió chocolate y está temblando.');
    end if;
    -- Aerolínea: el cliente ya tiene un vuelo reservado, pagado y con tiquete
    select tv.id as tv_id, v.id as vuelo_id, v.numero_vuelo, v.salida_programada into v_tv from plugin_airline.tarifas_vuelo tv
      join plugin_airline.vuelos v on v.tenant_id = tv.tenant_id and v.id = tv.vuelo_id
      where tv.tenant_id = t and v.estado = 'programado' and tv.cupos_vendidos < tv.cupos_totales order by v.salida_programada, tv.precio limit 1;
    if v_tv.tv_id is null then raise exception 'No hay vuelos con cupo: pulsa «Reiniciar prueba»'; end if;
    v_cod := 'R-' || upper(substr(md5(random()::text), 1, 5));
    insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
      values (t, v_contacto, v_conv, v_cod, 'vuelo', 'confirmada', v_tv.salida_programada, v_tv.salida_programada + interval '1 hour', 1, true) returning id into v_res;
    insert into plugin_airline.reserva_pasajeros (tenant_id, reserva_id, contacto_id, tipo_pasajero) values (t, v_res, v_contacto, 'ADT') returning id into v_rp;
    insert into plugin_airline.tramos_reserva (tenant_id, reserva_id, tarifa_vuelo_id, orden_tramo, estado) values (t, v_res, v_tv.tv_id, 1, 'confirmado') returning id into v_tr;
    insert into plugin_airline.tiquetes (tenant_id, reserva_pasajero_id, tramo_id, numero_tiquete, estado)
      values (t, v_rp, v_tr, '8' || substr(md5(random()::text), 1, 12), 'emitido');
    if p_flujo = 4 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, viajo mañana a Medellín. Necesito silla de ruedas hasta la puerta de embarque y voy a llevar una maleta de bodega');
      return jsonb_build_object('mensaje', format('Llegó un pasajero con la reserva %s (vuelo %s, ya pagada y con tiquete). Pide silla de ruedas hasta la puerta y una maleta de bodega.', v_cod, v_tv.numero_vuelo), 'reserva', v_cod);
    else
      update plugin_airline.vuelos set estado = 'retrasado' where tenant_id = t and id = v_tv.vuelo_id;
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, ¿mi vuelo de mañana a Medellín sigue a tiempo?');
      return jsonb_build_object('mensaje', format('El vuelo %s se marcó como RETRASADO (la base emitió el evento para avisar a los pasajeros) y un pasajero con la reserva %s pregunta si sigue a tiempo.', v_tv.numero_vuelo, v_cod), 'reserva', v_cod);
    end if;
  end if;

  select cv.id, i.contacto_id into v_conv, v_contacto from elius.conversaciones cv
    join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
    where cv.tenant_id = t and i.nombre_en_canal = v_nombre || ' Prueba' order by cv.creado_en desc limit 1;
  if v_conv is null then raise exception 'Primero ejecuta el paso 11 (llega el cliente)'; end if;

  -- ───────── Veterinaria 4: cita de control y alergia ─────────
  if v_vert = 'veterinaria' and p_flujo = 4 then
    if p_paso = 12 then
      select id into v_item from elius.items_catalogo where tenant_id = t and sku = 'VET-01' and eliminado_en is null;
      if v_item.id is null then raise exception 'No existe la consulta general en el catálogo'; end if;
      v_ini := (date_trunc('day', now() at time zone 'America/Bogota') + interval '1 day 9 hours') at time zone 'America/Bogota';
      v_cod := 'R-' || upper(substr(md5(random()::text), 1, 5));
      insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
        values (t, v_contacto, v_conv, v_cod, 'cita', 'confirmada', v_ini, v_ini + interval '30 minutes', 1, true) returning id into v_res;
      begin
        insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
          select t, v_res, rc.id, v_ini, v_ini + interval '30 minutes' from elius.recursos rc where rc.tenant_id = t and rc.tipo = 'consultorio' and rc.activo order by rc.nombre limit 1;
      exception when exclusion_violation then null;
      end;
      insert into plugin_vet.mascotas (tenant_id, nombre, especie, raza, sexo, peso_kg) values (t, 'Pelusa', 'gato', 'Criollo', 'hembra', 4.1) returning id into v_masc;
      insert into plugin_vet.propietarios_mascota (tenant_id, contacto_id, mascota_id, tipo, puede_autorizar) values (t, v_contacto, v_masc, 'principal', true);
      insert into plugin_vet.atenciones (tenant_id, reserva_id, mascota_id, servicio_id, profesional_id, motivo)
        values (t, v_res, v_masc, v_item.id, app.mi_membresia(), 'Control general');
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', format('¡Listo! Tu cita de control para Pelusa quedó confirmada para mañana a las 9:00 am (código %s). ¿Tiene alguna alergia o condición que debamos saber?', v_cod));
      return jsonb_build_object('mensaje', format('Eli agendó la cita %s (control de Pelusa, mañana 9:00 am), ya confirmada, y le preguntó por alergias. Míralo en Agenda.', v_cod), 'reserva', v_cod);
    elsif p_paso = 13 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Sí, es alérgica a la penicilina');
      return jsonb_build_object('mensaje', 'El cliente avisa que Pelusa es alérgica a la penicilina.');
    elsif p_paso = 14 then
      update plugin_vet.mascotas set alergias = array['penicilina'] where tenant_id = t and nombre = 'Pelusa'
        and id in (select mascota_id from plugin_vet.propietarios_mascota where tenant_id = t and contacto_id = v_contacto);
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Anotado: Pelusa es alérgica a la penicilina. Ya se lo avisé al veterinario.');
      return jsonb_build_object('mensaje', 'Eli anotó la alergia a la penicilina en la ficha de Pelusa. El Operador la verá en rojo en su cita.');
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

  -- ───────── Aerolínea 4: silla de ruedas y maleta de bodega ─────────
  elsif v_vert = 'aerolinea' and p_flujo = 4 then
    if p_paso = 12 then
      select tq.id, rp.id as rp_id into v_tiq, v_rp from plugin_airline.reserva_pasajeros rp
        join elius.reservas r on r.tenant_id = rp.tenant_id and r.id = rp.reserva_id
        join plugin_airline.tiquetes tq on tq.tenant_id = rp.tenant_id and tq.reserva_pasajero_id = rp.id
        where rp.tenant_id = t and r.conversacion_id = v_conv order by r.creado_en desc limit 1;
      if v_tiq is null then raise exception 'Primero ejecuta el paso 11 (llega el pasajero)'; end if;
      update plugin_airline.reserva_pasajeros set necesidades_especiales = 'Silla de ruedas hasta la puerta de embarque' where tenant_id = t and id = v_rp;
      insert into plugin_airline.equipajes (tenant_id, tiquete_id, tipo, peso_kg, etiqueta)
        values (t, v_tiq, 'bodega', 23, 'BG-' || upper(substr(md5(random()::text), 1, 6)));
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Listo: registré la silla de ruedas hasta la puerta de embarque y tu maleta de bodega de 23 kg. Recuerda hacer el check-in desde 48 horas antes.');
      return jsonb_build_object('mensaje', 'Eli registró la necesidad especial (silla de ruedas) y una maleta de bodega de 23 kg. El Operador la verá en Mi trabajo → Necesidades especiales.');
    end if;

  -- ───────── Aerolínea 5: vuelo retrasado y cambio ─────────
  elsif v_vert = 'aerolinea' and p_flujo = 5 then
    if p_paso = 12 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Tu vuelo de mañana a Medellín está RETRASADO. Apenas tengamos la nueva hora de salida te la confirmo por aquí.');
      return jsonb_build_object('mensaje', 'Eli le informó al pasajero que su vuelo está retrasado.');
    elsif p_paso = 13 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Con ese retraso pierdo mi conexión en Medellín. Necesito cambiar mi vuelo, ¿puedo hablar con una persona?');
      return jsonb_build_object('mensaje', 'El pasajero dice que pierde su conexión y pide cambiar el vuelo con una persona.');
    elsif p_paso = 14 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Entiendo, te paso con una persona del equipo para buscar otra opción de vuelo.');
      insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
        values (t, v_conv, 'Cambio de vuelo', 'Con ese retraso pierdo mi conexión en Medellín. Necesito cambiar mi vuelo', 'Vuelo retrasado: el pasajero pierde su conexión y pide cambio de vuelo');
      return jsonb_build_object('mensaje', 'Eli escaló el caso. Debe aparecer en Pendientes, asignado por turnos a un Operador.');
    end if;
  end if;
  raise exception 'Paso no válido para este flujo';
end $$;
