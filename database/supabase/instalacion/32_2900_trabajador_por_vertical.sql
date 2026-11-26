-- =============================================================================
-- 2900 · El panel del Trabajador cambia según el negocio (plugin)
-- Un trabajador de restaurante, de veterinaria y de aerolínea no hacen lo mismo. Cada uno ve y usa solo lo de su plugin,
-- con los permisos que ya tiene el rol Operador (restaurant.cocina, vet.pacientes, airline.reservas).
--   · Restaurante: cocina (comandas por estación), celebraciones del día, menú vigente
--   · Veterinaria: citas del día con la mascota, signos vitales, cerrar atención, vacunas por vencer
--   · Aerolínea: check-in (manifiesto), pasajeros con necesidades especiales, vuelos
-- Vistas security_invoker: la RLS y los permisos del usuario siguen mandando.
-- =============================================================================

-- Restaurante
create or replace view elius.v_trab_cocina with (security_invoker = true) as
  select c.comanda_id, c.estacion, c.orden_numero, c.ronda, c.estado, c.enviada_en, c.espera, c.plato, c.cantidad, c.nota_cocina, c.estado_plato
  from plugin_restaurant.v_cocina_pendiente c;

create or replace view elius.v_trab_celebraciones with (security_invoker = true) as
  select r.codigo, r.inicio, r.personas, r.estado, c.tipo_celebracion, c.festejado, c.decoracion, c.notas
  from plugin_restaurant.celebraciones c join elius.reservas r on r.tenant_id = c.tenant_id and r.id = c.reserva_id
  where r.estado in ('confirmada', 'pendiente_pago', 'asistio');

create or replace view elius.v_trab_menu with (security_invoker = true) as
  select * from plugin_restaurant.v_menu_vigente;

create or replace function elius.trab_avanzar_comanda(p_comanda uuid)
returns text language plpgsql set search_path = '' as $$
declare v_nuevo text;
begin
  update plugin_restaurant.comandas
     set estado = case estado when 'recibida' then 'en_preparacion' when 'en_preparacion' then 'lista' end,
         lista_en = case when estado = 'en_preparacion' then now() else lista_en end
   where id = p_comanda and estado in ('recibida', 'en_preparacion')
   returning estado into v_nuevo;
  if v_nuevo is null then raise exception 'La comanda no existe o ya está lista' using errcode = 'P0002'; end if;
  if v_nuevo = 'lista' then
    update plugin_restaurant.comanda_items set estado = 'listo' where comanda_id = p_comanda;
  else
    update plugin_restaurant.comanda_items set estado = 'preparando' where comanda_id = p_comanda;
  end if;
  return v_nuevo;
end $$;

-- Veterinaria
create or replace view elius.v_trab_citas_vet with (security_invoker = true) as
  select a.id as atencion_id, r.codigo, r.inicio, r.estado as estado_cita, a.estado, a.motivo, a.peso_kg, a.temperatura_c,
         m.nombre as mascota, m.especie, m.raza, m.alergias, c.nombres || ' ' || coalesce(c.apellidos, '') as propietario, c.telefono
  from plugin_vet.atenciones a
  join elius.reservas r on r.tenant_id = a.tenant_id and r.id = a.reserva_id
  join plugin_vet.mascotas m on m.tenant_id = a.tenant_id and m.id = a.mascota_id
  join elius.contactos c on c.tenant_id = r.tenant_id and c.id = r.contacto_id
  where a.estado in ('programada', 'en_curso') and r.estado <> 'cancelada';

create or replace view elius.v_trab_vacunas with (security_invoker = true) as
  select mascota, especie, vacuna, proxima_dosis_en, propietario, telefono from plugin_vet.v_vacunas_por_vencer;

create or replace function elius.trab_registrar_signos(p_atencion uuid, p_peso numeric, p_temperatura numeric)
returns void language plpgsql set search_path = '' as $$
begin
  update plugin_vet.atenciones set peso_kg = p_peso, temperatura_c = p_temperatura,
         estado = case when estado = 'programada' then 'en_curso' else estado end
   where id = p_atencion and estado in ('programada', 'en_curso');
  if not found then raise exception 'La atención no existe o ya terminó' using errcode = 'P0002'; end if;
end $$;

