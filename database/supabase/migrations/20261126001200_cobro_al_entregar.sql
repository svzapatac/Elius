-- =============================================================================
-- 4400 · Cobro del saldo en efectivo al entregar + vista del estado de pago
--   · T57: cuando el Operador marca el pedido como «entregada», el saldo que quedó «contra entrega» se da por cobrado:
--     la entrega pasa a «entregada» y se registra un pago en efectivo por ese monto.
--   · v_estado_pago_pedidos: por pedido, cuánto se pagó, cuánto falta y una frase clara
--     («Falta cobrar $X en efectivo al entregar» / «Pago finalizado · saldo $0»).
-- =============================================================================
create or replace function app.cobrar_al_entregar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare e record;
begin
  if new.estado = 'entregada' and old.estado is distinct from 'entregada' then
    for e in select id, cobro_contra_entrega from elius.entregas
             where tenant_id = new.tenant_id and orden_id = new.id and estado not in ('fallida', 'entregada') loop
      if e.cobro_contra_entrega > 0 then
        insert into elius.pagos (tenant_id, orden_id, metodo, proveedor, monto, estado)
        values (new.tenant_id, new.id, 'efectivo', 'Contra entrega', e.cobro_contra_entrega, 'aprobado');
      end if;
      update elius.entregas set estado = 'entregada', entregada_en = now() where tenant_id = new.tenant_id and id = e.id;
    end loop;
  end if;
  return null;
end $$;
create trigger t57_cobrar_al_entregar after update of estado on elius.ordenes
  for each row execute function app.cobrar_al_entregar();

comment on trigger t57_cobrar_al_entregar on elius.ordenes is 'T57 · al marcar el pedido entregado, el saldo contra entrega se cobra en efectivo y la entrega queda entregada';

create or replace view elius.v_estado_pago_pedidos with (security_invoker = true) as
select o.tenant_id, o.id as orden_id, o.numero, o.estado as estado_pedido, o.total,
       coalesce(p.pagado, 0) as pagado,
       greatest(o.total - coalesce(p.pagado, 0), 0) as saldo,
       case
         when o.estado = 'cancelada' then 'Pedido cancelado'
         when o.total - coalesce(p.pagado, 0) <= 0 then 'Pago finalizado · saldo $0'
         when exists (select 1 from elius.entregas e where e.tenant_id = o.tenant_id and e.orden_id = o.id and e.estado not in ('fallida', 'entregada') and e.cobro_contra_entrega > 0)
              then 'Falta cobrar $' || round(o.total - coalesce(p.pagado, 0))::text || ' en efectivo al entregar'
         when coalesce(p.pagado, 0) > 0 then 'Pago parcial: faltan $' || round(o.total - coalesce(p.pagado, 0))::text
         else 'Sin pago: debe $' || round(o.total)::text
       end as estado_pago
from elius.ordenes o
left join (select tenant_id, orden_id, sum(monto) as pagado from elius.pagos where estado = 'aprobado' group by tenant_id, orden_id) p
  on p.tenant_id = o.tenant_id and p.orden_id = o.id
where o.eliminado_en is null;
grant select on elius.v_estado_pago_pedidos to authenticated, service_role, elius_app;
comment on view elius.v_estado_pago_pedidos is 'Estado de pago de cada pedido: pagado, saldo y frase clara (falta cobrar en efectivo / pago finalizado)';
