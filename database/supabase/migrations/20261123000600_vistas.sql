-- =============================================================================
-- ELIUS · Migración 0600 · Vistas
-- Dos familias:
--  1. Vistas de negocio (elius y plugins) con security_invoker = true (DT-14):
--     aplican el RLS de quien consulta, así cada usuario solo ve su tenant y lo
--     que su rol le permite. Son las que usan los paneles y el rol Analista.
--  2. Vistas del esquema reportes: agregadas y sin datos personales, para el
--     usuario de base de datos elius_consulta y el Super Admin. No se exponen en la API.
-- =============================================================================

-- ---------- 1. Modelo general ----------------------------------------------------

-- Agenda del día: reservas de hoy con cliente y recursos asignados
create view elius.v_agenda_dia with (security_invoker = true) as
select r.tenant_id, r.id as reserva_id, r.codigo, r.tipo, r.estado, r.inicio, r.fin, r.personas,
       r.urgente, r.visto, r.llegada_en,
       c.nombres || coalesce(' ' || c.apellidos, '') as cliente, c.telefono,
       string_agg(rc.nombre, ', ' order by rc.nombre) as recursos,
       m.cargo as responsable_cargo
from elius.reservas r
join elius.contactos c on c.tenant_id = r.tenant_id and c.id = r.contacto_id
left join elius.asignaciones_recurso ar on ar.tenant_id = r.tenant_id and ar.reserva_id = r.id and ar.estado = 'activa'
left join elius.recursos rc on rc.tenant_id = ar.tenant_id and rc.id = ar.recurso_id
left join platform.membresias m on m.tenant_id = r.tenant_id and m.id = r.responsable_id
where r.inicio >= date_trunc('day', now()) and r.inicio < date_trunc('day', now()) + interval '1 day'
  and r.estado in ('pendiente_pago', 'confirmada', 'asistio')
group by r.tenant_id, r.id, c.nombres, c.apellidos, c.telefono, m.cargo;
comment on view elius.v_agenda_dia is 'Reservas de hoy con cliente y recursos (panel Operador)';

-- Saldo de cada orden: total, pagado, contra entrega y pendiente (RN-C17)
create view elius.v_saldo_ordenes with (security_invoker = true) as
select o.tenant_id, o.id as orden_id, o.numero, o.estado, o.total,
       coalesce(p.pagado, 0) as pagado,
       coalesce(e.contra_entrega, 0) as contra_entrega,
       greatest(o.total - coalesce(p.pagado, 0) - coalesce(e.contra_entrega, 0), 0) as saldo_pendiente
from elius.ordenes o
left join (select tenant_id, orden_id, sum(monto) as pagado from elius.pagos where estado = 'aprobado'
           group by tenant_id, orden_id) p on p.tenant_id = o.tenant_id and p.orden_id = o.id
left join (select tenant_id, orden_id, sum(cobro_contra_entrega) as contra_entrega from elius.entregas
           where estado <> 'fallida' group by tenant_id, orden_id) e on e.tenant_id = o.tenant_id and e.orden_id = o.id;
comment on view elius.v_saldo_ordenes is 'Total, pagado y saldo de cada orden (RN-C17)';

-- Comprobantes por revisar, primero los que tienen alerta (RN-C16)
create view elius.v_comprobantes_pendientes with (security_invoker = true) as
select cp.tenant_id, cp.id as comprobante_id, cp.creado_en, cp.monto_leido, cp.monto_esperado, cp.coincide,
       cp.app_origen, cp.referencia, cp.destinatario, cp.motivo,
       cp.motivo like 'ALERTA:%' as tiene_alerta,
       o.numero as orden_numero, c.nombres as cliente
from elius.comprobantes_pago cp
join elius.conversaciones cv on cv.tenant_id = cp.tenant_id and cv.id = cp.conversacion_id
join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
join elius.contactos c on c.tenant_id = i.tenant_id and c.id = i.contacto_id
left join elius.ordenes o on o.tenant_id = cp.tenant_id and o.id = cp.orden_id
where cp.veredicto = 'pendiente';
comment on view elius.v_comprobantes_pendientes is 'Comprobantes por aprobar, con alertas (RN-C16)';

-- Recaudos de Factus Pay que siguen abiertos o ya vencieron
create view elius.v_recaudos_abiertos with (security_invoker = true) as
select r.tenant_id, r.id as recaudo_id, r.codigo_referencia, r.monto, r.estado, r.expira_en, r.llave_breb,
       r.expira_en < now() as vencido, o.numero as orden_numero
