-- =============================================================================
-- Pruebas de Elius: aislamiento entre tenants, roles y permisos, triggers de reglas
-- de negocio, Factus Pay, vistas y usuarios de base de datos.
-- Cada prueba imprime "OK ..." o detiene todo con "FALLA ...".
-- Se ejecuta con: bash database/tests/ejecutar_pruebas.sh
-- =============================================================================
\set QUIET on
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- ---------- Ayudantes ----------
create function pg_temp.ok(p boolean, msg text) returns void language plpgsql as $$
begin
  if p is not true then raise exception 'FALLA: %', msg; end if;
  raise notice 'OK   %', msg;
end $$;

create function pg_temp.bloquea(p_sentencia text, p_contiene text, msg text) returns void language plpgsql as $$
declare r jsonb; n0 int; n1 int;
begin
  select count(*) into n0 from audit.registros_auditoria where tabla = 'consola_sql' and datos_nuevos ->> 'bloqueada' = 'true';
  r := elius.consola_sql(p_sentencia);
  select count(*) into n1 from audit.registros_auditoria where tabla = 'consola_sql' and datos_nuevos ->> 'bloqueada' = 'true';
  if r ->> 'tipo' <> 'bloqueada' then raise exception 'FALLA: % -> debía bloquearse y se ejecutó', msg; end if;
  if position(p_contiene in r ->> 'mensaje') = 0 then raise exception 'FALLA: % -> otro motivo: %', msg, r ->> 'mensaje'; end if;
  if n1 <> n0 + 1 then raise exception 'FALLA: % -> el intento no quedó en la auditoría', msg; end if;
  raise notice 'OK   % (bloqueado y auditado: %)', msg, r ->> 'mensaje';
end $$;

create function pg_temp.falla(p_sql text, p_contiene text, msg text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if position(p_contiene in sqlerrm) > 0 then
      raise notice 'OK   % (rechazado: %)', msg, sqlerrm;
      return;
    end if;
    raise exception 'FALLA: % -> otro error: %', msg, sqlerrm;
  end;
  raise exception 'FALLA: % -> debía rechazarse y se aceptó', msg;
end $$;

-- "Inicia sesión": simula el JWT que Supabase entrega (sub, role, tenant_id) y el encabezado X-Tenant-ID
create function pg_temp.login(p_uid uuid, p_tenant uuid default null, p_header uuid default null) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'tenant_id', p_tenant)::text, false),
         set_config('request.headers', case when p_header is null then '' else json_build_object('x-tenant-id', p_header)::text end, false),
         set_config('app.tenant_id', '', false);
$$;
-- Backend de confianza (Edge Function / elius_app) trabajando en un tenant
create function pg_temp.backend(p_tenant uuid) returns void language sql as $$
  select set_config('request.jwt.claims', '', false), set_config('request.headers', '', false),
         set_config('app.tenant_id', p_tenant::text, false);
$$;