create or replace function elius.trab_cerrar_atencion(p_atencion uuid)
returns void language plpgsql set search_path = '' as $$
begin
  update plugin_vet.atenciones set estado = 'finalizada' where id = p_atencion and estado = 'en_curso';
  if not found then raise exception 'Primero registra los signos de la mascota (la atención debe estar en curso)' using errcode = 'P0002'; end if;
end $$;

-- Aerolínea
create or replace view elius.v_trab_checkin with (security_invoker = true) as
  select t.id as tiquete_id, v.numero_vuelo, v.salida_programada, c.nombres || ' ' || coalesce(c.apellidos, '') as pasajero,
         rp.tipo_pasajero, t.numero_tiquete, t.silla, t.estado as estado_tiquete, t.checkin_en, r.codigo as localizador
  from plugin_airline.tiquetes t
  join plugin_airline.reserva_pasajeros rp on rp.tenant_id = t.tenant_id and rp.id = t.reserva_pasajero_id
  join plugin_airline.tramos_reserva tr on tr.tenant_id = t.tenant_id and tr.id = t.tramo_id
  join plugin_airline.tarifas_vuelo tv on tv.tenant_id = tr.tenant_id and tv.id = tr.tarifa_vuelo_id
  join plugin_airline.vuelos v on v.tenant_id = tv.tenant_id and v.id = tv.vuelo_id
  join elius.reservas r on r.tenant_id = rp.tenant_id and r.id = rp.reserva_id
  join elius.contactos c on c.tenant_id = rp.tenant_id and c.id = rp.contacto_id
  where t.estado in ('emitido', 'usado');

create or replace view elius.v_trab_necesidades with (security_invoker = true) as
  select r.codigo as localizador, c.nombres || ' ' || coalesce(c.apellidos, '') as pasajero, rp.tipo_pasajero, rp.necesidades_especiales
  from plugin_airline.reserva_pasajeros rp
  join elius.reservas r on r.tenant_id = rp.tenant_id and r.id = rp.reserva_id
  join elius.contactos c on c.tenant_id = rp.tenant_id and c.id = rp.contacto_id
  where rp.necesidades_especiales is not null;

create or replace view elius.v_trab_vuelos with (security_invoker = true) as
  select * from plugin_airline.v_ocupacion_vuelos;

create or replace function elius.trab_hacer_checkin(p_tiquete uuid, p_silla text)
returns void language plpgsql set search_path = '' as $$
begin
  perform plugin_airline.hacer_checkin(p_tiquete, p_silla);
end $$;

grant select on elius.v_trab_cocina, elius.v_trab_celebraciones, elius.v_trab_menu, elius.v_trab_citas_vet, elius.v_trab_vacunas,
  elius.v_trab_checkin, elius.v_trab_necesidades, elius.v_trab_vuelos to authenticated;
revoke execute on function elius.trab_avanzar_comanda(uuid), elius.trab_registrar_signos(uuid, numeric, numeric),
  elius.trab_cerrar_atencion(uuid), elius.trab_hacer_checkin(uuid, text) from public, anon;
grant execute on function elius.trab_avanzar_comanda(uuid), elius.trab_registrar_signos(uuid, numeric, numeric),
  elius.trab_cerrar_atencion(uuid), elius.trab_hacer_checkin(uuid, text) to authenticated;
comment on function elius.trab_avanzar_comanda(uuid) is 'Restaurante: la comanda pasa de recibida a en preparación y luego a lista';
comment on function elius.trab_registrar_signos(uuid, numeric, numeric) is 'Veterinaria: registra peso y temperatura y deja la atención en curso';
comment on function elius.trab_cerrar_atencion(uuid) is 'Veterinaria: finaliza la atención';
comment on function elius.trab_hacer_checkin(uuid, text) is 'Aerolínea: check-in del pasajero (RN-A08: ventana de 48 h a 1 h antes)';