from elius.recaudos r
join elius.ordenes o on o.tenant_id = r.tenant_id and o.id = r.orden_id
where r.estado = 'listo';
comment on view elius.v_recaudos_abiertos is 'Cobros por llave Bre-B pendientes de pago (RN-C22)';

-- Pendientes del equipo: escalamientos abiertos con su antigüedad
create view elius.v_escalamientos_abiertos with (security_invoker = true) as
select e.tenant_id, e.id as escalamiento_id, e.creado_en, now() - e.creado_en as antiguedad,
       e.motivo, e.resumen, e.asignado_a, m.cargo as asignado_cargo,
       c.nombres as cliente, i.id_externo as numero_cliente
from elius.escalamientos e
join elius.conversaciones cv on cv.tenant_id = e.tenant_id and cv.id = e.conversacion_id
join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
join elius.contactos c on c.tenant_id = i.tenant_id and c.id = i.contacto_id
left join platform.membresias m on m.tenant_id = e.tenant_id and m.id = e.asignado_a
where e.resuelto_en is null;
comment on view elius.v_escalamientos_abiertos is 'Casos que Eli pasó a una persona y siguen abiertos (RN-C18)';

-- Embudo: última fase de cada conversación
create view elius.v_embudo_ultima_fase with (security_invoker = true) as
select distinct on (ee.tenant_id, ee.conversacion_id)
       ee.tenant_id, ee.conversacion_id, ee.fase, ee.ocurrido_en
from elius.eventos_embudo ee
order by ee.tenant_id, ee.conversacion_id, ee.ocurrido_en desc;
comment on view elius.v_embudo_ultima_fase is 'Fase más reciente de cada conversación (métricas de conversión)';

-- Embudo agregado por día y fase (panel Analista)
create view elius.v_embudo_diario with (security_invoker = true) as
select tenant_id, date_trunc('day', ocurrido_en)::date as dia, fase, count(distinct conversacion_id) as conversaciones
from elius.eventos_embudo
group by tenant_id, 2, fase;

-- Ventas por día y canal (panel Analista)
create view elius.v_ventas_diarias with (security_invoker = true) as
select tenant_id, date_trunc('day', colocada_en)::date as dia, canal_venta, tipo_entrega,
       count(*) as ordenes, sum(total) as ventas, round(avg(total), 2) as ticket_promedio
from elius.ordenes
where estado not in ('cotizando', 'cancelada')
group by tenant_id, 2, canal_venta, tipo_entrega;
comment on view elius.v_ventas_diarias is 'Ventas confirmadas por día, canal y tipo de entrega';

-- Ítems más vendidos (panel Analista)
create view elius.v_items_mas_vendidos with (security_invoker = true) as
select oi.tenant_id, ic.id as item_id, ic.nombre, ic.tipo,
       sum(oi.cantidad) as unidades, sum(oi.total_linea) as ventas
from elius.orden_items oi
join elius.ordenes o on o.tenant_id = oi.tenant_id and o.id = oi.orden_id and o.estado not in ('cotizando', 'cancelada')
join elius.items_catalogo ic on ic.tenant_id = oi.tenant_id and ic.id = oi.item_id
group by oi.tenant_id, ic.id, ic.nombre, ic.tipo;

-- Conversaciones: cuántas atiende Eli sola y cuántas escala (panel Analista)
create view elius.v_metricas_conversaciones with (security_invoker = true) as
select cv.tenant_id, date_trunc('day', cv.iniciada_en)::date as dia,
       count(*) as conversaciones,
       count(*) filter (where exists (select 1 from elius.escalamientos e
                                      where e.tenant_id = cv.tenant_id and e.conversacion_id = cv.id)) as escaladas,
       round(100.0 * count(*) filter (where not exists (select 1 from elius.escalamientos e
                                      where e.tenant_id = cv.tenant_id and e.conversacion_id = cv.id)) / count(*), 1)
         as pct_resueltas_por_eli
from elius.conversaciones cv
group by cv.tenant_id, 2;

-- Consumo de IA por mes: tokens, costo y latencia
create view elius.v_consumo_ia_mensual with (security_invoker = true) as
select tenant_id, date_trunc('month', creado_en)::date as mes, modelo,
       count(*) as llamadas, sum(tokens_entrada) as tokens_entrada, sum(tokens_salida) as tokens_salida,
       sum(tokens_cache) as tokens_cache, sum(costo_usd) as costo_usd,
       round(avg(latencia_ms)) as latencia_promedio_ms,
       percentile_cont(0.95) within group (order by latencia_ms) as latencia_p95_ms
