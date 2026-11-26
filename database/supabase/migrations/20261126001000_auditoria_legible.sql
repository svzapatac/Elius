-- =============================================================================
-- 4300 · Auditoría legible: cada acción de negocio dice qué pasó (comprobantes, pagos, tickets, reservas, pedidos, precios, Papelera)
--   La bitácora ya guardaba todo; la vista ahora lo describe en una frase en lugar de "Registro nuevo" o "Cambió: columnas".
-- =============================================================================
create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' and a.datos_nuevos ->> 'bloqueada' = 'true'
              then 'INTENTO BLOQUEADO: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 160) || ' → ' || coalesce(a.datos_nuevos ->> 'motivo', '')
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.tabla = 'mensajes' then 'Respondió a un cliente en una conversación (' || coalesce(a.datos_nuevos ->> 'caracteres', '0') || ' caracteres)'
         when a.tabla = 'comprobantes_pago' and a.operacion = 'INSERT'
              then 'Llegó un comprobante de $' || coalesce(a.datos_nuevos ->> 'monto_leido', '?') || ' (esperado $' || coalesce(a.datos_nuevos ->> 'monto_esperado', '?') || ')'
                   || coalesce(' · ' || nullif(a.datos_nuevos ->> 'motivo', ''), '')
         when a.tabla = 'comprobantes_pago' and a.operacion = 'UPDATE' and a.datos_nuevos ->> 'veredicto' is distinct from a.datos_anteriores ->> 'veredicto'
              then case a.datos_nuevos ->> 'veredicto' when 'aprobado' then 'Aprobó' when 'rechazado' then 'Rechazó' else 'Cambió' end
                   || ' el comprobante de $' || coalesce(a.datos_nuevos ->> 'monto_leido', '?')
         when a.tabla = 'pagos' and a.operacion = 'INSERT'
              then 'Registró un pago de $' || coalesce(a.datos_nuevos ->> 'monto', '?') || ' (' || coalesce(a.datos_nuevos ->> 'metodo', '?') || ')'
         when a.tabla = 'tickets' and a.operacion = 'INSERT'
              then 'Creó el ticket ' || coalesce(a.datos_nuevos ->> 'codigo', '') || ' (' || coalesce(a.datos_nuevos ->> 'categoria', '') || ', prioridad ' || coalesce(a.datos_nuevos ->> 'prioridad', '') || '): ' || left(coalesce(a.datos_nuevos ->> 'asunto', ''), 80)
         when a.tabla = 'tickets' and a.operacion = 'UPDATE' and a.datos_nuevos ->> 'estado' is distinct from a.datos_anteriores ->> 'estado'
              then 'Ticket ' || coalesce(a.datos_nuevos ->> 'codigo', '') || ': ' || coalesce(a.datos_anteriores ->> 'estado', '') || ' → ' || coalesce(a.datos_nuevos ->> 'estado', '')
         when a.tabla = 'ticket_notas' and a.operacion = 'INSERT' then 'Agregó una nota a un ticket'
         when a.tabla = 'reservas' and a.operacion = 'UPDATE' and a.datos_nuevos ->> 'estado' is distinct from a.datos_anteriores ->> 'estado'
              then 'Reserva ' || coalesce(a.datos_nuevos ->> 'codigo', '') || ': ' || coalesce(a.datos_anteriores ->> 'estado', '') || ' → ' || coalesce(a.datos_nuevos ->> 'estado', '')
         when a.tabla = 'reservas' and a.operacion = 'UPDATE' and a.datos_nuevos ->> 'responsable_id' is distinct from a.datos_anteriores ->> 'responsable_id'
              then case when a.datos_nuevos ->> 'responsable_id' is null then 'Liberó la reserva ' else 'Tomó la reserva ' end || coalesce(a.datos_nuevos ->> 'codigo', '')
         when a.tabla = 'ordenes' and a.operacion = 'UPDATE' and a.datos_nuevos ->> 'estado' is distinct from a.datos_anteriores ->> 'estado'
              then 'Pedido #' || coalesce(a.datos_nuevos ->> 'numero', '') || ': ' || coalesce(a.datos_anteriores ->> 'estado', '') || ' → ' || coalesce(a.datos_nuevos ->> 'estado', '')
         when a.tabla = 'items_catalogo' and a.operacion = 'UPDATE' and a.datos_nuevos ->> 'precio' is distinct from a.datos_anteriores ->> 'precio'
              then 'Cambió el precio de ' || coalesce(a.datos_nuevos ->> 'nombre', '') || ' de $' || coalesce(a.datos_anteriores ->> 'precio', '?') || ' a $' || coalesce(a.datos_nuevos ->> 'precio', '?')
         when a.operacion = 'UPDATE' and a.datos_anteriores ->> 'eliminado_en' is null and a.datos_nuevos ->> 'eliminado_en' is not null
              then 'Envió a la Papelera un registro de ' || a.tabla
         when a.operacion = 'UPDATE' and a.datos_anteriores ->> 'eliminado_en' is not null and a.datos_nuevos ->> 'eliminado_en' is null
              then 'Restauró de la Papelera un registro de ' || a.tabla
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos,
       a.instancia, a.base_datos, a.puerto, a.ip_cliente, a.login_bd, a.aplicacion, a.usuario_email
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id
where a.creado_en >= timestamptz '2026-11-24 07:05:00+00'
  and not (a.tabla = 'parametros_negocio' and coalesce(a.datos_nuevos ->> 'clave', '') like 'demo\_%')
  and not (a.operacion = 'UPDATE' and not exists (
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'))
  and not (a.operacion = 'UPDATE' and a.tabla in ('conversaciones', 'identidades_contacto') and not exists (
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k
          and k not in ('actualizado_en', 'ultimo_mensaje_en', 'ultimo_contacto_en')))
  and not (a.tabla = 'membresias' and a.operacion = 'UPDATE' and a.usuario_id::text = a.datos_nuevos ->> 'usuario_id');
grant select on elius.v_auditoria to authenticated, service_role, elius_app;
