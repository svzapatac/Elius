-- 3300 · Lo que hace Soporte con los eventos de salida también queda en la auditoría.
-- elius.eventos_salida no tiene disparador de auditoría (la escribe el sistema en gran volumen); por eso el reintento
-- manual de una persona se registra de forma explícita.
create or replace function elius.soporte_reintentar_evento(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_rol text := app.mi_rol(); v_tenant uuid := app.current_tenant_id(); v_tipo text;
begin
  if v_rol is null or v_rol not in ('soporte', 'administrador') then raise exception 'Solo Soporte o el Administrador' using errcode = '42501'; end if;
  update elius.eventos_salida set estado = 'pendiente'
   where id = p_id and tenant_id = v_tenant and estado = 'fallido'
   returning tipo_evento into v_tipo;
  if not found then raise exception 'El evento no existe o no está fallido'; end if;
  insert into audit.registros_auditoria (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_anteriores, datos_nuevos)
  values (v_tenant, auth.uid(), v_rol, case when v_rol = 'soporte' then 'soporte' else 'app' end, 'elius', 'eventos_salida', p_id, 'UPDATE',
          jsonb_build_object('estado', 'fallido', 'tipo_evento', v_tipo), jsonb_build_object('estado', 'pendiente', 'tipo_evento', v_tipo));
end $$;
revoke execute on function elius.soporte_reintentar_evento(uuid) from public, anon;
grant execute on function elius.soporte_reintentar_evento(uuid) to authenticated;
