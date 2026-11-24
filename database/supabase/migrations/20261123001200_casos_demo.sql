-- =============================================================================
-- 1200 · Casos de prueba por vertical (restaurante, veterinaria, aerolínea)
-- El profesor elige un caso en el panel: se crea el negocio con su catálogo (5 ítems con imagen)
-- y, desde el panel, llegan 20 mensajes de prueba con las respuestas de Eli.
-- =============================================================================

create or replace function elius.datos_caso_demo(p_vertical text)
returns jsonb language sql immutable set search_path = '' as $$
  select case p_vertical
    when 'restaurante' then '{"negocio": "Restaurante Sabor Criollo", "categorias": ["Platos fuertes", "Bebidas", "Postres"], "contactos": [["Camila", "Rojas", "+573001110001"], ["Andrés", "Pardo", "+573001110002"], ["Laura", "Gómez", "+573001110003"]], "items": [{"cat": 0, "tipo": "producto", "sku": "RES-01", "nombre": "Bandeja paisa", "desc": "Frijoles, arroz, carne molida, chicharrón, chorizo, huevo, plátano maduro y arepa.", "precio": 38000, "iva": 8, "dur": null}, {"cat": 0, "tipo": "producto", "sku": "RES-02", "nombre": "Hamburguesa de la casa", "desc": "Carne de res 180 g, queso, tocineta y papas a la francesa.", "precio": 28000, "iva": 8, "dur": null}, {"cat": 0, "tipo": "producto", "sku": "RES-03", "nombre": "Arepa rellena de pollo", "desc": "Arepa de maíz rellena de pollo desmechado con guacamole.", "precio": 16000, "iva": 8, "dur": null}, {"cat": 1, "tipo": "producto", "sku": "RES-04", "nombre": "Limonada de coco", "desc": "Limonada cremada con coco, servida bien fría.", "precio": 12000, "iva": 8, "dur": null}, {"cat": 2, "tipo": "producto", "sku": "RES-05", "nombre": "Tres leches", "desc": "Bizcocho bañado en tres leches con crema y canela.", "precio": 14000, "iva": 8, "dur": null}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, buenas noches. ¿Tienen mesa para 4 personas mañana a las 8 pm?"}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Camila! Bienvenida a Sabor Criollo 🍽️ Mañana a las 8:00 p. m. tenemos mesa para 4 en la terraza. ¿Te la reservo a tu nombre?"}, {"conv": 1, "emisor": "cliente", "texto": "Buenas, quiero pedir a domicilio una bandeja paisa y una limonada de coco"}, {"conv": 1, "emisor": "eli", "texto": "¡Hola Andrés! Anoté 1 Bandeja paisa ($38.000) y 1 Limonada de coco ($12.000). Son $50.000 más $5.000 de domicilio. ¿A qué dirección lo enviamos?"}, {"conv": 0, "emisor": "cliente", "texto": "Sí, por favor, a nombre de Camila Rojas. Es el cumpleaños de mi mamá"}, {"conv": 0, "emisor": "eli", "texto": "Listo: mañana 8:00 p. m., 4 personas, a nombre de Camila Rojas 🎂 Puedo llevar un Tres leches ($14.000) con vela. Para confirmar la reserva se pide una consignación de $20.000, ¿te paso los datos?"}, {"conv": 2, "emisor": "cliente", "texto": "Hola, ¿ustedes tienen opciones sin gluten?"}, {"conv": 2, "emisor": "eli", "texto": "Hola Laura 😊 La Arepa rellena de pollo ($16.000) es de maíz y no lleva gluten; la Bandeja paisa tampoco. Si tu alergia es severa te paso con el administrador para confirmar con cocina. ¿Lo hago?"}, {"conv": 1, "emisor": "cliente", "texto": "Carrera 15 # 82-10, apto 301"}, {"conv": 1, "emisor": "eli", "texto": "Gracias, dirección anotada: Cra 15 #82-10, apto 301. Total con domicilio: $55.000, llega en unos 40 minutos. ¿Pagas por transferencia o en efectivo?"}, {"conv": 0, "emisor": "cliente", "texto": "Sí, pásame los datos de la consignación"}, {"conv": 0, "emisor": "eli", "texto": "Puedes consignar $20.000 a la llave Bre-B @saborcriollo o al Nequi 300 123 4567. Envíame la foto del comprobante y confirmo tu reserva."}, {"conv": 1, "emisor": "cliente", "texto": "Transferencia, ya te envío el comprobante"}, {"conv": 1, "emisor": "eli", "texto": "Perfecto, Andrés. Cuando lo envíes, una persona del restaurante verifica que el monto haya llegado y confirmamos tu pedido."}, {"conv": 2, "emisor": "cliente", "texto": "Sí, por favor. Soy alérgica a las nueces y al maní"}, {"conv": 2, "emisor": "eli", "texto": "Entendido, Laura. Te paso con el administrador para confirmar con cocina que ningún plato tenga trazas de nueces ni maní. En un momento te escribe una persona."}, {"conv": 0, "emisor": "cliente", "texto": "📎 Comprobante de consignación $20.000.jpg"}, {"conv": 0, "emisor": "eli", "texto": "Recibido, Camila. Lo estamos validando; cuando el administrador confirme el monto, tu reserva queda confirmada ✅"}, {"conv": 1, "emisor": "cliente", "texto": "¿Puedo agregar un postre al pedido?"}, {"conv": 1, "emisor": "eli", "texto": "Claro, agrego un Tres leches ($14.000). El total del pedido queda en $69.000. ¿Lo confirmo?"}]}'::jsonb
    when 'veterinaria' then '{"negocio": "Clínica Veterinaria Huellitas", "categorias": ["Consultas y cirugía", "Prevención", "Estética"], "contactos": [["Mariana", "Ruiz", "+573002220001"], ["Julián", "Castro", "+573002220002"], ["Paola", "Díaz", "+573002220003"]], "items": [{"cat": 0, "tipo": "servicio", "sku": "VET-01", "nombre": "Consulta general", "desc": "Examen clínico completo con orientación de tratamiento.", "precio": 60000, "iva": 0, "dur": 30}, {"cat": 1, "tipo": "servicio", "sku": "VET-02", "nombre": "Vacuna múltiple", "desc": "Esquema anual para perros y gatos, con carné actualizado.", "precio": 75000, "iva": 0, "dur": 20}, {"cat": 2, "tipo": "servicio", "sku": "VET-03", "nombre": "Baño y peluquería", "desc": "Baño medicado, corte de pelo y de uñas, limpieza de oídos.", "precio": 55000, "iva": 19, "dur": 90}, {"cat": 1, "tipo": "servicio", "sku": "VET-04", "nombre": "Desparasitación", "desc": "Desparasitante interno y externo según el peso de la mascota.", "precio": 35000, "iva": 0, "dur": 15}, {"cat": 0, "tipo": "servicio", "sku": "VET-05", "nombre": "Esterilización canina", "desc": "Cirugía con anestesia, exámenes previos y control posoperatorio.", "precio": 320000, "iva": 0, "dur": 120}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, mi perro Max tiene las vacunas atrasadas, ¿puedo sacar cita para esta semana?"}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Mariana! 🐶 Claro, para Max tenemos la Vacuna múltiple ($75.000). Hay cupo el jueves a las 10:00 a. m. o a las 3:00 p. m. ¿Cuál te sirve?"}, {"conv": 1, "emisor": "cliente", "texto": "Buenas, mi gata Luna lleva dos días sin comer y está decaída"}, {"conv": 1, "emisor": "eli", "texto": "Hola Julián, lamento que Luna esté así 🐱 Dos días sin comer es motivo de revisión pronta. Puedo darte cita de Consulta general ($60.000) hoy a las 4:00 p. m. ¿Te sirve?"}, {"conv": 0, "emisor": "cliente", "texto": "El jueves a las 10 está perfecto"}, {"conv": 0, "emisor": "eli", "texto": "Agendado: jueves 10:00 a. m., Max, Vacuna múltiple. Llega 10 minutos antes y trae su carné de vacunación si lo tienes. ¿Qué edad tiene Max?"}, {"conv": 2, "emisor": "cliente", "texto": "Hola, tengo un cachorro de 3 meses, Toby. ¿Qué necesita?"}, {"conv": 2, "emisor": "eli", "texto": "¡Hola Paola, qué ternura! 🐕 A los 3 meses Toby necesita su esquema de vacunas y desparasitación ($35.000). Una Consulta general ($60.000) nos permite revisarlo y armar el plan. ¿Quieres agendarla?"}, {"conv": 1, "emisor": "cliente", "texto": "Sí, a las 4 de hoy, voy saliendo ya"}, {"conv": 1, "emisor": "eli", "texto": "Listo, hoy 4:00 p. m. para Luna. Como hay síntomas, aviso al veterinario de turno para que la reciba de inmediato. Si empeora en el camino, llámanos a la línea de urgencias."}, {"conv": 0, "emisor": "cliente", "texto": "Max tiene 5 años, es un labrador"}, {"conv": 0, "emisor": "eli", "texto": "Gracias. Anoto: Max, labrador de 5 años. Te llegará un recordatorio el miércoles por la tarde."}, {"conv": 2, "emisor": "cliente", "texto": "Sí, agéndame para mañana por favor"}, {"conv": 2, "emisor": "eli", "texto": "Mañana tengo 9:00 a. m. o 11:30 a. m. para Toby. ¿Cuál prefieres?"}, {"conv": 1, "emisor": "cliente", "texto": "Ya llegamos"}, {"conv": 1, "emisor": "eli", "texto": "Perfecto, avisé en recepción. En un momento las atiende el veterinario 🩺"}, {"conv": 2, "emisor": "cliente", "texto": "A las 9 a. m."}, {"conv": 2, "emisor": "eli", "texto": "Confirmado: mañana 9:00 a. m., Consulta general para Toby. Para la cita puedes consignar o pagar en la clínica; si consignas, envíame el comprobante."}, {"conv": 0, "emisor": "cliente", "texto": "¿Y ya que vamos puedo agregar el baño para Max?"}, {"conv": 0, "emisor": "eli", "texto": "Claro, agrego el Baño y peluquería ($55.000) después de la vacuna; el total del día sería $130.000. ¿Lo confirmo?"}]}'::jsonb
    when 'aerolinea' then '{"negocio": "Aerolínea Cóndor Andino", "categorias": ["Tarifas", "Servicios adicionales"], "contactos": [["Sergio", "Molina", "+573003330001"], ["Daniela", "Vargas", "+573003330002"], ["Carlos", "Núñez", "+573003330003"]], "items": [{"cat": 0, "tipo": "tarifa", "sku": "AER-01", "nombre": "Bogotá – Medellín (Light)", "desc": "Solo equipaje de mano. Sin cambios ni devolución.", "precio": 189000, "iva": 19, "dur": null}, {"cat": 0, "tipo": "tarifa", "sku": "AER-02", "nombre": "Bogotá – Cartagena (Flex)", "desc": "Maleta de 23 kg incluida y un cambio de fecha sin costo.", "precio": 329000, "iva": 19, "dur": null}, {"cat": 0, "tipo": "tarifa", "sku": "AER-03", "nombre": "Bogotá – San Andrés (Promo)", "desc": "Tarifa promocional con equipaje de mano, cupos limitados.", "precio": 415000, "iva": 19, "dur": null}, {"cat": 1, "tipo": "adicional", "sku": "AER-04", "nombre": "Maleta de bodega 23 kg", "desc": "Equipaje adicional para tu vuelo.", "precio": 85000, "iva": 19, "dur": null}, {"cat": 1, "tipo": "adicional", "sku": "AER-05", "nombre": "Selección de asiento", "desc": "Elige ventana o pasillo antes del check-in.", "precio": 25000, "iva": 19, "dur": null}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, necesito un vuelo Bogotá–Medellín el viernes en la mañana"}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Sergio! ✈️ El viernes tengo vuelo a las 7:10 a. m. y a las 9:40 a. m. en tarifa Light desde $189.000 (equipaje de mano). ¿Cuál prefieres?"}, {"conv": 1, "emisor": "cliente", "texto": "Buenas, ¿cuánto cuesta ir a Cartagena el 20 de diciembre?"}, {"conv": 1, "emisor": "eli", "texto": "Hola Daniela. A Cartagena el 20 de diciembre tengo la tarifa Flex en $329.000, con maleta de 23 kg y un cambio de fecha sin costo. ¿Cuántos pasajeros viajan?"}, {"conv": 0, "emisor": "cliente", "texto": "El de las 7:10. Voy con equipaje, una maleta grande"}, {"conv": 0, "emisor": "eli", "texto": "Entonces te recomiendo la tarifa Light ($189.000) más una Maleta de bodega ($85.000): total $274.000. ¿Quieres elegir asiento por $25.000?"}, {"conv": 2, "emisor": "cliente", "texto": "Hola, ¿tienen vuelos baratos a San Andrés en enero?"}, {"conv": 2, "emisor": "eli", "texto": "Hola Carlos 🏝️ Para enero tengo la tarifa Promo a San Andrés en $415.000 con equipaje de mano, con cupos limitados. ¿Qué fechas tienes en mente?"}, {"conv": 1, "emisor": "cliente", "texto": "Somos 2 adultos"}, {"conv": 1, "emisor": "eli", "texto": "Para 2 adultos serían $658.000 en Flex. ¿Me confirmas nombres completos y número de documento de cada pasajero?"}, {"conv": 0, "emisor": "cliente", "texto": "Sí, agrego asiento de ventana. Mi cédula es 1.020.345.678"}, {"conv": 0, "emisor": "eli", "texto": "Anotado: Sergio Molina, vuelo 7:10 a. m., Light + maleta + asiento = $299.000. Para emitir el tiquete se paga con consignación y se envía el comprobante."}, {"conv": 2, "emisor": "cliente", "texto": "Del 10 al 17 de enero"}, {"conv": 2, "emisor": "eli", "texto": "Del 10 al 17 de enero tengo cupo en la tarifa Promo. Son $415.000 por trayecto por persona. ¿Cuántos viajan?"}, {"conv": 1, "emisor": "cliente", "texto": "Daniela Vargas CC 52.111.222 y Mateo Vargas CC 1.098.765.432"}, {"conv": 1, "emisor": "eli", "texto": "Gracias. Reservo 2 pasajeros en Flex: $658.000 en total. La reserva se mantiene 24 horas mientras envías el comprobante de pago."}, {"conv": 0, "emisor": "cliente", "texto": "📎 Comprobante pago tiquete $299.000.jpg"}, {"conv": 0, "emisor": "eli", "texto": "Recibido, Sergio. Lo estamos validando; cuando se confirme el monto emitimos tu tiquete y te lo enviamos por aquí ✅"}, {"conv": 2, "emisor": "cliente", "texto": "Somos solo 1 pasajero, cuéntame los pasos"}, {"conv": 2, "emisor": "eli", "texto": "Para 1 pasajero son $415.000. Necesito tu nombre completo y documento; luego te paso los datos para pagar y emitimos el tiquete."}]}'::jsonb
  end;
