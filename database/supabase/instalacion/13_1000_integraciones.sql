-- =============================================================================
-- ELIUS · Migración 1000 · Funciones para las Edge Functions (solo service_role)
-- Factus Pay (DT-18) y secretos en Supabase Vault.
-- Viven en el esquema elius (expuesto en la API) para que la Edge Function pueda
-- llamarlas con supabase.rpc(), pero solo service_role tiene permiso de ejecutarlas.
-- Llevan el prefijo srv_ para distinguirlas de las que usan los paneles.
-- =============================================================================

-- Lee un secreto de Supabase Vault (credenciales de Factus, token de WhatsApp…).
-- Solo la usa el backend; nunca un usuario. En un PostgreSQL sin Vault la función
-- se crea igual (plpgsql) pero no se puede ejecutar.
create or replace function elius.srv_secreto(p_id uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  execute 'select decrypted_secret from vault.decrypted_secrets where id = $1' into v using p_id;
  return v;
end $$;

-- Rota un secreto (por ejemplo, el token de Factus cuando la API responde 401)
create or replace function elius.srv_actualizar_secreto(p_id uuid, p_valor text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  execute 'select vault.update_secret($1, $2)' using p_id, p_valor;
end $$;

-- Datos que la Edge Function del webhook necesita de la pasarela (sin exponerla a usuarios)
create or replace function elius.srv_pasarela_webhook(p_pasarela uuid)
returns table (tenant_id uuid, ambiente text, referencia_clave_webhook uuid, referencia_credenciales uuid, activa boolean)
language sql stable security definer set search_path = '' as $$
  select p.tenant_id, p.ambiente, p.referencia_clave_webhook, p.referencia_credenciales, p.activa
  from elius.pasarelas_pago p where p.id = p_pasarela;
$$;

-- Punto de entrada del webhook de Factus para la Edge Function.
-- Fija el tenant de la pasarela solo dentro de esta transacción y aplica el pago.
create or replace function elius.webhook_factus(p_pasarela uuid, p_clave_valida boolean, p_carga jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  select tenant_id into v_tenant from elius.pasarelas_pago where id = p_pasarela;
  if v_tenant is null then
    return 'sin_recaudo';
  end if;
  perform set_config('app.tenant_id', v_tenant::text, true);
  return elius.procesar_webhook_factus(p_pasarela, p_clave_valida, p_carga);
end $$;

revoke execute on function elius.srv_secreto(uuid), elius.srv_actualizar_secreto(uuid, text), elius.srv_pasarela_webhook(uuid),
  elius.webhook_factus(uuid, boolean, jsonb) from public, anon, authenticated, elius_app;
grant execute on function elius.srv_secreto(uuid), elius.srv_actualizar_secreto(uuid, text), elius.srv_pasarela_webhook(uuid),
  elius.webhook_factus(uuid, boolean, jsonb) to service_role;