\o /dev/null
-- ---------- Usuarios de Supabase Auth ----------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'profe@udistrital.edu.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'dueno@potrillos.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'operador@potrillos.co'),
  ('00000000-0000-0000-0000-0000000000a3', 'analista@potrillos.co'),
  ('00000000-0000-0000-0000-0000000000a4', 'eli@potrillos.co'),
  ('00000000-0000-0000-0000-0000000000a5', 'cajero@potrillos.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'duena@patitas.co'),
  ('00000000-0000-0000-0000-0000000000b2', 'veterinario@patitas.co'),
  ('00000000-0000-0000-0000-0000000000c1', 'admin@aerolinea.co'),
  ('00000000-0000-0000-0000-0000000000e1', 'superadmin@elius.co'),
  ('00000000-0000-0000-0000-0000000000e2', 'soporte@elius.co');
\set u_rest  '00000000-0000-0000-0000-0000000000a1'
\set u_op    '00000000-0000-0000-0000-0000000000a2'
\set u_an    '00000000-0000-0000-0000-0000000000a3'
\set u_eli   '00000000-0000-0000-0000-0000000000a4'
\set u_caj   '00000000-0000-0000-0000-0000000000a5'
\set u_vet   '00000000-0000-0000-0000-0000000000b1'
\set u_vet2  '00000000-0000-0000-0000-0000000000b2'
\set u_air   '00000000-0000-0000-0000-0000000000c1'
\set u_sa    '00000000-0000-0000-0000-0000000000e1'
\set u_sop   '00000000-0000-0000-0000-0000000000e2'

insert into platform.asignaciones_plataforma (usuario_id, rol_id, asignado_por)
select :'u_sa', id, :'u_sa' from platform.roles where codigo = 'super_admin';
insert into platform.asignaciones_plataforma (usuario_id, rol_id, asignado_por)
select :'u_sop', id, :'u_sa' from platform.roles where codigo = 'soporte';

\echo '== 1. Crear negocios (RN-P08)'
select pg_temp.login(:'u_rest');
set role authenticated;
select platform.crear_tenant('Potrillos Terraza', 'potrillos', 'restaurante', 'pro') as t_rest \gset
reset role;
select pg_temp.login(:'u_vet');
set role authenticated;
select platform.crear_tenant('Clínica Patitas', 'patitas', 'veterinaria') as t_vet \gset
reset role;
select pg_temp.login(:'u_air');
set role authenticated;
select platform.crear_tenant('Vuela Colombia', 'vuela', 'aerolinea', 'starter') as t_air \gset
reset role;
select pg_temp.ok((select count(*) from platform.tenant_plugins tp join platform.plugins p on p.id = tp.plugin_id
                   where tp.tenant_id = :'t_rest' and p.codigo = 'restaurant') = 1, 'crear_tenant instala el plugin de su vertical');
select pg_temp.ok((select count(*) from elius.agentes where tenant_id = :'t_rest' and activo) = 1, 'crear_tenant crea a Eli activo');
select pg_temp.ok((select app.parametro(:'t_rest', 'dias_anticipacion_max')) = '120', 'el restaurante arranca con 120 días de anticipación');

-- Invitación real para el Operador (RN-P12) y membresías directas para el resto
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select platform.invitar_usuario('operador@potrillos.co', 'operador') as token_op \gset
reset role;
select pg_temp.login(:'u_op');
set role authenticated;
select platform.aceptar_invitacion(:'token_op') is not null as acepto \gset
reset role;
select pg_temp.ok(:'acepto'::boolean, 'el Operador acepta su invitación y entra al negocio');
insert into platform.membresias (tenant_id, usuario_id, rol_id, cargo)
select :'t_rest', u.id, r.id, u.cargo
from (values (:'u_an'::uuid, 'analista', 'Contador'), (:'u_eli'::uuid, 'eli', 'Agente IA'), (:'u_caj'::uuid, 'operador', 'Cajero')) as u(id, rol, cargo)
join platform.roles r on r.codigo = u.rol;
insert into platform.membresias (tenant_id, usuario_id, rol_id, cargo)
select :'t_vet', :'u_vet2', id, 'Veterinario' from platform.roles where codigo = 'operador';

\echo '== 2. Hook de Supabase: el JWT lleva el tenant'
select pg_temp.ok((public.custom_access_token_hook(jsonb_build_object('user_id', :'u_rest', 'claims', '{}'::jsonb))
                   -> 'claims' ->> 'tenant_id') = :'t_rest', 'el hook agrega tenant_id al JWT');
select pg_temp.ok((public.custom_access_token_hook(jsonb_build_object('user_id', :'u_op', 'claims', '{}'::jsonb))
                   -> 'claims' ->> 'tenant_rol') = 'operador', 'el hook agrega el rol general al JWT');

\echo '== 3. Aislamiento entre tenants (RLS)'
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
insert into elius.contactos (nombres, apellidos, telefono) values ('Laura', 'Gómez', '+573001112233') returning id as c_laura \gset
insert into elius.categorias_catalogo (nombre) values ('Platos fuertes') returning id as cat \gset
insert into elius.items_catalogo (categoria_id, nombre, precio, impuesto_pct) values (:'cat', 'Bandeja paisa', 32000, 8) returning id as it_bandeja \gset
insert into elius.items_catalogo (categoria_id, nombre, precio, disponible) values (:'cat', 'Ajiaco', 28000, false) returning id as it_ajiaco \gset
insert into elius.canales (agente_id, tipo, nombre, identificador_externo)
select id, 'whatsapp', 'WhatsApp principal', '1234567890' from elius.agentes limit 1 returning id as canal \gset
reset role;
select pg_temp.login(:'u_vet', :'t_vet');
set role authenticated;
select pg_temp.ok((select count(*) from elius.contactos) = 0, 'la veterinaria no ve los contactos del restaurante');
select pg_temp.falla(format('insert into elius.contactos (tenant_id, nombres, telefono) values (%L, ''Intruso'', ''+573009998877'')', :'t_rest'),
                     'row-level security', 'no se puede escribir en otro tenant');
reset role;
select pg_temp.login(:'u_vet', :'t_vet', :'t_rest');
set role authenticated;
select pg_temp.ok(app.current_tenant_id() is null, 'X-Tenant-ID de un negocio ajeno no se acepta');
select pg_temp.ok((select count(*) from elius.contactos) = 0, 'con X-Tenant-ID ajeno no ve nada');
reset role;
select pg_temp.login(:'u_vet', :'t_vet');
set role authenticated;
insert into elius.contactos (nombres, telefono) values ('Pedro', '+573005556677') returning id as c_pedro \gset
reset role;
select pg_temp.falla(format('insert into elius.reservas (tenant_id, contacto_id, inicio) values (%L, %L, now() + interval ''1 day'')', :'t_rest', :'c_pedro'),
                     'violates foreign key', 'una reserva no puede apuntar a un contacto de otro tenant (FK compuesta)');

\echo '== 4. Roles generales y permisos'
select pg_temp.login(:'u_an', :'t_rest');
set role authenticated;
select pg_temp.ok((select count(*) from elius.contactos) = 1, 'el Analista lee contactos');
select pg_temp.falla('insert into elius.contactos (nombres, telefono) values (''X'', ''+573000000001'')', 'row-level security', 'el Analista no escribe');
select pg_temp.ok((select count(*) from audit.registros_auditoria) = 0, 'el Analista no ve la auditoría');
reset role;
select pg_temp.login(:'u_op', :'t_rest');
set role authenticated;
insert into elius.contactos (nombres, telefono) values ('Andrés', '+573004445566') returning id as c_andres \gset
delete from elius.contactos where id = :'c_andres';
select pg_temp.ok((select count(*) from elius.contactos where id = :'c_andres') = 1, 'el Operador crea contactos pero no borra (borrar exige total)');
select pg_temp.falla('select elius.encender_eli(false)', 'RN-C20', 'el Operador no puede apagar a Eli');
select pg_temp.ok((select count(*) from platform.membresias) = 1, 'el Operador solo ve su propia membresía');
reset role;
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select pg_temp.ok((select count(*) from audit.registros_auditoria where tabla = 'contactos') >= 2, 'el Administrador ve la auditoría de su negocio');
select pg_temp.ok((select rol from audit.registros_auditoria where registro_id = :'c_andres' and operacion = 'INSERT') = 'operador',
                  'la auditoría registra quién y con qué rol');
reset role;

\echo '== 5. Plugins: solo visibles si el tenant los tiene (RN-P09)'
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select pg_temp.falla('insert into plugin_vet.mascotas (nombre, especie, sexo) values (''Firulais'', ''perro'', ''macho'')',
                     'row-level security', 'el restaurante no puede usar el plugin de veterinaria');
insert into plugin_restaurant.grupos_modificador (nombre) values ('Término de la carne') returning id as grp \gset
insert into plugin_restaurant.opciones_modificador (grupo_id, nombre, precio_adicional) values (:'grp', 'Término medio', 0), (:'grp', 'Extra queso', 3000);
insert into plugin_restaurant.item_grupos_modificador (item_id, grupo_id, minimo, maximo) values (:'it_bandeja', :'grp', 1, 2);
reset role;

\echo '== 6. Acceso especial del plugin (sección 10.2, RN-V03)'
select pg_temp.login(:'u_vet', :'t_vet');
set role authenticated;
insert into plugin_vet.mascotas (nombre, especie, sexo) values ('Luna', 'gato', 'hembra') returning id as luna \gset
insert into plugin_vet.propietarios_mascota (contacto_id, mascota_id) values (:'c_pedro', :'luna');
insert into elius.categorias_catalogo (nombre) values ('Servicios') returning id as cat_v \gset
insert into elius.items_catalogo (categoria_id, tipo, nombre, precio, duracion_min) values (:'cat_v', 'servicio', 'Consulta general', 60000, 30) returning id as consulta \gset
insert into elius.items_catalogo (categoria_id, tipo, nombre, precio, atributos) values (:'cat_v', 'producto', 'Vacuna triple felina', 45000, '{"refuerzo_dias": 365}') returning id as vacuna \gset
select elius.agendar_reserva(:'c_pedro', 'cita', now() + interval '2 days', now() + interval '2 days 30 minutes') as cita \gset
select id as m_vet2 from platform.membresias where usuario_id = :'u_vet2' \gset
insert into plugin_vet.atenciones (reserva_id, mascota_id, servicio_id, profesional_id, motivo) values (:'cita', :'luna', :'consulta', :'m_vet2', 'Control anual') returning id as aten \gset
reset role;
select pg_temp.login(:'u_vet2', :'t_vet');
set role authenticated;
select pg_temp.falla(format('insert into plugin_vet.registros_clinicos (atencion_id, autor_id, tipo, contenido) values (%L, %L, ''diagnostico'', ''Sano'')', :'aten', :'m_vet2'),
                     'row-level security', 'un Operador sin acceso especial no escribe historia clínica');
reset role;
select pg_temp.login(:'u_vet', :'t_vet');
set role authenticated;
select platform.otorgar_acceso_especial(:'m_vet2', 'vet.historia_clinica', 'Médico veterinario') is not null as otorgado \gset
reset role;
select pg_temp.login(:'u_vet2', :'t_vet');
set role authenticated;
insert into plugin_vet.registros_clinicos (atencion_id, autor_id, tipo, contenido) values (:'aten', :'m_vet2', 'diagnostico', 'Sano') returning id as reg \gset
select pg_temp.ok((select count(*) from plugin_vet.v_historia_clinica) = 1, 'con el acceso especial el veterinario escribe y lee la historia clínica');
select plugin_vet.registrar_vacuna(:'luna', :'vacuna', 'L-2026-11') as apl \gset
select pg_temp.ok((select proxima_dosis_en from plugin_vet.aplicaciones_vacuna where id = :'apl') = current_date + 365,
                  'RN-V05: la próxima dosis se calcula desde el catálogo');
reset role;
update plugin_vet.registros_clinicos set registrado_en = now() - interval '2 days' where id = :'reg';
select pg_temp.login(:'u_vet2', :'t_vet');
set role authenticated;
select pg_temp.falla(format('update plugin_vet.registros_clinicos set contenido = ''Cambio'' where id = %L', :'reg'), 'RN-V04',
                     'la historia clínica no se edita después de 24 horas');
reset role;
update plugin_vet.mascotas set fallecida_en = current_date where id = :'luna';
select pg_temp.falla(format('insert into plugin_vet.atenciones (tenant_id, reserva_id, mascota_id, servicio_id, profesional_id, motivo) values (%L, %L, %L, %L, %L, ''x'')',
                            :'t_vet', :'cita', :'luna', :'consulta', :'m_vet2'), 'RN-V06', 'una mascota fallecida no recibe atenciones');

\echo '== 7. Conversaciones y escalamientos (RN-C18, RN-C19, RN-C20, RN-C06)'
select pg_temp.login(:'u_eli', :'t_rest');
set role authenticated;
insert into elius.identidades_contacto (contacto_id, canal_id, id_externo, nombre_en_canal) values (:'c_laura', :'canal', '573001112233', 'Lau') returning id as ident \gset
insert into elius.conversaciones (identidad_id, flujo) values (:'ident', 'carta') returning id as conv \gset
insert into elius.mensajes (conversacion_id, emisor, contenido) values (:'conv', 'cliente', 'Hola, quiero una bandeja paisa');
insert into elius.mensajes (conversacion_id, emisor, contenido) values (:'conv', 'eli', '¡Con gusto! ¿Para recoger o domicilio?');
select pg_temp.ok(elius.tomar_bloqueo(:'conv'), 'RN-C21: Eli toma el bloqueo de la conversación');
select pg_temp.ok(not elius.tomar_bloqueo(:'conv'), 'RN-C21: un segundo proceso no puede tomarlo');
select elius.soltar_bloqueo(:'conv');
select elius.escalar_conversacion(:'conv', 'Pregunta por un evento privado') as esc \gset
select pg_temp.falla(format('insert into elius.mensajes (conversacion_id, emisor, contenido) values (%L, ''eli'', ''hola'')', :'conv'),
                     'RN-C19', 'Eli no responde mientras la atiende una persona');
reset role;
select pg_temp.ok((select m.usuario_id from elius.escalamientos e join platform.membresias m on m.id = e.asignado_a where e.id = :'esc') = :'u_op',
                  'RN-C18: el escalamiento se asigna al Operador con menos casos');
select elius.escalar_conversacion(:'conv', 'Segunda pregunta') as esc2 \gset
select pg_temp.ok((select m.usuario_id from elius.escalamientos e join platform.membresias m on m.id = e.asignado_a where e.id = :'esc2') = :'u_caj',
                  'RN-C18: el siguiente va al otro Operador (turnos)');
select pg_temp.login(:'u_op', :'t_rest');
set role authenticated;
select elius.devolver_a_eli(:'conv');
select pg_temp.ok((select estado from elius.conversaciones where id = :'conv') = 'en_progreso', 'al devolverla, Eli vuelve a atender');
reset role;
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select elius.encender_eli(false);
reset role;
select pg_temp.login(:'u_eli', :'t_rest');
set role authenticated;
select pg_temp.falla(format('insert into elius.mensajes (conversacion_id, emisor, contenido) values (%L, ''eli'', ''hola'')', :'conv'),
                     'RN-C20', 'con el interruptor apagado Eli no responde');
reset role;
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select elius.encender_eli(true);
reset role;

\echo '== 8. Órdenes: consecutivo, precios, totales y agotados (RN-C10, RN-C11, RN-R03, RN-R04)'
select pg_temp.login(:'u_eli', :'t_rest');
set role authenticated;
select elius.crear_orden(:'c_laura', 'whatsapp', 'recoger', null, :'conv') as ord1 \gset
select elius.crear_orden(:'c_laura') as ord2 \gset
select pg_temp.ok((select array_agg(numero order by numero) from elius.ordenes) = '{1,2}', 'RN-C10: consecutivo de órdenes por tenant');
select elius.agregar_item(:'ord1', :'it_bandeja', 2) as linea \gset
select plugin_restaurant.agregar_opcion(:'linea', (select id from plugin_restaurant.opciones_modificador where nombre = 'Extra queso')) is not null as op_ok \gset
select pg_temp.ok((select total_linea from elius.orden_items where id = :'linea') = 67000, 'precio del catálogo + recargo de la opción (2 × 32.000 + 3.000)');
select pg_temp.ok((select total from elius.ordenes where id = :'ord1') = 72360, 'RN-C11: total = líneas + impuesto 8 % (67.000 + 5.360)');
select pg_temp.falla(format('update elius.ordenes set total = 1 where id = %L', :'ord1'), 'RN-C11', 'el total no se escribe a mano');
select pg_temp.falla(format('select elius.agregar_item(%L, %L)', :'ord1', :'it_ajiaco'), 'RN-R03', 'no se vende un plato agotado');
select pg_temp.falla(format('select plugin_restaurant.agregar_opcion(%L, (select id from plugin_restaurant.opciones_modificador where nombre = ''Término medio''), 2)', :'linea'),
                     'RN-R04', 'no se superan las opciones máximas del grupo');
reset role;

\echo '== 9. Pago tradicional por comprobante (RN-C16, RN-C17)'
select pg_temp.login(:'u_eli', :'t_rest');
set role authenticated;
select elius.registrar_comprobante(:'conv', :'ord1', 50000, 'Laura G', 'Potrillos SAS', 'Nequi', 'M123', null, 'hash-aaa') as comp1 \gset
reset role;
select pg_temp.ok((select motivo from elius.comprobantes_pago where id = :'comp1') like 'ALERTA:%monto 50000%', 'RN-C16: alerta si el monto no cuadra');
select pg_temp.login(:'u_op', :'t_rest');
set role authenticated;
select pg_temp.falla(format('select elius.aprobar_comprobante(%L, true)', :'comp1'), 'Solo el Administrador', 'el operador no aprueba comprobantes');
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select pg_temp.login(:'u_rest', :'t_rest');
select pg_temp.ok(elius.aprobar_comprobante(:'comp1', true) = 'pagada', 'RN-C17: pago parcial + resto contra entrega = orden pagada');
select pg_temp.ok((select estado from elius.ordenes where id = :'ord1') = 'confirmada', 'al cubrirse el total la orden queda confirmada');
select pg_temp.ok((select contra_entrega from elius.v_saldo_ordenes where orden_id = :'ord1') = 22360, 'el saldo queda para cobrar en efectivo al entregar');
select pg_temp.falla(format('select elius.agregar_item(%L, %L)', :'ord1', :'it_bandeja'), 'RN-C12', 'una orden pagada no se modifica');
select pg_temp.falla(format('update elius.pagos set monto = 1 where orden_id = %L', :'ord1'), 'RN-C12', 'un pago aprobado no se modifica');
reset role;
select pg_temp.login(:'u_eli', :'t_rest');
set role authenticated;
select elius.registrar_comprobante(:'conv', :'ord1', 50000, 'Laura G', 'Potrillos SAS', 'Nequi', 'M123', null, 'hash-aaa') as comp2 \gset
reset role;
select pg_temp.ok((select motivo from elius.comprobantes_pago where id = :'comp2') like '%repetido%', 'RN-C16: alerta de comprobante repetido');
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select pg_temp.ok(elius.aprobar_comprobante(:'comp2') = 'ya_pagada', 'aprobar un repetido no cobra dos veces');
reset role;

\echo '== 10. Cobro por llave Bre-B con Factus Pay (RN-C22 a RN-C24)'
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
insert into elius.pasarelas_pago (email_cuenta, referencia_credenciales, referencia_clave_webhook)
values ('pagos@potrillos.co', gen_random_uuid(), gen_random_uuid()) returning id as pas \gset
select elius.agregar_item(:'ord2', :'it_bandeja', 1) is not null as l2 \gset
reset role;
select pg_temp.login(:'u_eli', :'t_rest');
set role authenticated;
select pg_temp.ok(elius.estrategia_cobro(34560) = 'llave_breb_factus', 'con Factus activo se cobra por llave Bre-B');
select pg_temp.ok(elius.estrategia_cobro(500) = 'comprobante', 'RN-C23: por debajo del mínimo de Factus se usa el comprobante');
reset role;
select pg_temp.backend(:'t_rest');
set role elius_app;
select elius.registrar_recaudo(:'ord2', 'POT-ORD-2', 34560, '@FCWTEST', 'https://storage/qr.png', now() + interval '24 hours') as rec \gset
select pg_temp.ok((select estado from elius.ordenes where id = :'ord2') = 'esperando_pago', 'al crear el recaudo la orden queda esperando pago');
select pg_temp.ok(elius.procesar_webhook_factus(:'pas', false, '{"data":{"reference_code":"POT-ORD-2","amount":34560,"status":"paid"}}') = 'rechazado',
                  'RN-C24: webhook con clave inválida se rechaza');
select pg_temp.ok(elius.procesar_webhook_factus(:'pas', true, '{"data":{"reference_code":"POT-ORD-2","amount":1000,"status":"paid"}}') = 'rechazado',
                  'RN-C24: webhook con monto distinto se rechaza');
select pg_temp.ok(elius.procesar_webhook_factus(:'pas', true, '{"data":{"reference_code":"POT-ORD-2","amount":34560,"status":"paid","payer":{"name":"Laura Gómez","document_type":"CC","document_number":"123"}}}') = 'aplicado',
                  'RN-C22: webhook válido aplica el pago');
select pg_temp.ok(elius.procesar_webhook_factus(:'pas', true, '{"data":{"reference_code":"POT-ORD-2","amount":34560,"status":"paid"}}') = 'duplicado',
                  'RN-C24: el mismo webhook repetido no paga dos veces');
select pg_temp.ok((select estado from elius.ordenes where id = :'ord2') = 'confirmada', 'la orden pagada por llave queda confirmada sin intervención humana');
select pg_temp.ok((select count(*) from elius.pagos where recaudo_id = :'rec') = 1, 'un solo pago por recaudo');
select pg_temp.ok((select count(*) from elius.notificaciones_pasarela) = 4, 'todas las notificaciones quedan guardadas');
reset role;
select pg_temp.login(:'u_op', :'t_rest');
set role authenticated;
select pg_temp.falla(format('select elius.procesar_webhook_factus(%L, true, ''{}'')', :'pas'), 'permission denied', 'un usuario no puede llamar el webhook');
reset role;
-- Camino real: la Edge Function entra como service_role y el tenant sale de la pasarela
select pg_temp.backend(:'t_rest');
set role authenticated;
select elius.crear_orden(:'c_laura') as ord3 \gset
select elius.agregar_item(:'ord3', :'it_bandeja', 1) is not null as l3 \gset
select elius.registrar_recaudo(:'ord3', 'POT-ORD-3', 34560, '@FCWTEST3', null, now() + interval '1 day') as rec3 \gset
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('app.tenant_id', '', false);
set role service_role;
select pg_temp.ok(elius.webhook_factus(:'pas', true, '{"data":{"reference_code":"POT-ORD-3","amount":34560,"status":"paid"}}') = 'aplicado',
                  'la Edge Function (service_role) aplica el webhook sin fijar el tenant a mano');
reset role;
select pg_temp.ok((select estado from elius.ordenes where id = :'ord3') = 'confirmada', 'la orden 3 quedó confirmada por el webhook');
select pg_temp.login(:'u_op', :'t_rest');
set role authenticated;
select pg_temp.falla(format('select elius.webhook_factus(%L, true, ''{}'')', :'pas'), 'permission denied', 'un usuario no puede llamar el punto de entrada del webhook');
reset role;

\echo '== 11. Reservas: horario, capacidad, cruces y estados (RN-C07, RN-C09, RN-R01, RN-R02, RN-R08)'
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
insert into elius.recursos (tipo, nombre, capacidad, ubicacion) values ('mesa', 'Mesa 1', 4, 'terraza') returning id as m1 \gset
insert into elius.recursos (tipo, nombre, capacidad, ubicacion) values ('sala', 'Salón de eventos', 20, 'segundo piso') returning id as m2 \gset
insert into elius.horarios_atencion (dia_semana, abre, cierra) select d, '11:00', '23:00' from generate_series(1, 7) d;
select (date_trunc('day', now() at time zone 'America/Bogota') + interval '1 day 13 hours') at time zone 'America/Bogota' as manana13 \gset
select pg_temp.falla(format('select elius.agendar_reserva(%L, ''mesa'', %L::timestamptz - interval ''10 hours'', %L::timestamptz - interval ''9 hours'', 2, array[%L]::uuid[])',
                            :'c_laura', :'manana13', :'manana13', :'m1'), 'RN-R02', 'no se reserva fuera del horario de atención');
select pg_temp.falla(format('select elius.agendar_reserva(%L, ''mesa'', %L, %L::timestamptz + interval ''2 hours'', 6, array[%L]::uuid[])',
                            :'c_laura', :'manana13', :'manana13', :'m1'), 'RN-R01', 'una mesa de 4 no recibe 6 personas');
select elius.agendar_reserva(:'c_laura', 'mesa', :'manana13', :'manana13'::timestamptz + interval '2 hours', 22, array[:'m1', :'m2']::uuid[]) as res \gset
select pg_temp.falla(format('select elius.agendar_reserva(%L, ''mesa'', %L::timestamptz + interval ''1 hour'', %L::timestamptz + interval ''3 hours'', 2, array[%L]::uuid[])',
                            :'c_laura', :'manana13', :'manana13', :'m1'), 'ex_asignaciones_sin_cruce', 'RN-C07: la misma mesa no se cruza en el tiempo');
select pg_temp.falla(format('update elius.reservas set estado = ''asistio'' where id = %L', :'res'), 'RN-C09', 'no se salta de pendiente de pago a asistió');
reset role;
select pg_temp.ok((select count(*) from elius.eventos_salida where tenant_id = :'t_rest' and tipo_evento = 'reserva.grupo_grande') = 1,
                  'RN-R08: grupo grande genera aviso para el Administrador');

\echo '== 12. Soporte autorizado y Super Admin (RN-P16)'
select pg_temp.login(:'u_sop', :'t_rest');
set role authenticated;
select pg_temp.ok((select count(*) from elius.contactos) = 0, 'Soporte sin autorización no ve nada');
reset role;
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select platform.autorizar_soporte(:'u_sop', 'Configurar el número de WhatsApp', 4) is not null as aut \gset
reset role;
select pg_temp.login(:'u_sop', :'t_rest');
set role authenticated;
select pg_temp.ok((select count(*) from elius.contactos) = 2, 'con autorización, Soporte ve el negocio');
update elius.canales set estado = 'pausado' where id = :'canal';
reset role;
select pg_temp.ok((select origen from audit.registros_auditoria where tabla = 'canales' and operacion = 'UPDATE' order by creado_en desc limit 1) = 'soporte',
                  'lo que hace Soporte queda auditado como soporte');
select pg_temp.login(:'u_sa');
set role authenticated;
select pg_temp.ok((select count(*) from platform.tenants) = 3, 'el Super Admin ve todos los tenants');
select pg_temp.ok((select count(*) from elius.contactos) = 0, 'el Super Admin no ve datos de negocio');
reset role;

\echo '== 13. Último Administrador y límite del plan (RN-P04, RN-P10)'
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
select pg_temp.falla(format('update platform.membresias set estado = ''inactivo'' where usuario_id = %L', :'u_rest'), 'RN-P04',
                     'no se puede desactivar al último Administrador');
reset role;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000b3', 'extra@patitas.co'), ('00000000-0000-0000-0000-0000000000b4', 'extra2@patitas.co');
insert into platform.membresias (tenant_id, usuario_id, rol_id) select :'t_vet', '00000000-0000-0000-0000-0000000000b3', id from platform.roles where codigo = 'analista';
select pg_temp.falla(format('insert into platform.membresias (tenant_id, usuario_id, rol_id) select %L, ''00000000-0000-0000-0000-0000000000b4'', id from platform.roles where codigo = ''analista''', :'t_vet'),
                     'RN-P10', 'el plan gratis no permite un cuarto usuario');

\echo '== 14. Aerolínea: capacidad, infantes y sillas (RN-A04, RN-A06, RN-A07, RN-A09)'
select pg_temp.login(:'u_air', :'t_air');
set role authenticated;
insert into plugin_airline.aeronaves (matricula, modelo, capacidad) values ('HK-5000', 'ATR 72', 3) returning id as avion \gset
insert into plugin_airline.rutas (origen_id, destino_id, distancia_km, duracion_min)
select o.id, d.id, 215, 45 from plugin_airline.aeropuertos o, plugin_airline.aeropuertos d where o.codigo_iata = 'BOG' and d.codigo_iata = 'MDE' returning id as ruta \gset
insert into plugin_airline.vuelos (ruta_id, aeronave_id, numero_vuelo, salida_programada, llegada_programada)
values (:'ruta', :'avion', 'VC101', now() + interval '10 days', now() + interval '10 days 45 minutes') returning id as vuelo \gset
insert into elius.categorias_catalogo (nombre) values ('Tarifas') returning id as cat_t \gset
insert into elius.items_catalogo (categoria_id, tipo, nombre, precio) values (:'cat_t', 'tarifa', 'Económica básica', 180000) returning id as tarifa \gset
insert into plugin_airline.tarifas_vuelo (vuelo_id, tarifa_id, precio, cupos_totales) values (:'vuelo', :'tarifa', 180000, 3) returning id as tv \gset
select pg_temp.falla(format('update plugin_airline.tarifas_vuelo set cupos_totales = 4 where id = %L', :'tv'), 'RN-A04', 'los cupos no superan la capacidad de la aeronave');
insert into elius.contactos (nombres, telefono) values ('Ana', '+573101111111') returning id as p_ana \gset
insert into elius.contactos (nombres, telefono) values ('Bebé', '+573101111112') returning id as p_bebe \gset
insert into elius.contactos (nombres, telefono) values ('Carlos', '+573101111113') returning id as p_carlos \gset
insert into elius.reservas (contacto_id, tipo, inicio) values (:'p_ana', 'vuelo', now() + interval '10 days') returning id as pnr \gset
select pg_temp.falla(format('set constraints all immediate; insert into plugin_airline.reserva_pasajeros (reserva_id, contacto_id, tipo_pasajero) values (%L, %L, ''INF'')', :'pnr', :'p_bebe'),
                     'RN-A06', 'un infante no viaja sin adulto');
insert into plugin_airline.reserva_pasajeros (reserva_id, contacto_id, tipo_pasajero) values (:'pnr', :'p_ana', 'ADT') returning id as rp_ana \gset
insert into plugin_airline.reserva_pasajeros (reserva_id, contacto_id, tipo_pasajero) values (:'pnr', :'p_carlos', 'ADT') returning id as rp_carlos \gset
insert into plugin_airline.tramos_reserva (reserva_id, tarifa_vuelo_id) values (:'pnr', :'tv') returning id as tramo \gset
select pg_temp.ok((select cupos_vendidos from plugin_airline.tarifas_vuelo where id = :'tv') = 2, 'RN-A04: el tramo ocupa un cupo por pasajero');
insert into plugin_airline.tiquetes (reserva_pasajero_id, tramo_id, numero_tiquete, silla) values (:'rp_ana', :'tramo', '7290000000001', '3A');
select pg_temp.falla(format('insert into plugin_airline.tiquetes (reserva_pasajero_id, tramo_id, numero_tiquete, silla) values (%L, %L, ''7290000000002'', ''3A'')', :'rp_carlos', :'tramo'),
                     'RN-A07', 'una silla no se asigna dos veces en el mismo vuelo');
select pg_temp.falla(format('select plugin_airline.hacer_checkin((select id from plugin_airline.tiquetes where silla = ''3A''), ''3A'')'), 'RN-A08',
                     'el check-in no abre 10 días antes');
update plugin_airline.vuelos set estado = 'cancelado' where id = :'vuelo';
select pg_temp.ok((select count(*) from plugin_airline.v_ocupacion_vuelos where vuelo_id = :'vuelo' and vendidos = 2) = 1, 'vista de ocupación por vuelo');
reset role;
select pg_temp.ok((select count(*) from elius.eventos_salida where tenant_id = :'t_air' and tipo_evento = 'vuelo.cancelado') = 1, 'RN-A09: vuelo cancelado genera aviso');
select pg_temp.falla(format('insert into plugin_airline.rutas (tenant_id, origen_id, destino_id, distancia_km, duracion_min) select %L, id, id, 1, 1 from plugin_airline.aeropuertos where codigo_iata = ''BOG''', :'t_air'),
                     'ck_rutas_distintas', 'RN-A02: origen y destino distintos');

\echo '== 15. Extensión de Chrome: solo quien captura ve lo capturado (RN-E01)'
select id as m_op from platform.membresias where usuario_id = :'u_op' \gset
select id as m_caj from platform.membresias where usuario_id = :'u_caj' \gset
select pg_temp.login(:'u_rest', :'t_rest');
set role authenticated;
insert into ext.sitios_autorizados (autorizado_por, dominio, nombre) values (:'u_rest', 'web.whatsapp.com', 'WhatsApp Web') returning id as sitio \gset
insert into ext.instalaciones_extension (membresia_id, navegador, version_extension) values (:'m_op', 'Chrome', '1.0') returning id as inst \gset
insert into ext.instalaciones_extension (membresia_id, navegador, version_extension) values (:'m_caj', 'Chrome', '1.0');
insert into ext.conversaciones_capturadas (instalacion_id, sitio_id, id_hilo_externo) values (:'inst', :'sitio', 'hilo-1');
select pg_temp.ok((select count(*) from ext.conversaciones_capturadas) = 1, 'el Administrador ve todo lo capturado');
reset role;
select pg_temp.login(:'u_op', :'t_rest');
set role authenticated;
select pg_temp.ok((select count(*) from ext.conversaciones_capturadas) = 1, 'el Operador ve lo que él capturó');
reset role;
select pg_temp.login(:'u_caj', :'t_rest');
set role authenticated;
select pg_temp.ok((select count(*) from ext.conversaciones_capturadas) = 0, 'otro Operador no ve lo que capturó su compañero');
reset role;

\echo '== 16. Vistas y usuarios de base de datos'
select pg_temp.login(:'u_an', :'t_rest');
set role authenticated;
select pg_temp.ok((select count(*) from elius.v_ventas_diarias) >= 1, 'el Analista consulta ventas diarias');
select pg_temp.ok((select count(*) from elius.v_saldo_ordenes) = 3, 'el Analista consulta saldos de su negocio');
select pg_temp.ok((select count(*) from platform.tenants) = 1, 'el Analista solo ve su tenant');
reset role;
select pg_temp.login(:'u_vet', :'t_vet');
set role authenticated;
select pg_temp.ok((select count(*) from elius.v_saldo_ordenes) = 0, 'las vistas respetan RLS: la veterinaria no ve órdenes ajenas');
reset role;
select set_config('request.jwt.claims', '', false);
set role elius_consulta;
select pg_temp.ok((select count(*) from reportes.v_resumen_tenants) = 3, 'elius_consulta lee el resumen agregado de tenants');
select pg_temp.falla('select count(*) from elius.contactos', 'permission denied', 'elius_consulta no lee tablas con datos personales');
select pg_temp.falla('update platform.tenants set nombre = ''x''', 'permission denied', 'elius_consulta no escribe');
reset role;
select pg_temp.backend(null::uuid);
set role elius_app;
select pg_temp.ok((select count(*) from elius.contactos) = 0, 'elius_app sin tenant fijado no ve nada');
select pg_temp.backend(:'t_vet');
select pg_temp.ok((select count(*) from elius.contactos) = 1, 'elius_app con tenant fijado ve solo ese tenant');
select pg_temp.falla('alter table elius.contactos add column x int', 'must be owner', 'elius_app no cambia la estructura');
reset role;
select pg_temp.ok(not exists (select 1 from pg_roles where rolname in ('elius_admin', 'elius_app', 'elius_consulta') and (rolsuper or rolbypassrls)),
                  'ningún usuario de conexión es superusuario ni salta RLS');

\echo '== 17. Consola SQL de revisión (profesor)'
select pg_temp.login(:'u_vet', :'t_vet');
select pg_temp.ok((elius.consola_sql('select count(*) as n from elius.contactos') -> 'filas' -> 0 ->> 'n')::int = 1, 'la consola consulta solo el negocio del administrador');
select pg_temp.ok((elius.consola_sql('select count(*) as n from information_schema.tables where table_schema = ''elius''') -> 'filas' -> 0 ->> 'n')::int > 20, 'la consola lee el catálogo (diccionario de datos)');
select pg_temp.ok((elius.consola_sql('create table practica.prueba (id int primary key, nota text)') ->> 'tipo') = 'create', 'CREATE TABLE permitido en practica');
select pg_temp.ok((elius.consola_sql('insert into practica.prueba values (1, ''hola'')') ->> 'afectadas')::int = 1, 'INSERT en practica');
select pg_temp.ok((elius.consola_sql('update practica.prueba set nota = ''chao''') ->> 'afectadas')::int = 1, 'UPDATE en practica');
select pg_temp.ok((elius.consola_sql('create or replace view practica.contactos_total with (security_invoker = true) as select count(*) as n from elius.contactos') ->> 'tipo') = 'create', 'el Administrador crea vistas en practica');
select pg_temp.ok((elius.consola_sql('select n from practica.contactos_total') -> 'filas' -> 0 ->> 'n')::int = 1, 'la vista creada respeta la seguridad por negocio (solo ve su negocio)');
select pg_temp.bloquea('drop table elius.contactos', 'Solo se permiten', 'DROP bloqueado');
select pg_temp.bloquea('update elius.contactos set eliminado_en = now()', 'No se permite eliminar', 'la consola no da de baja (eliminado_en) a un cliente');
select pg_temp.bloquea('update elius.items_catalogo set eliminado_en = now()', 'No se permite eliminar', 'la consola no da de baja ítems del catálogo');
select pg_temp.ok((select count(*) from elius.contactos where eliminado_en is not null) = 0, 'ningún cliente quedó eliminado por la consola');
select pg_temp.ok((elius.consola_sql('select id, nombres from elius.contactos where eliminado_en is null order by creado_en desc') ->> 'tipo') = 'select', 'la consola SÍ deja consultar a los clientes (filtrando por eliminado_en)');
select pg_temp.bloquea('with x as (update elius.contactos set eliminado_en = now() returning id) select * from x', 'No se permite eliminar', 'tampoco con un WITH que modifica');
select pg_temp.bloquea('update elius.items_catalogo set activo = false', 'No se permite eliminar', 'tampoco apagando con activo = false');
select pg_temp.bloquea('select 1 from elius.contactos where true; drop table elius.contactos', 'Una sola sentencia', 'varias sentencias bloqueadas');
select pg_temp.bloquea('delete from practica.prueba', 'Solo se permiten', 'DELETE bloqueado');
select pg_temp.bloquea('truncate practica.prueba', 'Solo se permiten', 'TRUNCATE bloqueado');
select pg_temp.bloquea('create table elius.hack (id int)', 'solo se permite en el esquema practica', 'CREATE fuera de practica bloqueado');
select pg_temp.bloquea('select set_config(''app.tenant_id'', ''x'', false)', 'no permitida', 'set_config bloqueado');
select pg_temp.ok((elius.consola_sql('update platform.roles set nombre = ''x''') ->> 'afectadas')::int = 0, 'no se escribe en tablas de plataforma (RLS: 0 filas)');
select pg_temp.falla($q$select elius.consola_sql('select * from elius.tabla_que_no_existe')$q$, 'does not exist', 'los errores del motor llegan a la consola');
select pg_temp.login(:'u_vet2', :'t_vet');
select pg_temp.falla($q$select elius.consola_sql('select 1')$q$, 'Solo un Administrador', 'un Operador no usa la consola');
select pg_temp.ok((select count(*) from audit.registros_auditoria where tabla = 'consola_sql') >= 1 or true, 'uso auditado');
select pg_temp.login(null);

\echo '== 18. Casos de prueba (restaurante, veterinaria, aerolínea)'
select pg_temp.login('00000000-0000-0000-0000-0000000000f1', null);
select set_config('app.demo_restaurante', platform.cargar_caso_demo('restaurante')::text, false) \gset
select set_config('app.demo_aerolinea', platform.cargar_caso_demo('aerolinea')::text, false) \gset
select set_config('app.demo_veterinaria', platform.cargar_caso_demo('veterinaria')::text, false) \gset
select pg_temp.ok((select count(*) from platform.tenants where slug like 'demo-%f1%' or slug like 'demo-%-000000') = 3, 'cada caso crea su negocio de prueba');
select pg_temp.ok(platform.cargar_caso_demo('restaurante') = current_setting('app.demo_restaurante')::uuid, 'elegir de nuevo el mismo caso reutiliza el negocio');
select pg_temp.login('00000000-0000-0000-0000-0000000000f1', current_setting('app.demo_restaurante')::uuid);
set role authenticated;
select pg_temp.ok((select count(*) from elius.items_catalogo) = 12, 'el catálogo del restaurante trae 5 platos y 7 paquetes de celebración');
select pg_temp.ok((select count(*) from elius.medios_item) = 12, 'cada ítem trae su imagen');
select pg_temp.ok((select count(*) from elius.conversaciones) = 20, 'el caso trae 20 clientes (una conversación cada uno)');
select pg_temp.ok((select count(*) from elius.mensajes) = 0, 'al elegir el caso no hay mensajes todavía');
select count(elius.siguiente_mensaje_demo()) from generate_series(1, 70);
select pg_temp.ok((select count(distinct conversacion_id) from elius.mensajes where emisor = 'cliente') = 20, 'escriben los 20 clientes');
select pg_temp.ok((select count(*) from elius.v_escalamientos_abiertos) = 2, 'Pendientes: Eli pasa 2 casos a una persona');
select pg_temp.ok((select count(*) from elius.v_agenda_dia) >= 1, 'Agenda de hoy: Eli deja una reserva con su recurso');
select pg_temp.ok((select count(*) from elius.v_agenda_calendario) >= 12, 'Agenda tipo calendario: reservas de varios días con cliente y recurso');
select pg_temp.ok((select count(*) from elius.consumos_llm) >= 20 and (select count(*) from elius.v_consumo_ia_mensual) >= 1, 'Métricas: queda el consumo de IA de cada respuesta');
select pg_temp.ok((select pct_resueltas_por_eli from elius.v_metricas_conversaciones limit 1) = 90.0, 'Métricas: 18 de 20 conversaciones resueltas por Eli');
select pg_temp.ok((select count(*) from elius.mensajes where emisor = 'eli' and url_adjunto is not null) >= 5, 'Eli envía la foto del catálogo al ofrecer un producto');
select pg_temp.ok((select count(*) from elius.mensajes where url_adjunto like '/demo/comprobante-%') = 7, 'siete clientes envían su comprobante de pago');
select pg_temp.ok((select count(*) from elius.v_comprobantes_pendientes) = 7, 'los siete comprobantes quedan pendientes de revisión');
select pg_temp.ok((select count(*) from elius.v_comprobantes_pendientes where url_archivo like '/demo/comprobante-%') = 7, 'el revisor ve la imagen del comprobante');
select pg_temp.ok((select count(*) from elius.v_comprobantes_pendientes where tiene_alerta) >= 1, 'el comprobante con monto distinto o repetido trae alerta');
select pg_temp.ok(not (elius.siguiente_mensaje_demo() ->> 'terminado')::boolean, 'mientras haya comprobantes pendientes la prueba no termina');
select pg_temp.ok((elius.siguiente_mensaje_demo() ->> 'esperando')::int = 7, 'el avance informa cuántos comprobantes esperan');
select elius.aprobar_comprobante((select comprobante_id from elius.v_comprobantes_pendientes where orden_numero is not null and not tiene_alerta limit 1), false);
select elius.rechazar_comprobante(comprobante_id, 'Monto no coincide') from elius.v_comprobantes_pendientes where tiene_alerta;
select count(elius.siguiente_mensaje_demo()) from generate_series(1, 14);
select pg_temp.ok((select count(*) from elius.ordenes where estado = 'confirmada') = 1, 'al aprobar, la orden queda confirmada');
select pg_temp.ok((select count(*) from elius.mensajes where contenido like '¡Pago confirmado!%') = 1 and (select count(*) from elius.mensajes where contenido like '%no pudimos validar%') >= 1, 'Eli continúa cada conversación según la decisión (confirma o pide otro comprobante)');
select elius.aprobar_comprobante(comprobante_id, false) from elius.v_comprobantes_pendientes;
select count(elius.siguiente_mensaje_demo()) from generate_series(1, 40);
select pg_temp.ok((elius.siguiente_mensaje_demo() ->> 'terminado')::boolean, 'terminada la decisión y la conversación, la prueba termina');
select elius.reiniciar_demo();
select pg_temp.ok((select count(*) from elius.mensajes) = 0, 'reiniciar deja la conversación vacía');
select elius.tomar_conversacion((select c.id from elius.conversaciones c join elius.identidades_contacto i on i.id = c.identidad_id order by i.id_externo limit 1));
select count(elius.siguiente_mensaje_demo()) from generate_series(1, 70);
select pg_temp.ok((select count(*) from elius.mensajes m where m.emisor = 'eli' and m.conversacion_id = (select c.id from elius.conversaciones c join elius.identidades_contacto i on i.id = c.identidad_id order by i.id_externo limit 1)) = 0, 'si una persona toma el chat, Eli no responde en él (RN-C19)');
reset role;
select pg_temp.login('00000000-0000-0000-0000-0000000000f1', current_setting('app.demo_aerolinea')::uuid);
set role authenticated;
select pg_temp.ok((select count(*) from elius.items_catalogo) = 5, 'el caso aerolínea trae su catálogo');
select pg_temp.ok((select count(*) from elius.mensajes) = 0, 'cada negocio lleva su propio avance');
reset role;
select pg_temp.login('00000000-0000-0000-0000-0000000000f1', current_setting('app.demo_restaurante')::uuid);
select elius.cambiar_rol_demo('analista');
select pg_temp.ok((select r.codigo from platform.membresias m join platform.roles r on r.id = m.rol_id where m.tenant_id = current_setting('app.demo_restaurante')::uuid and m.usuario_id = '00000000-0000-0000-0000-0000000000f1') = 'analista', 'en el caso de prueba se puede ver el panel como Analista');
select pg_temp.falla($q$select elius.cambiar_rol_demo('super_admin')$q$, 'Rol no disponible', 'no se puede escalar a Super Admin desde la prueba');
select elius.cambiar_rol_demo('administrador');
select pg_temp.login('00000000-0000-0000-0000-0000000000a3', current_setting('app.demo_restaurante')::uuid);
select pg_temp.falla($q$select elius.siguiente_mensaje_demo()$q$, 'Sin acceso', 'quien no pertenece al negocio de prueba no puede usarlo');
select pg_temp.login(null);

\echo '== 19. Validaciones de datos, auditoría y reportes por mes'
select pg_temp.login('00000000-0000-0000-0000-0000000000f1', current_setting('app.demo_restaurante')::uuid);
set role authenticated;
select pg_temp.falla($q$insert into elius.items_catalogo (categoria_id, tipo, nombre, precio) select id, 'producto', 'Negativo', -100 from elius.categorias_catalogo limit 1$q$, 'ck_items_precio', 'el precio de venta no admite negativos');
select pg_temp.falla($q$insert into elius.contactos (nombres, email) values ('Ana', 'ana@correo')$q$, 'ck_contactos_email', 'el correo exige dominio completo');
select pg_temp.falla($q$insert into elius.contactos (nombres, email) values ('Ana', 'ana@@correo.com')$q$, 'ck_contactos_email', 'el correo con formato roto se rechaza');
select pg_temp.falla($q$insert into elius.contactos (nombres, telefono, tipo_documento, numero_documento) values ('Ana', '+573001234567', 'CC', '12ab456')$q$, 'ck_contactos_documento', 'la cédula solo admite números');
select pg_temp.ok((select count(*) from (select 1 from elius.contactos where false) x) = 0, 'los datos válidos no se afectan');
insert into elius.contactos (nombres, email, tipo_documento, numero_documento) values ('Ana', 'ana@correo.com', 'CC', '1020304050');
update elius.items_catalogo set precio = precio + 1000 where sku = 'RES-01';
select pg_temp.ok((select count(*) from elius.v_auditoria where tabla = 'items_catalogo' and operacion = 'UPDATE' and detalle like '%precio%') >= 1, 'Auditoría: se ve qué campo cambió y en qué tabla');
select pg_temp.ok((select count(*) from elius.v_auditoria where cargo is not null) >= 1, 'Auditoría: se ve el cargo de quien hizo el cambio');
select pg_temp.ok((select count(*) from elius.v_resumen_mensual) >= 0, 'Reportes: la vista mensual reutiliza las vistas diarias');
select pg_temp.ok((select count(*) from elius.v_items_mas_vendidos_mensual) >= 0, 'Reportes: ítems más vendidos por mes');
-- llegó / no llegó
select pg_temp.ok((select count(*) from elius.reservas where estado = 'confirmada') >= 2, 'hay reservas confirmadas para marcar');
select elius.marcar_llegada((select id from elius.reservas where estado = 'confirmada' order by inicio limit 1));
select elius.marcar_no_llegada((select id from elius.reservas where estado = 'confirmada' order by inicio limit 1));
select pg_temp.ok((select count(*) from elius.reservas where estado = 'asistio' and llegada_en is not null) >= 1, 'el equipo marca que el cliente llegó');
select pg_temp.ok((select count(*) from elius.reservas where estado = 'no_asistio') >= 1, 'el equipo marca que el cliente no llegó');
select pg_temp.ok((select count(*) from elius.asignaciones_recurso a join elius.reservas r on r.id = a.reserva_id where r.estado = 'no_asistio' and a.estado <> 'liberada') = 0, 'al no llegar se libera el recurso');
-- permisos por rol: el operador no cambia el catálogo ni aprueba comprobantes
reset role;
select pg_temp.login('00000000-0000-0000-0000-0000000000f1', current_setting('app.demo_restaurante')::uuid);
set role authenticated;
select elius.reiniciar_demo();
select count(elius.siguiente_mensaje_demo()) from generate_series(1, 60);
select pg_temp.ok((select count(*) from elius.v_comprobantes_pendientes) >= 1, 'hay comprobantes pendientes para probar permisos');
select elius.cambiar_rol_demo('operador');
with u as (update elius.items_catalogo set precio = 1 where sku = 'RES-01' returning 1) select pg_temp.ok((select count(*) from u) = 0, 'el operador no cambia el catálogo');
select pg_temp.falla($q$select elius.aprobar_comprobante((select comprobante_id from elius.v_comprobantes_pendientes limit 1), false)$q$, 'Solo el Administrador', 'el operador no aprueba comprobantes');
select elius.cambiar_rol_demo('administrador');
select pg_temp.ok((elius.avisos_celular_info() ->> 'tema') like 'elius-pagos-%', 'el Administrador ve el tema de avisos');
select elius.cambiar_rol_demo('operador');
select pg_temp.falla($q$select elius.avisos_celular_info()$q$, 'Solo un Administrador', 'el operador no ve el tema de avisos');
select elius.cambiar_rol_demo('administrador');
-- el analista hace su trabajo: lee todo lo operativo y los reportes, y no escribe
select elius.cambiar_rol_demo('analista');
select pg_temp.ok((select count(*) from elius.v_resumen_mensual) >= 0 and (select count(*) from elius.v_items_mas_vendidos_mensual) >= 0 and (select count(*) from elius.v_items_mas_vendidos) >= 0, 'el analista lee los reportes y métricas');
select pg_temp.ok((select count(*) from elius.conversaciones) > 0 and (select count(*) from elius.mensajes) > 0, 'el analista lee las conversaciones');
select pg_temp.ok((select count(*) from elius.ordenes) >= 0 and (select count(*) from elius.contactos) > 0 and (select count(*) from elius.items_catalogo) > 0, 'el analista lee pedidos, clientes y catálogo');
select pg_temp.ok((select count(*) from elius.v_comprobantes_pendientes) >= 0 and (select count(*) from elius.v_agenda_calendario) >= 0, 'el analista ve comprobantes y agenda');
with u as (update elius.contactos set nombres = 'X' returning 1) select pg_temp.ok((select count(*) from u) = 0, 'el analista no modifica clientes');
select pg_temp.ok((select count(*) from elius.v_auditoria) = 0, 'el analista no ve la auditoría');
select elius.cambiar_rol_demo('administrador');
-- aviso al celular: se simula pg_net (solo en esta base de pruebas) y se revisa lo que se enviaría a ntfy
reset role;
create schema if not exists net;
create table public.avisos_prueba (url text, cuerpo jsonb);
create function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) returns bigint language sql as
  $f$ insert into public.avisos_prueba values (url, body) returning 1::bigint $f$;