from elius.consumos_llm
group by tenant_id, 2, modelo;

-- ---------- 2. Plugins ------------------------------------------------------------

-- Veterinaria: vacunas que vencen en los próximos 30 días (RN-V05, recordatorios de Eli)
create view plugin_vet.v_vacunas_por_vencer with (security_invoker = true) as
select av.tenant_id, m.id as mascota_id, m.nombre as mascota, m.especie,
       ic.nombre as vacuna, av.aplicada_en, av.proxima_dosis_en,
       c.nombres as propietario, c.telefono
from plugin_vet.aplicaciones_vacuna av
join plugin_vet.mascotas m on m.tenant_id = av.tenant_id and m.id = av.mascota_id and m.fallecida_en is null
join elius.items_catalogo ic on ic.tenant_id = av.tenant_id and ic.id = av.vacuna_id
join plugin_vet.propietarios_mascota pm on pm.tenant_id = m.tenant_id and pm.mascota_id = m.id and pm.tipo = 'principal'
join elius.contactos c on c.tenant_id = pm.tenant_id and c.id = pm.contacto_id
where av.proxima_dosis_en between current_date and current_date + 30
  and not exists (select 1 from plugin_vet.aplicaciones_vacuna x
                  where x.tenant_id = av.tenant_id and x.mascota_id = av.mascota_id
                    and x.vacuna_id = av.vacuna_id and x.aplicada_en > av.aplicada_en);

-- Veterinaria: historia clínica completa por mascota (RLS: solo con acceso especial, RN-V03)
create view plugin_vet.v_historia_clinica with (security_invoker = true) as
select rc.tenant_id, a.mascota_id, m.nombre as mascota, a.id as atencion_id, r.inicio as fecha_cita,
       a.motivo, rc.tipo, rc.contenido, rc.registrado_en, rc.corrige_a, mb.cargo as autor_cargo
from plugin_vet.registros_clinicos rc
join plugin_vet.atenciones a on a.tenant_id = rc.tenant_id and a.id = rc.atencion_id
join plugin_vet.mascotas m on m.tenant_id = a.tenant_id and m.id = a.mascota_id
join elius.reservas r on r.tenant_id = a.tenant_id and r.id = a.reserva_id
join platform.membresias mb on mb.tenant_id = rc.tenant_id and mb.id = rc.autor_id;

-- Restaurante: menú del día vigente, solo si el dueño lo confirmó (RN-R11)
create view plugin_restaurant.v_menu_vigente with (security_invoker = true) as
select md.tenant_id, md.fecha, md.precio_base, md.url_foto,
       mi.seccion, mi.posicion, ic.nombre as plato, mi.disponible
from plugin_restaurant.menus_dia md
join plugin_restaurant.menu_dia_items mi on mi.tenant_id = md.tenant_id and mi.menu_id = md.id
join elius.items_catalogo ic on ic.tenant_id = mi.tenant_id and ic.id = mi.item_id
where md.fecha = current_date and md.activo and md.confirmado_en is not null;

-- Restaurante: lo que la cocina tiene pendiente, por estación
create view plugin_restaurant.v_cocina_pendiente with (security_invoker = true) as
select co.tenant_id, ec.nombre as estacion, co.id as comanda_id, o.numero as orden_numero, o.tipo_entrega,
       co.ronda, co.estado, co.enviada_en, now() - co.enviada_en as espera,
       ic.nombre as plato, ci.cantidad, ci.nota_cocina, ci.estado as estado_plato
from plugin_restaurant.comandas co
join plugin_restaurant.estaciones_cocina ec on ec.tenant_id = co.tenant_id and ec.id = co.estacion_id
join elius.ordenes o on o.tenant_id = co.tenant_id and o.id = co.orden_id
join plugin_restaurant.comanda_items ci on ci.tenant_id = co.tenant_id and ci.comanda_id = co.id
join elius.orden_items oi on oi.tenant_id = ci.tenant_id and oi.id = ci.orden_item_id
join elius.items_catalogo ic on ic.tenant_id = oi.tenant_id and ic.id = oi.item_id
where co.estado in ('recibida', 'en_preparacion');

-- Aerolínea: ocupación de cada vuelo
create view plugin_airline.v_ocupacion_vuelos with (security_invoker = true) as
select v.tenant_id, v.id as vuelo_id, v.numero_vuelo, v.salida_programada, v.estado,
       ao.codigo_iata as origen, ad.codigo_iata as destino, an.capacidad,
       coalesce(sum(tv.cupos_vendidos), 0) as vendidos,
       round(100.0 * coalesce(sum(tv.cupos_vendidos), 0) / an.capacidad, 1) as pct_ocupacion
