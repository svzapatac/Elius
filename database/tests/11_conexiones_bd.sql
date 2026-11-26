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
select pg_temp.ok(pg_temp.intenta('update elius.contactos set eliminado_en = now()') = '42501', 'Administrador: no puede dar de baja (eliminado_en)');
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
select pg_temp.ok((select count(*) from elius.v_soporte_errores where abierto and origen = 'reporte:operador') >= 1, 'Soporte: ve el problema que reportó el Trabajador');
select pg_temp.ok((select count(*) from elius.v_soporte_eventos where estado = 'fallido') = 1, 'Soporte: ve los eventos fallidos (sin su contenido)');
select pg_temp.ok((select count(*) from information_schema.columns where table_schema = 'elius' and table_name = 'v_soporte_eventos' and column_name = 'carga') = 0, 'Soporte: el contenido del evento no se expone');
select elius.soporte_reintentar_evento((select id from elius.v_soporte_eventos where estado = 'fallido' limit 1)) is null as ok_r \gset
select pg_temp.ok((select count(*) from elius.v_soporte_eventos where estado = 'fallido') = 0, 'Soporte: reintenta un evento fallido');
select pg_temp.ok((elius.soporte_estado_integraciones() ->> 'errores_abiertos')::int >= 1, 'Soporte: ve el estado de las integraciones');
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
select pg_temp.ok((select count(*) from elius.v_auditoria where tabla = 'errores_agente' and operacion = 'INSERT' and rol = 'operador') >= 1, 'Auditoría: el Trabajador reportó un problema');
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
select elius.soporte_resolver_error(:'p2', 'Se reinició el servicio de impresión') is null as ok_res \gset
reset session authorization;
set session authorization elius_trabajador;
select platform.usar_negocio(:'s_rest') \gset
select pg_temp.ok((select count(*) from elius.v_mis_reportes where id = :'p2' and not abierto and notas like '%reinició el servicio%') = 1, 'Trabajador: ve que Soporte lo resolvió y con qué nota');
reset session authorization;
