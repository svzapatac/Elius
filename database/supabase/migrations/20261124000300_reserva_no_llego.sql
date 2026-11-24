-- =============================================================================
-- 1500 · El equipo registra que el cliente NO llegó (complemento de marcar_llegada)
-- Pasa la reserva a "no_asistio" y libera la mesa, consultorio o recurso asignado.
-- =============================================================================
create or replace function elius.marcar_no_llegada(p_reserva uuid)
returns void language plpgsql set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id();
begin
  update elius.reservas set estado = 'no_asistio', visto = true
  where id = p_reserva and tenant_id = v_tenant and estado = 'confirmada' and llegada_en is null;
  if found then
    update elius.asignaciones_recurso set estado = 'liberada' where tenant_id = v_tenant and reserva_id = p_reserva;
  end if;
end $$;
