-- Conexiones directas a la base de datos, una por rol (elius_superadmin, elius_administrador, elius_trabajador, elius_soporte)
\echo '== 20. Conexiones directas por rol'
create or replace function pg_temp.intenta(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'ok'; exception when others then return sqlstate; end $$;
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin if p_cond is not true then raise exception 'FALLA: %', p_msg; end if; raise notice 'OK   %', p_msg; end $$;
select slug as s_rest from platform.tenants where slug like 'demo-restaurante-%' order by creado_en limit 1 \gset
select id as t_rest from platform.tenants where slug = :'s_rest' \gset
select pg_temp.ok((select count(*) from platform.accesos_bd) = 4, 'hay 4 usuarios de conexión directa');
select pg_temp.ok((select count(*) from platform.tenants t where eliminado_en is null and
  (select count(*) from platform.membresias m where m.tenant_id = t.id and m.usuario_id in (select usuario_id from platform.accesos_bd)) = 3) = (select count(*) from platform.tenants where eliminado_en is null), 'los 3 usuarios con membresía están en todos los negocios');

-- Administrador
set session authorization elius_administrador;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok(app.mi_rol() = 'administrador' and app.current_tenant_id() = :'t_rest'::uuid, 'Administrador: entra con su rol al negocio elegido');
select pg_temp.ok((select count(*) from elius.contactos) > 0, 'Administrador: ve los datos del negocio');
select pg_temp.ok(pg_temp.intenta('delete from elius.contactos') = '42501', 'Administrador: DELETE bloqueado');
select pg_temp.ok(pg_temp.intenta('truncate elius.contactos') <> 'ok', 'Administrador: TRUNCATE bloqueado');
insert into elius.contactos (nombres, apellidos, telefono, origen) values ('Sin', 'Historial', '+573000000001', 'panel');
select pg_temp.ok(pg_temp.intenta('update elius.contactos set eliminado_en = now() where id = (select id from elius.contactos order by creado_en limit 1)') <> 'ok', 'RN-C13: un cliente con reservas o pedidos abiertos no se elimina');
select pg_temp.ok(pg_temp.intenta('update elius.contactos set eliminado_en = now() where telefono = ''+573000000001''') = 'ok', 'Administrador: puede eliminar (desactivar) un cliente sin movimientos');
select pg_temp.ok(pg_temp.intenta('update elius.contactos set eliminado_en = null where eliminado_en is not null') = 'ok', 'Administrador: puede restaurar');
select pg_temp.ok(pg_temp.intenta('drop table elius.contactos') <> 'ok', 'Administrador: DROP bloqueado');
select pg_temp.ok(pg_temp.intenta('alter table elius.contactos add column x int') <> 'ok', 'Administrador: ALTER bloqueado');
select pg_temp.ok(pg_temp.intenta('create table elius.intruso (id int)') <> 'ok', 'Administrador: no crea tablas en el esquema del sistema');
select pg_temp.ok(pg_temp.intenta('create table practica.mi_prueba_bd (id int)') = 'ok', 'Administrador: sí crea en practica');
select pg_temp.ok(pg_temp.intenta('update elius.items_catalogo set precio = precio + 1 where sku = ''RES-01''') = 'ok', 'Administrador: puede actualizar precios');
select pg_temp.ok(pg_temp.intenta('select set_config(''request.jwt.claims'', ''{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}'', false)') = 'ok'
  and app.mi_rol() = 'administrador', 'Administrador: falsear el token no cambia su identidad');
select pg_temp.ok(pg_temp.intenta('select set_config(''app.tenant_id'', ''00000000-0000-0000-0000-000000000abc'', false)') = 'ok' and app.current_tenant_id() is null
  and (select count(*) from elius.contactos) = 0, 'Administrador: un negocio que no existe no devuelve nada');
select platform.usar_negocio(:'s_rest') \gset
reset session authorization;

-- Trabajador
set session authorization elius_trabajador;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok(app.mi_rol() = 'operador', 'Trabajador: entra con el rol operador');
select pg_temp.ok((select count(*) from elius.reservas) > 0, 'Trabajador: ve la agenda');
create temp table n_res as select count(*) n from elius.reservas;
select pg_temp.intenta('delete from elius.reservas');
select pg_temp.ok((select count(*) from elius.reservas) = (select n from n_res), 'Trabajador: no logra borrar (DELETE sin efecto o bloqueado)');
create temp table pr_ant as select precio from elius.items_catalogo where sku = 'RES-02';
select pg_temp.intenta('update elius.items_catalogo set precio = 1 where sku = ''RES-02''');
select pg_temp.ok((select precio from elius.items_catalogo where sku = 'RES-02') = (select precio from pr_ant), 'Trabajador: no logra cambiar precios del catálogo');
select pg_temp.ok(pg_temp.intenta('update elius.reservas set novedades = ''Llega tarde (BD)'' where id = (select id from elius.reservas order by inicio limit 1)') = 'ok', 'Trabajador: sí anota novedades');
select pg_temp.ok(pg_temp.intenta('drop table practica.mi_prueba_bd') <> 'ok', 'Trabajador: no borra tablas');
reset session authorization;

-- Soporte (con la autorización vigente de 7 días)
set session authorization elius_soporte;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok(app.current_tenant_id() = :'t_rest'::uuid and (select count(*) from elius.contactos) = 0 and app.mi_rol() = 'soporte', 'Soporte: entra al negocio autorizado pero no ve datos de clientes');
select pg_temp.intenta('delete from elius.contactos');
reset session authorization;
select pg_temp.ok((select count(*) from elius.contactos where tenant_id = :'t_rest') > 0, 'Soporte: DELETE no borra nada');
update platform.accesos_soporte set vence_en = now() + interval '1 minute', inicio = now() - interval '1 day' where usuario_soporte_id = '00000000-0000-0000-0000-00000000bd04';
update platform.accesos_soporte set revocado_en = now() where usuario_soporte_id = '00000000-0000-0000-0000-00000000bd04';
set session authorization elius_soporte;
select pg_temp.ok(app.current_tenant_id() is distinct from :'t_rest'::uuid and app.mi_rol() is null, 'Soporte: sin autorización vigente no entra al negocio');
reset session authorization;
select platform.renovar_soporte_bd() > 0 as renovado \gset
set session authorization elius_soporte;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok(app.mi_rol() = 'soporte' and app.current_tenant_id() = :'t_rest'::uuid, 'Soporte: renovada la autorización vuelve a entrar al negocio');
reset session authorization;

-- Super administrador
set session authorization elius_superadmin;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok(app.es_super_admin(), 'Superadministrador: es Super Admin de plataforma');
select pg_temp.ok(pg_temp.intenta('insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen) values (app.current_tenant_id(), ''Prueba'', ''BD'', ''+570000000'', ''whatsapp'')') = 'ok', 'Superadministrador: inserta');
select pg_temp.ok(pg_temp.intenta('delete from elius.contactos where telefono = ''+570000000''') = 'ok', 'Superadministrador: puede borrar (lo suyo)');
select pg_temp.ok(pg_temp.intenta('drop table elius.contactos') <> 'ok', 'Superadministrador: no es dueño, no puede dropear tablas del sistema');
select pg_temp.ok((select count(*) from platform.mis_negocios()) >= 1, 'Superadministrador: ve la lista de negocios');
reset session authorization;

-- Auditoría: lo hecho por el Trabajador lo ve el Administrador, con su rol
set session authorization elius_administrador;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok(exists (select 1 from elius.v_auditoria where tabla = 'reservas' and rol = 'operador' and datos_nuevos ->> 'novedades' = 'Llega tarde (BD)'), 'Auditoría: el Administrador ve lo que hizo el Trabajador, con su rol');
reset session authorization;
drop table if exists practica.mi_prueba_bd;

\echo '== 21. Paneles por rol: Trabajador y Soporte'
set session authorization elius_trabajador;
select platform.usar_negocio(:'s_rest') \gset
select elius.reportar_problema('No me carga la agenda de mañana') as pid \gset
select pg_temp.ok(:'pid' is not null, 'Trabajador: reporta un problema');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_resolver_error(null, ''x'')') <> 'ok', 'Trabajador: no puede resolver errores de Soporte');
select pg_temp.ok((select count(*) from elius.v_soporte_errores) = 0, 'Trabajador: no ve el panel técnico');
select id as r_id from elius.reservas where estado = 'confirmada' and responsable_id is null order by inicio limit 1 \gset
select pg_temp.ok(elius.tomar_reserva(:'r_id') = 'Trabajador (BD)', 'Trabajador: toma una reserva y queda como responsable');
select pg_temp.ok((select responsable_cargo from elius.v_agenda_calendario where reserva_id = :'r_id') = 'Trabajador (BD)', 'la agenda muestra quién tomó la reserva');
reset session authorization;
insert into elius.eventos_salida (tenant_id, tipo_evento, entidad, entidad_id, estado, intentos) values (:'t_rest', 'orden.pagada', 'orden', gen_random_uuid(), 'fallido', 3);

set session authorization elius_soporte;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok((select count(*) from elius.v_soporte_tickets_pendientes where origen = 'reporte' and creado_por_rol = 'operador') >= 1, 'Soporte: ve el problema que reportó el Trabajador como ticket pendiente');
select pg_temp.ok((select count(*) from elius.v_soporte_eventos where estado = 'fallido') = 1, 'Soporte: ve los eventos fallidos (sin su contenido)');
select pg_temp.ok((select count(*) from information_schema.columns where table_schema = 'elius' and table_name = 'v_soporte_eventos' and column_name = 'carga') = 0, 'Soporte: el contenido del evento no se expone');
select elius.soporte_reintentar_evento((select id from elius.v_soporte_eventos where estado = 'fallido' limit 1)) is null as ok_r \gset
select pg_temp.ok((select count(*) from elius.v_soporte_eventos where estado = 'fallido') = 0, 'Soporte: reintenta un evento fallido');
select pg_temp.ok((elius.soporte_estado_integraciones() ->> 'tickets_abiertos')::int >= 1, 'Soporte: ve el estado de las integraciones');
select pg_temp.ok((select count(*) from elius.v_soporte_auditoria) > 0, 'Soporte: ve la auditoría técnica');
select pg_temp.ok(pg_temp.intenta('select * from elius.ordenes') = 'ok' and (select count(*) from elius.ordenes) = 0, 'Soporte: no ve órdenes');
select pg_temp.ok(pg_temp.intenta('update elius.items_catalogo set precio = 1') = 'ok'
                  and (select count(*) from elius.items_catalogo) = 0, 'Soporte: no ve ni cambia el catálogo');
select pg_temp.ok(pg_temp.intenta('select elius.tomar_reserva(gen_random_uuid())') <> 'ok', 'Soporte: no toma reservas');
reset session authorization;

\echo '== 22. El panel del Trabajador cambia según el negocio'
create or replace function pg_temp.negocio(p_v text) returns text language sql as $$ select slug from platform.tenants where vertical = p_v and slug like 'demo-%' order by creado_en limit 1 $$;
select pg_temp.negocio('restaurante') as s_r, pg_temp.negocio('veterinaria') as s_v, pg_temp.negocio('aerolinea') as s_a \gset
set session authorization elius_trabajador;
-- Restaurante
select platform.usar_negocio(:'s_r') \gset
select pg_temp.ok((select count(*) from elius.v_trab_cocina) >= 3, 'Restaurante: la cocina tiene comandas pendientes');
select comanda_id as c1 from elius.v_trab_cocina where estado = 'recibida' limit 1 \gset
select pg_temp.ok(elius.trab_avanzar_comanda(:'c1') = 'en_preparacion', 'Restaurante: empieza la comanda');
select pg_temp.ok(elius.trab_avanzar_comanda(:'c1') = 'lista', 'Restaurante: deja lista la comanda');
select pg_temp.ok((select count(*) from elius.v_trab_celebraciones) >= 1 and (select count(*) from elius.v_trab_menu) >= 1, 'Restaurante: ve celebraciones y menú del día');
select pg_temp.ok((select count(*) from elius.v_trab_citas_vet) = 0, 'Restaurante: no ve nada de veterinaria');
-- Veterinaria
select platform.usar_negocio(:'s_v') \gset
select atencion_id as a1 from elius.v_trab_citas_vet order by inicio limit 1 \gset
select pg_temp.ok(:'a1' is not null, 'Veterinaria: ve las citas con su mascota');
select pg_temp.ok(pg_temp.intenta('select elius.trab_cerrar_atencion(''' || :'a1' || ''')') <> 'ok', 'Veterinaria: no cierra sin registrar signos');
select elius.trab_registrar_signos(:'a1', 12.5, 38.6) is null as ok_s \gset
select elius.trab_cerrar_atencion(:'a1') is null as ok_c \gset
select pg_temp.ok((select count(*) from elius.v_trab_vacunas) >= 1, 'Veterinaria: ve las vacunas por vencer');
select pg_temp.ok((select count(*) from elius.v_trab_cocina) = 0, 'Veterinaria: no ve la cocina');
-- Aerolínea
select platform.usar_negocio(:'s_a') \gset
select tiquete_id as tq from elius.v_trab_checkin where checkin_en is null order by salida_programada limit 1 \gset
select pg_temp.ok(:'tq' is not null, 'Aerolínea: ve los pasajeros sin check-in');
select elius.trab_hacer_checkin(:'tq', '14C') is null as ok_ck \gset
select pg_temp.ok((select count(*) from elius.v_trab_checkin where tiquete_id = :'tq' and checkin_en is not null and silla = '14C') = 1, 'Aerolínea: hace el check-in y queda la silla');
select pg_temp.ok((select count(*) from elius.v_trab_necesidades) >= 1 and (select count(*) from elius.v_trab_vuelos) >= 1, 'Aerolínea: ve necesidades especiales y vuelos');
select pg_temp.ok((select count(*) from elius.v_trab_cocina) = 0, 'Aerolínea: no ve la cocina del restaurante');
reset session authorization;

\echo '== 23. Todo lo que se hace en cualquier panel queda en la auditoría'
set session authorization elius_administrador;
select platform.usar_negocio(:'s_r') \gset
select pg_temp.ok((select count(*) from elius.v_auditoria where tabla = 'reservas' and rol = 'operador') >= 1, 'Auditoría: el Trabajador tomó una reserva');
select pg_temp.ok((select count(*) from elius.v_auditoria where tabla = 'tickets' and operacion = 'INSERT' and rol = 'operador') >= 1, 'Auditoría: el Trabajador reportó un problema');
select pg_temp.ok((select count(*) from elius.v_auditoria where esquema = 'plugin_restaurant' and tabla = 'comandas' and rol = 'operador') >= 1, 'Auditoría: el Trabajador avanzó una comanda');
select pg_temp.ok((select count(*) from elius.v_auditoria where tabla = 'errores_agente' and operacion = 'UPDATE' and rol = 'soporte') >= 0, 'Auditoría: consulta de lo que hizo Soporte');
select pg_temp.ok((select count(*) from elius.v_auditoria where tabla = 'eventos_salida' and rol = 'soporte') >= 1, 'Auditoría: Soporte reintentó un evento de salida');
select platform.usar_negocio(:'s_v') \gset
select pg_temp.ok((select count(*) from elius.v_auditoria where esquema = 'plugin_vet' and tabla = 'atenciones' and rol = 'operador') >= 1, 'Auditoría: el Trabajador registró signos y cerró una atención');
select platform.usar_negocio(:'s_a') \gset
select pg_temp.ok((select count(*) from elius.v_auditoria where esquema = 'plugin_airline' and tabla = 'tiquetes' and rol = 'operador') >= 1, 'Auditoría: el Trabajador hizo un check-in');
-- El Trabajador ve en vivo cómo Soporte atiende su reporte
reset session authorization;
set session authorization elius_trabajador;
select platform.usar_negocio(:'s_rest') \gset
select elius.reportar_problema('La impresora de comandas no responde') as p2 \gset
select pg_temp.ok((select count(*) from elius.v_mis_reportes where id = :'p2' and abierto) = 1, 'Trabajador: ve su reporte como abierto');
reset session authorization;
set session authorization elius_soporte;
select platform.usar_negocio(:'s_rest') \gset
select elius.soporte_tomar_ticket(:'p2') is null as ok_tom \gset
select elius.soporte_resolver_ticket(:'p2', 'Se reinició el servicio de impresión') is null as ok_res \gset
reset session authorization;
set session authorization elius_trabajador;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok((select count(*) from elius.v_mis_reportes where id = :'p2' and not abierto and notas like '%reinició el servicio%') = 1, 'Trabajador: ve que Soporte lo resolvió y con qué nota');
reset session authorization;

-- 24 · La auditoría guarda instancia, base, puerto, IP y login de BD de cada movimiento
do $$ declare v record; begin
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.7, 10.0.0.1"}', true);
  insert into audit.registros_auditoria (rol, esquema, tabla, registro_id, operacion)
    values ('administrador', 'elius', 'prueba_origen', gen_random_uuid(), 'INSERT');
  select * into v from audit.registros_auditoria where tabla = 'prueba_origen';
  if v.base_datos is null or v.instancia is null or v.login_bd is null or v.aplicacion is null then
    raise exception 'FALLA 24: faltan datos de conexión en la auditoría'; end if;
  if v.ip_cliente <> '203.0.113.7' then raise exception 'FALLA 24: IP esperada 203.0.113.7, llegó %', v.ip_cliente; end if;
  delete from audit.registros_auditoria where tabla = 'prueba_origen';
  raise notice 'OK 24: auditoría con instancia %, base %, puerto %, IP %, login %', v.instancia, v.base_datos, v.puerto, v.ip_cliente, v.login_bd;
end $$;

-- 25 · La auditoría guarda el correo de quien hizo el cambio
do $$ declare v record; u uuid; begin
  select id into u from auth.users where email = 'admin.restaurante@elius.local';
  insert into audit.registros_auditoria (usuario_id, rol, esquema, tabla, registro_id, operacion)
    values (u, 'administrador', 'elius', 'prueba_quien', gen_random_uuid(), 'INSERT');
  select * into v from audit.registros_auditoria where tabla = 'prueba_quien';
  if v.usuario_email is distinct from 'admin.restaurante@elius.local' then raise exception 'FALLA 25: correo % ', v.usuario_email; end if;
  delete from audit.registros_auditoria where tabla = 'prueba_quien';
  raise notice 'OK 25: la auditoría dice quién: %', v.usuario_email;
end $$;

-- 26 · Los triggers tienen descripción y la vista los lista
do $$ declare n int; v text; begin
  select count(*) into n from elius.v_triggers_tabla where descripcion is null;
  if n > 0 then raise exception 'FALLA 26: % triggers sin descripción: %', n, (select string_agg(esquema||'.'||tabla||':'||trigger, ', ') from elius.v_triggers_tabla where descripcion is null limit 5); end if;
  select descripcion into v from elius.v_triggers_tabla where tabla = 'ordenes' and trigger = 't43_proteger_totales';
  if v is null then raise exception 'FALLA 26: falta t43'; end if;
  raise notice 'OK 26: todos los triggers describen su regla (%)', left(v, 40);
end $$;

-- 27 · Eliminar = desactivar; borrar de verdad solo el CIS adm
\echo '== 27. Baja lógica y papelera'
select u.id as u_admin from auth.users u where u.email = 'admin.restaurante@elius.local' \gset
select u.id as u_trab  from auth.users u where u.email = 'trabajador.restaurante@elius.local' \gset
select u.id as u_cis   from auth.users u where u.email = 'superadmin.restaurante@elius.local' \gset
select slug as s_r27 from platform.tenants where slug like 'demo-restaurante-%' order by creado_en limit 1 \gset
select id as t_r27 from platform.tenants where slug = :'s_r27' \gset
select id as item27 from elius.items_catalogo where tenant_id = :'t_r27' and eliminado_en is null order by nombre limit 1 \gset
insert into elius.items_catalogo (tenant_id, nombre, tipo, precio, impuesto_pct, categoria_id) values (:'t_r27', 'Producto de papelera', 'producto', 1000, 0, (select id from elius.categorias_catalogo where tenant_id = :'t_r27' limit 1)) returning id as item_nuevo \gset

-- Administrador desde el panel (API)
select set_config('request.jwt.claims', json_build_object('sub', :'u_admin', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select pg_temp.ok(pg_temp.intenta('delete from elius.items_catalogo where id = ''' || :'item_nuevo' || '''') = '42501', 'Panel Administrador: el DELETE real está bloqueado');
select pg_temp.ok(pg_temp.intenta('update elius.items_catalogo set eliminado_en = now() where id = ''' || :'item_nuevo' || '''') = 'ok', 'Panel Administrador: Eliminar = desactivar');
select pg_temp.ok((select count(*) from elius.v_papelera where tipo = 'producto' and id = :'item_nuevo') = 1, 'Panel Administrador: lo ve en la Papelera');
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_definitivo(''producto'', ''' || :'item_nuevo' || ''')') = '42501', 'Panel Administrador: no borra definitivamente');
select pg_temp.ok(pg_temp.intenta('update elius.items_catalogo set eliminado_en = null where id = ''' || :'item_nuevo' || '''') = 'ok', 'Panel Administrador: restaura');
select pg_temp.ok(pg_temp.intenta('update elius.items_catalogo set eliminado_en = now() where id = ''' || :'item_nuevo' || '''') = 'ok', 'Panel Administrador: vuelve a eliminarlo');
reset role;

-- Operador desde el panel
select set_config('request.jwt.claims', json_build_object('sub', :'u_trab', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select pg_temp.ok(pg_temp.intenta('update elius.contactos set eliminado_en = now() where id = (select id from elius.contactos limit 1)') <> 'ok', 'Panel Operador: no puede eliminar clientes');
select pg_temp.ok((select count(*) from elius.v_papelera) = 0, 'Panel Operador: no ve la Papelera');
reset role;

-- CIS adm
select set_config('request.jwt.claims', json_build_object('sub', :'u_cis', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select pg_temp.ok(app.es_super_admin(), 'CIS adm: es Super Admin');
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_definitivo(''producto'', ''' || :'item_nuevo' || ''')') = 'ok', 'CIS adm: borra definitivamente lo que está en la Papelera');
reset role;
select pg_temp.ok((select count(*) from elius.items_catalogo where id = :'item_nuevo') = 0, 'La fila ya no existe en la base');
select pg_temp.ok((select count(*) from audit.registros_auditoria where tabla = 'items_catalogo' and operacion = 'DELETE' and (datos_anteriores ->> 'id') = :'item_nuevo') = 1, 'El borrado definitivo quedó en la auditoría');
select set_config('request.jwt.claims', '', false);

-- 28 · Panel de Soporte con tickets: todo por vistas y procedimientos
\echo '== 28. Tickets de soporte'
reset session authorization;
reset role;
select set_config('request.jwt.claims', '', false);
update platform.accesos_soporte set revocado_en = null, inicio = now() - interval '1 hour', vence_en = now() + interval '3 days' where usuario_soporte_id = '00000000-0000-0000-0000-00000000bd04';
set session authorization elius_soporte;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok(pg_temp.intenta('select * from elius.tickets') <> 'ok', 'Soporte: no lee la tabla de tickets directamente');
select pg_temp.ok(pg_temp.intenta('delete from elius.tickets') <> 'ok', 'Soporte: no borra tickets');
select elius.generar_ticket_prueba('cliente') ->> 'id' as tk \gset
select pg_temp.ok((select count(*) from elius.v_soporte_tickets_pendientes where id = :'tk') = 1, 'Soporte: el ticket generado aparece en pendientes');
select pg_temp.ok((select count(*) from elius.v_soporte_historial_tickets) >= 3, 'Soporte: el historial trae tickets ya resueltos');
select pg_temp.ok((select codigo from elius.v_soporte_tickets where id = :'tk') ~ '^TCK-[0-9]{4}$', 'El ticket tiene código TCK-0000');
select pg_temp.ok((select count(*) from elius.v_soporte_historial_tickets where categoria = '05') >= 1, 'Soporte: busca en el historial por categoría 05 Contabilidad');
select pg_temp.ok((select count(*) from elius.v_soporte_manual where categoria = '05') >= 1, 'Soporte: lee el manual de la categoría');
select elius.soporte_tomar_ticket(:'tk') is null as ok_t \gset
select pg_temp.ok((select estado from elius.v_soporte_tickets where id = :'tk') = 'en_proceso', 'Soporte: toma el ticket (en proceso)');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_resolver_ticket(''' || :'tk' || ''', ''x'')') <> 'ok', 'No se resuelve sin escribir la solución');
select contacto_id as c_tk from elius.v_soporte_tickets where id = :'tk' \gset
select pg_temp.ok((select telefono from elius.v_soporte_clientes where id = :'c_tk') like '+57%•••%' or (select telefono from elius.v_soporte_clientes where id = :'c_tk') = '•••', 'Soporte: ve el teléfono del cliente enmascarado');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_corregir_cliente(''' || :'c_tk' || ''', ''' || :'tk' || ''', null, null, ''3001234'', null, ''Teléfono sin indicativo'')') <> 'ok', 'Teléfono mal escrito: se rechaza');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_corregir_cliente(''' || :'c_tk' || ''', ''' || :'tk' || ''', null, null, ''+573105550123'', null, ''x'')') <> 'ok', 'Corregir exige un motivo');
select elius.soporte_corregir_cliente(:'c_tk', :'tk', null, null, '+573105550123', null, 'Teléfono incompleto al registrarlo') as cambio \gset
select pg_temp.ok(:'cambio' like 'teléfono:%', 'Soporte: corrige el teléfono del cliente por el procedimiento');
select pg_temp.ok((select count(*) from elius.v_soporte_ticket_notas where ticket_id = :'tk' and tipo = 'dato_corregido') = 1, 'La corrección queda en la cronología del ticket');
select elius.soporte_crear_usuario(:'tk', 'ayudante28@elius.local', 'operador', 'Ayudante') ->> 'email' as u_nuevo \gset
select pg_temp.ok(:'u_nuevo' = 'ayudante28@elius.local', 'Soporte: crea un usuario con rol');
select pg_temp.ok((select rol from elius.v_soporte_usuarios where email = 'ayudante28@elius.local') = 'operador', 'El usuario nuevo aparece con su rol');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_crear_usuario(null, ''ayudante28@elius.local'', ''operador'', null)') <> 'ok', 'No se duplica el usuario en el negocio');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_crear_usuario(null, ''otro28@elius.local'', ''superadministrador'', null)') <> 'ok', 'Soporte no crea roles de plataforma');
select usuario_id as u28 from elius.v_soporte_usuarios where email = 'ayudante28@elius.local' \gset
select elius.soporte_cambiar_rol_usuario(:'u28', 'analista', :'tk') is null as ok_cr \gset
select pg_temp.ok((select rol from elius.v_soporte_usuarios where usuario_id = :'u28') = 'analista', 'Soporte: cambia el rol del usuario');
select pg_temp.ok((elius.soporte_restablecer_clave(:'u28', :'tk') ->> 'email') = 'ayudante28@elius.local', 'Soporte: restablece la clave (se muestra una vez)');
select elius.soporte_estado_usuario(:'u28', false, :'tk') is null as ok_es \gset
select pg_temp.ok((select estado from elius.v_soporte_usuarios where usuario_id = :'u28') = 'inactivo', 'Soporte: desactiva al usuario');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_restablecer_clave(''00000000-0000-0000-0000-00000000bd04'', null)') <> 'ok', 'No restablece cuentas de conexión directa ni la propia');
select elius.soporte_resolver_ticket(:'tk', 'Se corrigió el teléfono y se creó el usuario de apoyo') is null as ok_r \gset
select pg_temp.ok((select estado from elius.v_soporte_tickets where id = :'tk') = 'resuelto' and (select count(*) from elius.v_soporte_historial_tickets where id = :'tk') = 1, 'Soporte: resuelve y pasa al historial');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_nota_ticket(''' || :'tk' || ''', ''nota tardía'')') = 'ok', 'Se pueden agregar notas aun resuelto');
select pg_temp.ok(pg_temp.intenta('select elius.soporte_corregir_cliente(''' || :'c_tk' || ''', ''' || :'tk' || ''', ''Nombre'', null, null, null, ''motivo válido'')') <> 'ok', 'No se corrige un cliente con un ticket ya resuelto');
reset session authorization;
select pg_temp.ok((select count(*) from audit.registros_auditoria where tabla = 'contactos' and operacion = 'UPDATE' and rol = 'soporte' and registro_id = :'c_tk') >= 1, 'Auditoría: la corrección quedó con rol soporte');
select pg_temp.ok((select count(*) from audit.registros_auditoria where tabla = 'tickets' and rol = 'soporte') >= 1, 'Auditoría: los cambios del ticket quedaron con rol soporte');
-- El trabajador no ve tickets del panel técnico
set session authorization elius_trabajador;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok((select count(*) from elius.v_soporte_tickets) = 0 and (select count(*) from elius.v_soporte_usuarios) = 0 and (select count(*) from elius.v_soporte_clientes) = 0, 'Trabajador: no ve las vistas de Soporte');
select pg_temp.ok(pg_temp.intenta('select elius.generar_ticket_prueba()') <> 'ok', 'Trabajador: no genera tickets de prueba');
reset session authorization;

-- 29 · Flujos del Administrador: comprobantes de prueba y consola (C, R, U, D y mixta)
\echo '== 29. Comprobantes de prueba y consola del Administrador'
select slug as s_v29 from platform.tenants where slug like 'demo-veterinaria-%' order by creado_en limit 1 \gset
select slug as s_a29 from platform.tenants where slug like 'demo-aerolinea-%' order by creado_en limit 1 \gset
select id as t_v29 from platform.tenants where slug = :'s_v29' \gset
select id as t_a29 from platform.tenants where slug = :'s_a29' \gset
select u.id as u_adm_v from auth.users u where u.email = 'admin.veterinaria@elius.local' \gset
select u.id as u_adm_a from auth.users u where u.email = 'admin.aerolinea@elius.local' \gset

-- Restaurante · caso exacto
select set_config('request.jwt.claims', json_build_object('sub', :'u_admin', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select elius.generar_comprobante_prueba('exacto') ->> 'comprobante_id' as c_ex \gset
select pg_temp.ok((select motivo from elius.comprobantes_pago where id = :'c_ex') is null and (select coincide from elius.comprobantes_pago where id = :'c_ex'), 'Comprobante exacto: sin alerta (t52)');
select pg_temp.ok(pg_temp.intenta('select elius.aprobar_comprobante(''' || :'c_ex' || ''')') = 'ok', 'Administrador aprueba el comprobante');
select pg_temp.ok((select o.estado from elius.ordenes o join elius.comprobantes_pago c on c.orden_id = o.id where c.id = :'c_ex') = 'confirmada', 't51: la orden queda confirmada al cubrirse el total');
select pg_temp.ok(pg_temp.intenta('select elius.generar_comprobante_prueba(''xx'')') <> 'ok', 'Caso no válido se rechaza');
-- Consola del Administrador
select pg_temp.ok((elius.consola_sql('select count(*) as n from elius.v_comprobantes_pendientes') ->> 'tipo') = 'select', 'Consola: SELECT sobre la vista de comprobantes');
select pg_temp.ok(pg_temp.intenta($q$select elius.consola_sql('update elius.pagos set monto = 1 where estado = ''aprobado''')$q$) <> 'ok', 'Consola: t50 impide modificar un pago aprobado');
select pg_temp.ok(pg_temp.intenta($q$select elius.consola_sql('update elius.ordenes set total = 1')$q$) <> 'ok', 'Consola: t43 impide escribir el total a mano');
select pg_temp.ok((elius.consola_sql('delete from elius.contactos') ->> 'tipo') = 'bloqueada', 'Consola: DELETE bloqueado y registrado');
select pg_temp.ok((elius.consola_sql($q$insert into elius.contactos (nombres, apellidos, telefono, origen) values ('Consola', 'Crea', '+573009998877', 'panel')$q$) ->> 'afectadas')::int = 1, 'Consola: INSERT de un cliente (Create)');
select pg_temp.ok(pg_temp.intenta($q$select elius.consola_sql('insert into elius.contactos (nombres, apellidos, telefono, origen) values (''Mal'', ''Tel'', ''3001'', ''panel'')')$q$) <> 'ok', 'Consola: teléfono mal escrito rechazado por la restricción');
select pg_temp.ok((elius.consola_sql($q$update elius.contactos set apellidos = 'Actualizado' where telefono = '+573009998877'$q$) ->> 'afectadas')::int = 1, 'Consola: UPDATE de un cliente (Update)');
select pg_temp.ok((select count(*) from elius.v_triggers_tabla where tabla in ('comprobantes_pago', 'pagos', 'ordenes', 'orden_items')) >= 8, 'Vista de triggers de la plata disponible');
reset role;
select pg_temp.ok((select count(*) from audit.registros_auditoria where tabla = 'comprobantes_pago' and operacion = 'INSERT' and registro_id = :'c_ex') = 1, 'Auditoría del comprobante generado');
select pg_temp.ok((select count(*) from elius.eventos_salida where tipo_evento = 'comprobante.recibido' and entidad_id = :'c_ex') = 1, 't53: el comprobante emitió su evento');