from plugin_airline.vuelos v
join plugin_airline.rutas ru on ru.tenant_id = v.tenant_id and ru.id = v.ruta_id
join plugin_airline.aeropuertos ao on ao.id = ru.origen_id
join plugin_airline.aeropuertos ad on ad.id = ru.destino_id
join plugin_airline.aeronaves an on an.tenant_id = v.tenant_id and an.id = v.aeronave_id
left join plugin_airline.tarifas_vuelo tv on tv.tenant_id = v.tenant_id and tv.vuelo_id = v.id
group by v.tenant_id, v.id, ao.codigo_iata, ad.codigo_iata, an.capacidad;

-- Aerolínea: manifiesto de pasajeros por vuelo
create view plugin_airline.v_manifiesto with (security_invoker = true) as
select tv.tenant_id, tv.vuelo_id, v.numero_vuelo, v.salida_programada,
       c.nombres || coalesce(' ' || c.apellidos, '') as pasajero, rp.tipo_pasajero,
       t.numero_tiquete, t.silla, t.estado as estado_tiquete, t.checkin_en, r.codigo as localizador
from plugin_airline.tiquetes t
join plugin_airline.reserva_pasajeros rp on rp.tenant_id = t.tenant_id and rp.id = t.reserva_pasajero_id
join elius.contactos c on c.tenant_id = rp.tenant_id and c.id = rp.contacto_id
join elius.reservas r on r.tenant_id = rp.tenant_id and r.id = rp.reserva_id
join plugin_airline.tramos_reserva tr on tr.tenant_id = t.tenant_id and tr.id = t.tramo_id
join plugin_airline.tarifas_vuelo tv on tv.tenant_id = tr.tenant_id and tv.id = tr.tarifa_vuelo_id
join plugin_airline.vuelos v on v.tenant_id = tv.tenant_id and v.id = tv.vuelo_id
where t.estado <> 'anulado';

grant select on all tables in schema elius, plugin_vet, plugin_restaurant, plugin_airline to authenticated, service_role, elius_app;

-- ---------- 3. Reportes agregados (usuario elius_consulta y Super Admin) ----------
-- Sin nombres, teléfonos ni contenidos: solo conteos y montos por tenant y mes.
create view reportes.v_uso_por_tenant as
select t.id as tenant_id, t.slug, t.vertical, t.estado, p.codigo as plan, m.mes,
       coalesce(m.conversaciones, 0) as conversaciones, coalesce(m.tokens, 0) as tokens,
       coalesce(m.costo_ia_usd, 0) as costo_ia_usd
from platform.tenants t
join platform.planes p on p.id = t.plan_id
left join (
  select cv.tenant_id, date_trunc('month', cv.iniciada_en)::date as mes, count(*) as conversaciones,
         sum(ll.tokens) as tokens, sum(ll.costo) as costo_ia_usd
  from elius.conversaciones cv
  left join (select tenant_id, conversacion_id, sum(tokens_entrada + tokens_salida) as tokens, sum(costo_usd) as costo
             from elius.consumos_llm group by tenant_id, conversacion_id) ll
    on ll.tenant_id = cv.tenant_id and ll.conversacion_id = cv.id
  group by cv.tenant_id, 2
) m on m.tenant_id = t.id;
comment on view reportes.v_uso_por_tenant is 'Uso mensual por tenant, sin datos personales';

create view reportes.v_ventas_por_tenant as
select o.tenant_id, t.slug, t.vertical, date_trunc('month', o.colocada_en)::date as mes,
       count(*) as ordenes, sum(o.total) as ventas
from elius.ordenes o join platform.tenants t on t.id = o.tenant_id
where o.estado not in ('cotizando', 'cancelada')
group by o.tenant_id, t.slug, t.vertical, 4;

create view reportes.v_resumen_tenants as
select t.id as tenant_id, t.slug, t.vertical, t.estado, p.codigo as plan,
       (select count(*) from platform.membresias m where m.tenant_id = t.id and m.estado = 'activo') as usuarios_activos,
       (select string_agg(pl.codigo, ', ') from platform.tenant_plugins tp join platform.plugins pl on pl.id = tp.plugin_id
         where tp.tenant_id = t.id and tp.habilitado) as plugins,
       t.creado_en
from platform.tenants t join platform.planes p on p.id = t.plan_id;
