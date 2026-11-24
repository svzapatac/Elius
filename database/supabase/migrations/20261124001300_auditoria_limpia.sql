-- 1300 · Auditoría limpia: solo lo que hacen las personas.
--  · El motor de la demostración (reiniciar, cargar caso, siguiente mensaje, cambiar de vista) ya no escribe en la auditoría:
--    app.auditar() omite lo que ocurre dentro de esas llamadas.
--  · La lista ya no muestra el historial anterior a esta limpieza ni las actualizaciones sin cambios reales (siguen guardados).
create or replace function app.auditar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_fila   jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_rol    text  := app.mi_rol();
  v_tenant uuid  := nullif(v_fila ->> 'tenant_id', '')::uuid;
begin
  if current_query() ~* '(siguiente_mensaje_demo|reiniciar_demo|cargar_caso_demo|cambiar_rol_demo|cambiar_tenant)' then
    return null;   -- movimientos automáticos del motor de la demostración
  end if;
  insert into audit.registros_auditoria
    (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_anteriores, datos_nuevos)
  values (
    v_tenant, auth.uid(), coalesce(v_rol, 'sistema'),
    case when v_rol = 'eli' then 'eli' when v_rol = 'soporte' then 'soporte'
         when auth.uid() is null then 'sistema' else 'app' end,
    tg_table_schema, tg_table_name, (v_fila ->> 'id')::uuid, tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return null;
end $$;

create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' and a.datos_nuevos ->> 'bloqueada' = 'true'
              then 'INTENTO BLOQUEADO: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 160) || ' → ' || coalesce(a.datos_nuevos ->> 'motivo', '')
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.tabla = 'mensajes' then 'Respondió a un cliente en una conversación (' || coalesce(a.datos_nuevos ->> 'caracteres', '0') || ' caracteres)'
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id
where a.creado_en >= timestamptz '2026-11-24 07:05:00+00'                 -- historial anterior a la limpieza del 24-nov: no se lista (sigue guardado)
  and not (a.tabla = 'parametros_negocio' and coalesce(a.datos_nuevos ->> 'clave', '') like 'demo\_%')
  and not (a.operacion = 'UPDATE' and not exists (                -- actualizaciones sin ningún dato realmente distinto
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'))
  and not (a.operacion = 'UPDATE' and a.tabla in ('conversaciones', 'identidades_contacto') and not exists (
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k
          and k not in ('actualizado_en', 'ultimo_mensaje_en', 'ultimo_contacto_en')))
  and not (a.tabla = 'membresias' and a.operacion = 'UPDATE' and a.usuario_id::text = a.datos_nuevos ->> 'usuario_id');  -- cambiar de vista o de negocio uno mismo
grant select on elius.v_auditoria to authenticated, service_role, elius_app;