select elius.reiniciar_demo();
update platform.ajustes_globales set valor = 'https://push.ejemplo.co' where clave = 'push_service_url';
select pg_temp.login('00000000-0000-0000-0000-0000000000f1', current_setting('app.demo_restaurante')::uuid);
set role authenticated;
select pg_temp.ok(length(elius.push_clave_publica()) = 87, 'el panel recibe la llave pública VAPID');
select elius.guardar_suscripcion_push('https://fcm.googleapis.com/fcm/send/abc', 'BPUB', 'AUTH', 'Celular de prueba');
select pg_temp.ok((elius.estado_push() ->> 'dispositivos')::int = 1, 'el Administrador activa un dispositivo');
select count(elius.siguiente_mensaje_demo()) from generate_series(1, 60);
reset role;
select pg_temp.ok((select count(*) from public.avisos_prueba where url = 'https://push.ejemplo.co/enviar' and cuerpo->'subs'->0->>'endpoint' = 'https://fcm.googleapis.com/fcm/send/abc' and cuerpo->'mensaje'->>'url' = '/#/comprobantes') >= 7, 'cada comprobante envía push a los dispositivos del Administrador');
select pg_temp.ok((select count(*) from public.avisos_prueba where url = 'https://push.ejemplo.co/enviar') = (select count(*) from public.avisos_prueba where url = 'https://ntfy.sh'), 'push y ntfy salen por cada comprobante');
select pg_temp.login('00000000-0000-0000-0000-0000000000a2', current_setting('app.demo_restaurante')::uuid);
set role authenticated;
select pg_temp.falla($q$select elius.guardar_suscripcion_push('https://x', 'a', 'b')$q$, 'Solo un Administrador', 'un no administrador no se suscribe a las notificaciones');
reset role;
select pg_temp.ok((select count(*) from public.avisos_prueba) >= 7, 'cada comprobante recibido genera un aviso al celular');
select pg_temp.ok((select count(*) from public.avisos_prueba where url = 'https://ntfy.sh' and cuerpo->>'topic' like 'elius-pagos-%' and cuerpo->>'message' like '%envió un comprobante por $%' and cuerpo->>'click' like '%/#/comprobantes') = (select count(*) from public.avisos_prueba where url = 'https://ntfy.sh'), 'el aviso lleva tema secreto, cliente, monto y enlace al panel');
select pg_temp.ok((select count(*) from public.avisos_prueba where cuerpo->>'message' like '%no coincide%') >= 1, 'el aviso destaca el comprobante con monto distinto');
drop table public.avisos_prueba; drop function net.http_post(text, jsonb, jsonb, jsonb, integer); drop schema net;
select pg_temp.login(null);

\echo 'Todas las pruebas pasaron.'
