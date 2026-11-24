-- =============================================================================
-- 1400 · Validaciones de datos, auditoría consultable y reportes por mes
-- =============================================================================

-- ---------- 1. Validaciones (NOT VALID: se aplican a todo dato nuevo sin reventar el histórico) ----------
-- Correo: debe traer dominio completo (usuario@dominio.ext)
alter table elius.contactos drop constraint if exists ck_contactos_email;
alter table elius.contactos add constraint ck_contactos_email
  check (email is null or email ~* '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$') not valid;
alter table platform.invitaciones drop constraint if exists ck_invitaciones_email;
alter table platform.invitaciones add constraint ck_invitaciones_email
  check (email ~* '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$') not valid;

-- Documento: cédula, tarjeta, NIT… solo números; el pasaporte admite letras y números
alter table elius.contactos add constraint ck_contactos_tipo_documento
  check (tipo_documento is null or tipo_documento in ('CC', 'CE', 'TI', 'RC', 'NIT', 'PA')) not valid;
alter table elius.contactos add constraint ck_contactos_documento
  check (numero_documento is null
         or (tipo_documento = 'PA' and numero_documento ~ '^[A-Za-z0-9]{5,15}$')
         or (coalesce(tipo_documento, 'CC') <> 'PA' and numero_documento ~ '^[0-9]{5,15}$')) not valid;

-- Precios e impuestos: ya existen ck_items_precio (>= 0), ck_items_impuesto (0 a 100) y ck_items_duracion (> 0)
comment on constraint ck_items_precio on elius.items_catalogo is 'El precio de venta no puede ser negativo';
comment on constraint ck_contactos_documento on elius.contactos is 'Cédula y demás documentos: solo números (pasaporte: letras y números)';
comment on constraint ck_contactos_email on elius.contactos is 'Correo con dominio completo';

-- ---------- 2. Auditoría consultable desde el panel (el esquema audit no está expuesto a la API) ----------
create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id;
comment on view elius.v_auditoria is 'Bitácora legible: quién (cargo y rol), qué tabla, qué operación y qué campos cambiaron o qué consulta ejecutó';
grant select on elius.v_auditoria to authenticated, service_role, elius_app;

-- ---------- 3. Vistas reutilizables por mes (se construyen sobre las vistas diarias ya existentes) ----------
create or replace view elius.v_resumen_mensual with (security_invoker = true) as
select tenant_id, mes,
       coalesce(v.ordenes, 0) as ordenes, coalesce(v.ventas, 0) as ventas, v.ticket_promedio,
       coalesce(c.conversaciones, 0) as conversaciones, coalesce(c.escaladas, 0) as escaladas,
       case when coalesce(c.conversaciones, 0) > 0
            then round(100.0 * (c.conversaciones - c.escaladas) / c.conversaciones, 1) end as pct_resueltas_por_eli
from (select tenant_id, date_trunc('month', dia)::date as mes, sum(ordenes) as ordenes, sum(ventas) as ventas,
             round(sum(ventas) / nullif(sum(ordenes), 0), 2) as ticket_promedio
      from elius.v_ventas_diarias group by 1, 2) v
full join (select tenant_id, date_trunc('month', dia)::date as mes, sum(conversaciones) as conversaciones, sum(escaladas) as escaladas
           from elius.v_metricas_conversaciones group by 1, 2) c using (tenant_id, mes);
comment on view elius.v_resumen_mensual is 'Un renglón por mes: órdenes, ventas, ticket promedio y atención de Eli (reutiliza v_ventas_diarias y v_metricas_conversaciones)';

create or replace view elius.v_items_mas_vendidos_mensual with (security_invoker = true) as
select oi.tenant_id, date_trunc('month', o.colocada_en)::date as mes, ic.id as item_id, ic.nombre, ic.tipo,
       sum(oi.cantidad) as unidades, sum(oi.total_linea) as ventas
from elius.orden_items oi
join elius.ordenes o on o.tenant_id = oi.tenant_id and o.id = oi.orden_id and o.estado not in ('cotizando', 'cancelada')
join elius.items_catalogo ic on ic.tenant_id = oi.tenant_id and ic.id = oi.item_id
group by oi.tenant_id, 2, ic.id, ic.nombre, ic.tipo;
comment on view elius.v_items_mas_vendidos_mensual is 'Ítems más vendidos por mes (filtra por la columna mes)';
grant select on elius.v_resumen_mensual, elius.v_items_mas_vendidos_mensual to authenticated, service_role, elius_app;