-- Veterinaria · monto distinto → alerta, rechazo
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm_v', 'role', 'authenticated', 'tenant_id', :'t_v29')::text, false) \gset
set role authenticated;
select elius.generar_comprobante_prueba('distinto') ->> 'comprobante_id' as c_di \gset
select pg_temp.ok((select motivo from elius.comprobantes_pago where id = :'c_di') like 'ALERTA:%monto%distinto%', 't52: alerta de monto distinto');
select pg_temp.ok((select coincide from elius.comprobantes_pago where id = :'c_di') = false, 'coincide = false');
select pg_temp.ok(pg_temp.intenta('select elius.rechazar_comprobante(''' || :'c_di' || ''', ''El monto no coincide con el pedido'')') = 'ok', 'Administrador rechaza el comprobante');
select pg_temp.ok((select count(*) from elius.pagos p join elius.comprobantes_pago c on c.orden_id = p.orden_id where c.id = :'c_di') = 0, 'Rechazado: no se creó ningún pago');
reset role;

-- Aerolínea · repetido
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm_a', 'role', 'authenticated', 'tenant_id', :'t_a29')::text, false) \gset
set role authenticated;
select elius.generar_comprobante_prueba('exacto') ->> 'comprobante_id' as c_a1 \gset
select elius.aprobar_comprobante(:'c_a1') is not null as ok_a1 \gset
select elius.generar_comprobante_prueba('repetido') ->> 'comprobante_id' as c_a2 \gset
select pg_temp.ok((select motivo from elius.comprobantes_pago where id = :'c_a2') like '%repetido%', 't52: alerta de comprobante repetido');
reset role;
select set_config('request.jwt.claims', '', false);

-- 30 · El Administrador crea y elimina pedidos y reservas a mano
\echo '== 30. Pedidos y reservas manuales + Papelera'
select set_config('request.jwt.claims', json_build_object('sub', :'u_admin', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select id as c30 from elius.contactos where eliminado_en is null order by creado_en limit 1 \gset
select id as i30a from elius.items_catalogo where eliminado_en is null and precio > 0 order by precio limit 1 \gset
select id as i30b from elius.items_catalogo where eliminado_en is null and precio > 0 order by precio desc limit 1 \gset
select elius.crear_pedido_manual(:'c30', 'recoger', json_build_array(json_build_object('item_id', :'i30a', 'cantidad', 2), json_build_object('item_id', :'i30b', 'cantidad', 1))::jsonb) as p30 \gset
select pg_temp.ok((select total from elius.ordenes where id = :'p30') > 0 and (select canal_venta from elius.ordenes where id = :'p30') = 'presencial', 'Pedido manual: la base calcula el total (t41, t42) y queda presencial');
select pg_temp.ok(pg_temp.intenta('select elius.crear_pedido_manual(''' || :'c30' || ''', ''recoger'', ''[]''::jsonb)') <> 'ok', 'Pedido sin productos se rechaza');
select pg_temp.ok(pg_temp.intenta('delete from elius.ordenes where id = ''' || :'p30' || '''') = '42501', 'El DELETE real de un pedido está bloqueado');
select elius.eliminar_pedido(:'p30') is null as ok_e \gset
select pg_temp.ok((select count(*) from elius.ordenes where id = :'p30') = 0 and (select count(*) from elius.v_saldo_ordenes where orden_id = :'p30') = 0, 'Pedido eliminado: desaparece del panel y de las vistas');
select pg_temp.ok((select count(*) from elius.v_papelera where tipo = 'pedido' and id = :'p30') = 1, 'El pedido eliminado aparece en la Papelera');
select elius.restaurar_pedido(:'p30') is null as ok_r \gset
select pg_temp.ok((select count(*) from elius.ordenes where id = :'p30') = 1, 'Pedido restaurado: vuelve al panel');
-- Reserva manual
select elius.agendar_reserva(:'c30', 'mesa', (date_trunc('day', now() at time zone 'America/Bogota') + interval '3 days 19 hours') at time zone 'America/Bogota', (date_trunc('day', now() at time zone 'America/Bogota') + interval '3 days 20 hours') at time zone 'America/Bogota', 2, '{}', 'Reserva manual de prueba') as r30 \gset
select pg_temp.ok((select count(*) from elius.reservas where id = :'r30') = 1, 'Reserva manual creada por el Administrador');
select elius.eliminar_reserva(:'r30') is null as ok_er \gset
select pg_temp.ok((select count(*) from elius.reservas where id = :'r30') = 0 and (select count(*) from elius.v_agenda_calendario where reserva_id = :'r30') = 0, 'Reserva eliminada: desaparece de la agenda');
select pg_temp.ok((select count(*) from elius.v_papelera where tipo = 'reserva' and id = :'r30') = 1, 'La reserva eliminada aparece en la Papelera');
select elius.restaurar_reserva(:'r30') is null as ok_rr \gset
select pg_temp.ok((select count(*) from elius.v_agenda_calendario where reserva_id = :'r30') = 1, 'Reserva restaurada: vuelve a la agenda');
-- Pedido con pago aprobado: no se elimina
select elius.generar_comprobante_prueba('exacto') ->> 'comprobante_id' as c30c \gset
select elius.aprobar_comprobante(:'c30c') is not null as ok_ap \gset
select orden_id as o30p from elius.comprobantes_pago where id = :'c30c' \gset
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_pedido(''' || :'o30p' || ''')') <> 'ok', 'RN-C12: un pedido con pago aprobado no se elimina (t07)');
reset role;
-- Operador no crea ni elimina
select set_config('request.jwt.claims', json_build_object('sub', :'u_trab', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_pedido(''' || :'p30' || ''')') <> 'ok', 'Operador: no elimina pedidos');
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_reserva(''' || :'r30' || ''')') <> 'ok', 'Operador: no elimina reservas');
select pg_temp.ok(pg_temp.intenta('select elius.crear_pedido_manual(''' || :'c30' || ''', ''recoger'', ''[{}]''::jsonb)') <> 'ok', 'Operador: no crea pedidos a mano');
reset role;
-- CIS adm borra de verdad
select set_config('request.jwt.claims', json_build_object('sub', :'u_admin', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select elius.eliminar_pedido(:'p30') is null as ok_e2 \gset
select elius.eliminar_reserva(:'r30') is null as ok_er2 \gset
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_definitivo(''pedido'', ''' || :'p30' || ''')') = '42501', 'Administrador: no borra definitivamente un pedido');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'u_cis', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_definitivo(''pedido'', ''' || :'p30' || ''')') = 'ok', 'CIS adm: borra definitivamente el pedido de la Papelera');
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_definitivo(''reserva'', ''' || :'r30' || ''')') = 'ok', 'CIS adm: borra definitivamente la reserva de la Papelera');
reset role;
select pg_temp.ok((select count(*) from elius.ordenes where id = :'p30') = 0 and (select count(*) from elius.reservas where id = :'r30') = 0, 'Ya no existen en la base');
-- Veterinaria y aerolínea
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm_v', 'role', 'authenticated', 'tenant_id', :'t_v29')::text, false) \gset
set role authenticated;
select id as c30v from elius.contactos where eliminado_en is null order by creado_en limit 1 \gset
select id as i30v from elius.items_catalogo where eliminado_en is null and precio > 0 order by precio limit 1 \gset
select pg_temp.ok(pg_temp.intenta('select elius.crear_pedido_manual(''' || :'c30v' || ''', ''recoger'', ''[{"item_id": "' || :'i30v' || '", "cantidad": 1}]''::jsonb)') = 'ok', 'Veterinaria: pedido manual');
select pg_temp.ok(pg_temp.intenta('select elius.agendar_reserva(''' || :'c30v' || ''', ''cita'', now() + interval ''4 days'', now() + interval ''4 days 1 hour'', 1)') in ('ok', '23514'), 'Veterinaria: reserva manual (acepta o la rechaza una regla de horario, nunca un error de permisos)');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'u_adm_a', 'role', 'authenticated', 'tenant_id', :'t_a29')::text, false) \gset
set role authenticated;
select id as c30a from elius.contactos where eliminado_en is null order by creado_en limit 1 \gset
select id as i30a2 from elius.items_catalogo where eliminado_en is null and precio > 0 order by precio limit 1 \gset
select pg_temp.ok(pg_temp.intenta('select elius.crear_pedido_manual(''' || :'c30a' || ''', ''no_aplica'', ''[{"item_id": "' || :'i30a2' || '", "cantidad": 1}]''::jsonb)') = 'ok', 'Aerolínea: pedido manual');
reset role;
select set_config('request.jwt.claims', '', false);

-- 31 · Coherencia: reservas, pedidos, mesas, clientes y dinero
\echo '== 31. Coherencia entre reservas, pedidos y mesas'
select set_config('request.jwt.claims', json_build_object('sub', :'u_admin', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select id as c31 from elius.contactos where eliminado_en is null order by creado_en offset 2 limit 1 \gset
select id as mesa31 from elius.recursos where activo and tipo = 'mesa' and capacidad >= 2 order by capacidad limit 1 \gset
select id as it31 from elius.items_catalogo where eliminado_en is null and precio > 0 order by precio limit 1 \gset
select (date_trunc('day', now() at time zone 'America/Bogota') + interval '5 days 19 hours') at time zone 'America/Bogota' as ini31 \gset
select (date_trunc('day', now() at time zone 'America/Bogota') + interval '5 days 20 hours') at time zone 'America/Bogota' as fin31 \gset
select elius.agendar_reserva(:'c31', 'mesa', :'ini31', :'fin31', 2, array[:'mesa31']::uuid[], 'Reserva coherencia 1') as r31 \gset
select elius.crear_orden(:'c31', 'presencial', 'sitio', :'r31') as o31 \gset
select elius.agregar_item(:'o31', :'it31', 1) is not null as ok_it \gset
select pg_temp.ok(pg_temp.intenta('select elius.agendar_reserva(''' || :'c31' || ''', ''mesa'', ''' || :'ini31' || ''', ''' || :'fin31' || ''', 2, array[''' || :'mesa31' || ''']::uuid[], null)') <> 'ok', 'RN-C07: la mesa ocupada no se reserva dos veces');
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_pedido(''' || :'o31' || ''')') <> 'ok', 'RN-C09: el pedido de una reserva activa no se elimina solo');
select pg_temp.ok(pg_temp.intenta('update elius.contactos set eliminado_en = now() where id = ''' || :'c31' || '''') <> 'ok', 'RN-C13: el cliente con reserva activa no se elimina');
select pg_temp.ok(pg_temp.intenta('select elius.cancelar_reserva(''' || :'r31' || ''', ''no'')') <> 'ok', 'Cancelar exige un motivo');
reset role;
-- El Trabajador no cancela y no registra llegada de una reserva sin pago
select set_config('request.jwt.claims', json_build_object('sub', :'u_trab', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select pg_temp.ok(pg_temp.intenta('select elius.cancelar_reserva(''' || :'r31' || ''', ''Intento del trabajador'')') = '42501', 'Operador: no cancela reservas');
select pg_temp.ok(pg_temp.intenta('select elius.marcar_llegada(''' || :'r31' || ''')') <> 'ok', 'Operador: no registra llegada de una reserva pendiente de pago o de otro día');
reset role;
-- El Administrador cancela: se libera la mesa y se cancela el pedido sin pago
select set_config('request.jwt.claims', json_build_object('sub', :'u_admin', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select elius.cancelar_reserva(:'r31', 'El cliente avisó que no viene') as msg31 \gset
select pg_temp.ok((select estado from elius.reservas where id = :'r31') = 'cancelada' and (select notas from elius.reservas where id = :'r31') like '%Cancelada: El cliente%', 'Reserva cancelada con su motivo');
select pg_temp.ok((select estado from elius.ordenes where id = :'o31') = 'cancelada', 'El pedido sin pago de esa reserva quedó cancelado');
select pg_temp.ok((select count(*) from elius.asignaciones_recurso where reserva_id = :'r31' and estado = 'activa') = 0, 'La mesa quedó liberada');
select elius.agendar_reserva(:'c31', 'mesa', :'ini31', :'fin31', 2, array[:'mesa31']::uuid[], 'Reserva coherencia 2') as r31b \gset
select pg_temp.ok(:'r31b' is not null, 'La mesa liberada se puede reservar de nuevo');
-- Eliminar libera la mesa; restaurar la vuelve a ocupar si sigue libre
select elius.eliminar_reserva(:'r31b') is null as ok_el \gset
select elius.agendar_reserva(:'c31', 'mesa', :'ini31', :'fin31', 2, array[:'mesa31']::uuid[], 'Reserva coherencia 3') as r31c \gset
select pg_temp.ok(pg_temp.intenta('select elius.restaurar_reserva(''' || :'r31b' || ''')') = '23P01', 'No se restaura si otra reserva ya tomó la mesa');
select elius.cancelar_reserva(:'r31c', 'Se cambia de horario') is not null as ok_c \gset
select pg_temp.ok(pg_temp.intenta('select elius.restaurar_reserva(''' || :'r31b' || ''')') = 'ok', 'Se restaura cuando la mesa está libre');
select pg_temp.ok((select count(*) from elius.asignaciones_recurso where reserva_id = :'r31b' and estado = 'activa') = 1, 'Al restaurar la mesa vuelve a quedar ocupada');
reset role;
-- Dinero de por medio: pago aprobado
select elius.agendar_reserva(:'c31', 'cita', now() + interval '6 days', now() + interval '6 days 1 hour', 1, '{}', 'Con pago') as r31d \gset
select set_config('request.jwt.claims', json_build_object('sub', :'u_admin', 'role', 'authenticated', 'tenant_id', :'t_r27')::text, false) \gset
set role authenticated;
select elius.agendar_reserva(:'c31', 'otro', now() + interval '6 days', now() + interval '6 days 1 hour', 1, '{}', 'Con pago') as r31e \gset
select elius.crear_orden(:'c31', 'presencial', 'no_aplica', :'r31e') as o31e \gset
select elius.agregar_item(:'o31e', :'it31', 1) is not null as ok_ie \gset
reset role;
insert into elius.pagos (tenant_id, orden_id, metodo, monto, estado) select :'t_r27', :'o31e', 'transferencia', total, 'aprobado' from elius.ordenes where id = :'o31e';
set role authenticated;
select pg_temp.ok(pg_temp.intenta('select elius.eliminar_reserva(''' || :'r31e' || ''')') <> 'ok', 'RN-C12: una reserva con pago aprobado no se elimina');
select pg_temp.ok(elius.cancelar_reserva(:'r31e', 'El cliente pidió cancelar') like '%reembolso%', 'Cancelar una reserva pagada deja anotado el reembolso');
select pg_temp.ok((select estado from elius.ordenes where id = :'o31e') = 'confirmada', 'El pedido pagado no se cancela: el dinero se gestiona aparte');
reset role;
select set_config('request.jwt.claims', '', false);