-- La limpieza borra primero las órdenes (y sus comandas) y luego las estaciones
create or replace function elius.limpiar_caso_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from plugin_vet.mascotas where tenant_id = p_tenant;
  delete from elius.pagos where tenant_id = p_tenant;
  delete from elius.comprobantes_pago where tenant_id = p_tenant;
  delete from elius.entregas where tenant_id = p_tenant;
  delete from elius.ordenes where tenant_id = p_tenant;
  delete from plugin_restaurant.menus_dia where tenant_id = p_tenant;
  delete from plugin_restaurant.estaciones_cocina where tenant_id = p_tenant;
  delete from elius.asignaciones_recurso where tenant_id = p_tenant;
  delete from elius.reservas where tenant_id = p_tenant;
  delete from plugin_airline.vuelos where tenant_id = p_tenant;
  delete from plugin_airline.rutas where tenant_id = p_tenant;
  delete from plugin_airline.aeronaves where tenant_id = p_tenant;
  delete from elius.escalamientos where tenant_id = p_tenant;
  delete from elius.consumos_llm where tenant_id = p_tenant;
  delete from elius.contactos where tenant_id = p_tenant;   -- cascada: identidades, conversaciones y mensajes
  delete from elius.parametros_negocio where tenant_id = p_tenant and clave like 'demo\_%';
end $$;

-- Datos de ejemplo: pedidos en sala con sus comandas (la cocina del restaurante tiene trabajo) y nueva versión del guion
create or replace function elius.sembrar_plugin_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_ord uuid; v_oi uuid; v_est uuid; v_cm uuid; v_cli uuid;
  v_mem uuid; v_item uuid; v_menu uuid; v_ruta uuid; v_vuelo uuid; v_tv uuid; v_at uuid; v_masc uuid; v_rp uuid; v_tr uuid;
  v_aer uuid; v_o uuid; v_d uuid; r record; k int;
