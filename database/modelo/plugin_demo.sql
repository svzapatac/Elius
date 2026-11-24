-- Datos de ejemplo del plugin del negocio (solo el de su vertical), para que las sentencias sugeridas devuelvan filas
create or replace function elius.sembrar_plugin_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
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