$$;

-- Crea (o reutiliza) el negocio de prueba del caso para el usuario que llama y lo deja activo
create or replace function platform.cargar_caso_demo(p_vertical text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_slug text;
  v_tenant uuid; v_agente uuid; v_canal uuid; v_ident uuid; v_contacto uuid;
  v_cats uuid[] := '{}'; v_cat uuid; v_item uuid;
  r jsonb; k int;
begin
  if v_uid is null then raise exception 'Debe iniciar sesión' using errcode = '42501'; end if;
  if v_d is null then raise exception 'Caso desconocido: %', p_vertical; end if;
  v_slug := 'demo-' || p_vertical || '-' || substr(replace(v_uid::text, '-', ''), 1, 6);

  select id into v_tenant from platform.tenants where slug = v_slug;
  if v_tenant is not null then
    perform platform.cambiar_tenant(v_tenant);
    return v_tenant;
  end if;

  v_tenant := platform.crear_tenant(v_d->>'negocio', v_slug, p_vertical);
  select id into v_agente from elius.agentes where tenant_id = v_tenant limit 1;
  insert into elius.canales (tenant_id, agente_id, tipo, nombre, identificador_externo)
  values (v_tenant, v_agente, 'whatsapp', 'WhatsApp de prueba', 'demo-' || v_slug) returning id into v_canal;

  for r in select * from jsonb_array_elements(v_d->'categorias') loop
    insert into elius.categorias_catalogo (tenant_id, nombre, orden)
    values (v_tenant, r #>> '{}', coalesce(array_length(v_cats, 1), 0)) returning id into v_cat;
    v_cats := v_cats || v_cat;
  end loop;

  k := 0;
  for r in select * from jsonb_array_elements(v_d->'items') loop
    k := k + 1;
    insert into elius.items_catalogo (tenant_id, categoria_id, tipo, sku, nombre, descripcion, precio, impuesto_pct, duracion_min)
    values (v_tenant, v_cats[(r->>'cat')::int + 1], r->>'tipo', r->>'sku', r->>'nombre', r->>'desc',
            (r->>'precio')::numeric, (r->>'iva')::numeric, nullif(r->>'dur', '')::int)
    returning id into v_item;
    insert into elius.medios_item (tenant_id, item_id, tipo_archivo, url, descripcion, orden)
    values (v_tenant, v_item, 'foto', '/demo/' || p_vertical || '-' || k || '.svg', r->>'nombre', 0);
  end loop;

  for r in select * from jsonb_array_elements(v_d->'contactos') loop
    insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen)
    values (v_tenant, r->>0, r->>1, r->>2, 'whatsapp') returning id into v_contacto;
    insert into elius.identidades_contacto (tenant_id, contacto_id, canal_id, id_externo, nombre_en_canal)
    values (v_tenant, v_contacto, v_canal, r->>2, (r->>0) || ' ' || (r->>1)) returning id into v_ident;
    insert into elius.conversaciones (tenant_id, identidad_id, flujo)
    values (v_tenant, v_ident, 'general');
  end loop;

  insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion)
  values (v_tenant, 'demo_indice', '0', 'numero', 'Mensajes de prueba ya entregados (caso de demostración)');

  perform platform.cambiar_tenant(v_tenant);
  return v_tenant;