begin
  select id into v_mem from platform.membresias where tenant_id = p_tenant order by creado_en limit 1;

  if p_vertical = 'veterinaria' then
    k := 0;
    for r in select id, nombres from elius.contactos where tenant_id = p_tenant order by telefono limit 8 loop
      k := k + 1;
      insert into plugin_vet.mascotas (tenant_id, nombre, especie, raza, sexo, fecha_nacimiento, peso_kg, esterilizada, alergias)
      values (p_tenant,
        (array['Max','Luna','Toby','Mia','Rocky','Nala','Simón','Kira'])[k],
        (array['perro','gato','perro','gato','perro','perro','gato','perro'])[k],
        (array['Labrador','Criollo','Beagle','Siamés','Schnauzer','Golden','Persa','Bulldog'])[k],
        (array['macho','hembra'])[1 + k % 2],
        current_date - ((k + 1) * 280),
        (array[28.5,4.2,11.3,3.8,9.6,26.1,4.9,22.4])[k],
        k % 3 = 0,
        case when k in (2, 5) then array['pollo']::text[] when k = 7 then array['penicilina']::text[] else array[]::text[] end)
      returning id into v_masc;
      insert into plugin_vet.propietarios_mascota (tenant_id, contacto_id, mascota_id, tipo, puede_autorizar, desde)
      values (p_tenant, r.id, v_masc, 'principal', true, current_date - 400);
      -- vacuna aplicada, con refuerzo próximo para varias mascotas
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = 'VET-02';
      insert into plugin_vet.aplicaciones_vacuna (tenant_id, mascota_id, vacuna_id, aplicada_por, lote, aplicada_en, proxima_dosis_en)
      values (p_tenant, v_masc, v_item, v_mem, 'LT-' || (2400 + k), current_date - (330 + k * 3), current_date + (k * 4 - 6));
    end loop;
    -- atenciones de las citas ya agendadas, con su historia clínica
    k := 0;
    for r in select rs.id as reserva_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'cita' order by rs.inicio limit 5 loop
      k := k + 1;
      select id into v_masc from plugin_vet.mascotas where tenant_id = p_tenant order by nombre offset k - 1 limit 1;
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = 'VET-01';
      insert into plugin_vet.atenciones (tenant_id, reserva_id, mascota_id, servicio_id, profesional_id, motivo, estado, peso_kg, temperatura_c)
      values (p_tenant, r.reserva_id, v_masc, v_item, v_mem,
        (array['Control anual','Vómito desde ayer','Cojera en pata trasera','Picazón y enrojecimiento','Revisión posoperatoria'])[k],
        'programada', null, null) returning id into v_at;
      insert into plugin_vet.registros_clinicos (tenant_id, atencion_id, autor_id, tipo, contenido)
      values (p_tenant, v_at, v_mem, 'anamnesis', (array['Sin novedades, come y bebe bien.','Dos episodios de vómito, sin fiebre.','Cojea al levantarse.','Se rasca las orejas hace tres días.','Herida cerrando bien.'])[k]);
    end loop;

  elsif p_vertical = 'restaurante' then
    insert into plugin_restaurant.estaciones_cocina (tenant_id, nombre, tiempo_objetivo_min) values
      (p_tenant, 'Cocina caliente', 18), (p_tenant, 'Cocina fría y bar', 8), (p_tenant, 'Postres', 10);
    insert into plugin_restaurant.menus_dia (tenant_id, fecha, precio_base, confirmado_por, confirmado_en, activo)
    values (p_tenant, (now() at time zone 'America/Bogota')::date, 22000, v_mem, now(), true) returning id into v_menu;
    for r in select * from (values ('RES-03','entrada',1), ('RES-01','principal',2), ('RES-02','principal',3), ('RES-04','bebida',4), ('RES-05','postre',5)) t(sku, sec, pos) loop
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = r.sku;
      insert into plugin_restaurant.menu_dia_items (tenant_id, menu_id, item_id, seccion, posicion) values (p_tenant, v_menu, v_item, r.sec, r.pos);
    end loop;
    k := 0;
    for r in select rs.id as reserva_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'mesa' order by rs.inicio limit 5 loop
      k := k + 1;
      insert into plugin_restaurant.celebraciones (tenant_id, reserva_id, tipo_celebracion, festejado, decoracion, notas)
      values (p_tenant, r.reserva_id,
        (array['cumpleaños','aniversario','grado','bautizo','cumpleaños'])[k],
        (array['Valentina','Pareja Ríos','Camilo','Sofía','Don Hernán'])[k],
        (array['Globos rosados','Velas y flores','Arco de globos','Tonos suaves','Letrero dorado'])[k],
        (array['Torta llega a las 7 p. m.','Mesa junto a la ventana','Traen su propia torta','Sin frutos secos','Sorpresa: apagar luces'])[k]);
    end loop;
    -- pedidos en sala con sus comandas, para que la cocina tenga trabajo
    k := 0;
    for r in select * from (values
        (1, 'RES-01', 2, 'Cocina caliente', 'recibida', 'sin chorizo en una'),
        (1, 'RES-04', 2, 'Cocina fría y bar', 'en_preparacion', null),
        (2, 'RES-02', 1, 'Cocina caliente', 'en_preparacion', 'término medio'),
        (3, 'RES-05', 2, 'Postres', 'recibida', null)) t(n, sku, cant, est, est_com, nota) loop
      if r.n <> k then
        k := r.n;
        select id into v_cli from elius.contactos where tenant_id = p_tenant order by telefono offset k limit 1;
        insert into elius.ordenes (tenant_id, contacto_id, canal_venta, tipo_entrega)
        values (p_tenant, v_cli, 'presencial', 'sitio') returning id into v_ord;
      end if;
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = r.sku;
      insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (p_tenant, v_ord, v_item, r.cant) returning id into v_oi;
      select id into v_est from plugin_restaurant.estaciones_cocina where tenant_id = p_tenant and nombre = r.est;
      select id into v_cm from plugin_restaurant.comandas where tenant_id = p_tenant and orden_id = v_ord and estacion_id = v_est;
      if v_cm is null then
        insert into plugin_restaurant.comandas (tenant_id, orden_id, estacion_id, ronda, enviada_en, estado)
        values (p_tenant, v_ord, v_est, 1, now() - (k * interval '4 minutes'), r.est_com) returning id into v_cm;
      end if;
      insert into plugin_restaurant.comanda_items (tenant_id, comanda_id, orden_item_id, cantidad, nota_cocina)
      values (p_tenant, v_cm, v_oi, r.cant, r.nota);
    end loop;
    update elius.ordenes set estado = 'en_preparacion' where tenant_id = p_tenant and canal_venta = 'presencial' and estado <> 'en_preparacion';

  elsif p_vertical = 'aerolinea' then
    insert into plugin_airline.aeropuertos (codigo_iata, nombre, ciudad, pais, zona_horaria)
    select t.c, t.n, t.ci, 'CO', 'America/Bogota' from (values
      ('BOG','El Dorado','Bogotá'), ('MDE','José María Córdova','Medellín'), ('CTG','Rafael Núñez','Cartagena'), ('ADZ','Gustavo Rojas Pinilla','San Andrés')) t(c, n, ci)
    where not exists (select 1 from plugin_airline.aeropuertos a where a.codigo_iata = t.c);
    insert into plugin_airline.aeronaves (tenant_id, matricula, modelo, capacidad) values
      (p_tenant, 'HK-4501', 'Airbus A320', 180), (p_tenant, 'HK-4502', 'Airbus A319', 144);
    select id into v_aer from plugin_airline.aeronaves where tenant_id = p_tenant order by matricula limit 1;
    select id into v_o from plugin_airline.aeropuertos where codigo_iata = 'BOG';
    k := 0;
    for r in select * from (values ('MDE','AER-01',55,70,19000), ('CTG','AER-02',90,75,22000), ('ADZ','AER-03',140,120,41500)) t(dest, sku, dur, km, pre) loop
      k := k + 1;
      select id into v_d from plugin_airline.aeropuertos where codigo_iata = r.dest;
      insert into plugin_airline.rutas (tenant_id, origen_id, destino_id, distancia_km, duracion_min)
      values (p_tenant, v_o, v_d, r.km * 10, r.dur) returning id into v_ruta;
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = r.sku;
      for k in 1..2 loop
        insert into plugin_airline.vuelos (tenant_id, ruta_id, aeronave_id, numero_vuelo, salida_programada, llegada_programada, estado, puerta)
        values (p_tenant, v_ruta, v_aer, 'EL' || (100 + (select count(*) from plugin_airline.vuelos where tenant_id = p_tenant) + 1),
          date_trunc('day', now()) + (k * interval '1 day') + interval '23 hours', date_trunc('day', now()) + (k * interval '1 day') + interval '23 hours' + (r.dur * interval '1 minute'),
          'programado', 'A' || (3 + k)) returning id into v_vuelo;
        insert into plugin_airline.tarifas_vuelo (tenant_id, vuelo_id, tarifa_id, precio, cupos_totales, cupos_vendidos)
        values (p_tenant, v_vuelo, v_item, (select precio from elius.items_catalogo where id = v_item) + (k - 1) * 15000, 30, case when r.dest = 'ADZ' then 27 + k when k = 1 then 18 else 6 end);
      end loop;
    end loop;
    -- pasajeros, tramos y tiquetes de las reservas de vuelo ya agendadas
    select tv.id into v_tv from plugin_airline.tarifas_vuelo tv where tv.tenant_id = p_tenant order by tv.creado_en limit 1;
    k := 0;
    for r in select rs.id as reserva_id, rs.contacto_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'vuelo' order by rs.inicio limit 6 loop
      k := k + 1;
      insert into plugin_airline.reserva_pasajeros (tenant_id, reserva_id, contacto_id, tipo_pasajero, necesidades_especiales)
      values (p_tenant, r.reserva_id, r.contacto_id, 'ADT', case when k in (2, 5) then (array['Silla de ruedas hasta la puerta','Menú sin gluten'])[1 + k % 2] else null end)
      returning id into v_rp;
      insert into plugin_airline.tramos_reserva (tenant_id, reserva_id, tarifa_vuelo_id, orden_tramo, estado)
      values (p_tenant, r.reserva_id, v_tv, 1, 'confirmado') returning id into v_tr;
      insert into plugin_airline.tiquetes (tenant_id, reserva_pasajero_id, tramo_id, numero_tiquete, silla, estado, checkin_en)
      values (p_tenant, v_rp, v_tr, '8' || substr(md5(random()::text), 1, 12), (10 + k) || 'A', case when k <= 2 then 'usado' else 'emitido' end,
              case when k <= 2 then now() - interval '1 hour' else null end);
    end loop;
  end if;
end $$;

do $$ declare d text;
begin
  d := replace(pg_get_functiondef('elius.sembrar_clientes_demo(uuid,text)'::regprocedure), '''demo_version'', ''9''', '''demo_version'', ''10''');
  execute d;
end $$;
revoke execute on function elius.sembrar_plugin_demo(uuid, text), elius.sembrar_clientes_demo(uuid, text) from public, anon, authenticated;