end $$;

-- Entrega el siguiente mensaje del guion (20 por caso). El panel lo llama cada pocos segundos.
-- Si una persona tomó la conversación, Eli no responde en ella (RN-C19) y se salta ese mensaje.
create or replace function elius.siguiente_mensaje_demo()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_vertical text; v_slug text; v_d jsonb; v_guion jsonb; v_i int; v_total int;
  v_g jsonb; v_conv uuid; v_estado text; v_texto text;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  select slug, vertical into v_slug, v_vertical from platform.tenants where id = v_tenant;
  if v_slug not like 'demo-%' then raise exception 'Este negocio no es un caso de prueba'; end if;
  v_d := elius.datos_caso_demo(v_vertical);
  v_guion := v_d->'guion'; v_total := jsonb_array_length(v_guion);
  select valor::int into v_i from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_indice';

  loop
    if v_i >= v_total then
      return jsonb_build_object('terminado', true, 'indice', v_i, 'total', v_total);
    end if;
    v_g := v_guion -> v_i;
    select c.id, c.estado into v_conv, v_estado
    from elius.conversaciones c
    join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
    where c.tenant_id = v_tenant order by i.id_externo offset (v_g->>'conv')::int limit 1;
    exit when not (v_g->>'emisor' = 'eli' and v_estado in ('humano', 'pausa'));
    v_i := v_i + 1;
  end loop;

  v_texto := v_g->>'texto';
  insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, estado_entrega, procesado)
  values (v_tenant, v_conv, v_g->>'emisor', case when v_texto like '📎%' then 'imagen' else 'texto' end, v_texto,
          case when v_g->>'emisor' = 'cliente' then 'recibido' else 'entregado' end, true);
  v_i := v_i + 1;
  update elius.parametros_negocio set valor = v_i::text where tenant_id = v_tenant and clave = 'demo_indice';
  return jsonb_build_object('terminado', v_i >= v_total, 'indice', v_i, 'total', v_total,
                            'emisor', v_g->>'emisor', 'conversacion_id', v_conv);
end $$;

-- Vuelve a empezar la demostración del negocio de prueba actual
create or replace function elius.reiniciar_demo()
returns void language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id();
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  if not exists (select 1 from platform.tenants where id = v_tenant and slug like 'demo-%') then
    raise exception 'Este negocio no es un caso de prueba';
  end if;
  delete from elius.mensajes where tenant_id = v_tenant;
  update elius.conversaciones set estado = 'en_progreso', asignado_a = null where tenant_id = v_tenant;
  update elius.parametros_negocio set valor = '0' where tenant_id = v_tenant and clave = 'demo_indice';
end $$;

revoke execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() from public, anon;
grant execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() to authenticated;
comment on function platform.cargar_caso_demo(text) is 'Crea el negocio de prueba de un caso (restaurante/veterinaria/aerolinea) con catálogo e imágenes';
comment on function elius.siguiente_mensaje_demo() is 'Entrega el siguiente mensaje (de 20) del guion del caso de prueba';
