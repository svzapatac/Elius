-- =============================================================================
-- ELIUS · Migración 0400 · Seguridad: tenant, permisos, JWT y RLS
-- DT-02 (RLS), DT-04 (JWT con tenant), DT-05 (roles generales), DT-06 (rendimiento)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ¿El usuario puede entrar a este tenant?
--    Miembro activo de un tenant activo, o Soporte con autorización vigente (RN-P16).
-- -----------------------------------------------------------------------------
create or replace function app.soporte_autorizado(p_usuario uuid, p_tenant uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from platform.accesos_soporte a
    join platform.asignaciones_plataforma ap on ap.usuario_id = a.usuario_soporte_id
    join platform.roles r on r.id = ap.rol_id and r.codigo = 'soporte'
    where a.usuario_soporte_id = p_usuario and a.tenant_id = p_tenant
      and now() >= a.inicio and now() < a.vence_en and a.revocado_en is null
      and now() >= ap.desde and (ap.hasta is null or now() < ap.hasta));
$$;

create or replace function app.tiene_acceso_tenant(p_usuario uuid, p_tenant uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
           select 1
           from platform.membresias m
           join platform.tenants t on t.id = m.tenant_id
           where m.usuario_id = p_usuario and m.tenant_id = p_tenant
             and m.estado = 'activo' and t.estado in ('prueba', 'activo') and t.eliminado_en is null)
      or app.soporte_autorizado(p_usuario, p_tenant);
$$;

create or replace function app.es_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from platform.asignaciones_plataforma ap
    join platform.roles r on r.id = ap.rol_id and r.codigo = 'super_admin'
    where ap.usuario_id = auth.uid() and now() >= ap.desde and (ap.hasta is null or now() < ap.hasta));
$$;

-- Membresía del usuario en el tenant actual (NULL si no tiene)
create or replace function app.mi_membresia()
returns uuid language sql stable security definer set search_path = '' as $$
  select m.id from platform.membresias m
  where m.tenant_id = app.current_tenant_id() and m.usuario_id = auth.uid() and m.estado = 'activo';
$$;

create or replace function app.mi_rol()
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select r.codigo from platform.membresias m join platform.roles r on r.id = m.rol_id
      where m.tenant_id = app.current_tenant_id() and m.usuario_id = auth.uid() and m.estado = 'activo'),
    case when app.soporte_autorizado(auth.uid(), app.current_tenant_id()) then 'soporte' end,
    case when auth.uid() is null and app.current_tenant_id() is not null then 'backend' end);
$$;

create or replace function app.plugin_habilitado(p_codigo text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from platform.tenant_plugins tp join platform.plugins p on p.id = tp.plugin_id
    where tp.tenant_id = app.current_tenant_id() and p.codigo = p_codigo and tp.habilitado and p.activo);
$$;

-- -----------------------------------------------------------------------------
-- 2. Nivel de permiso del usuario actual sobre un módulo: 0 nada, 1 lectura,
--    2 escritura, 3 total. Suma tres fuentes y toma la mayor:
--      a) el rol general de su membresía (platform.rol_permisos)
--      b) los accesos especiales que le activó el Administrador (escritura)
--      c) Soporte con autorización vigente: 'con_autorizacion' equivale a total
--    El backend de confianza (sin usuario, tenant fijado) tiene nivel total.
--    Si el permiso es de un plugin que el tenant no tiene habilitado: 0 (RN-P09).
-- -----------------------------------------------------------------------------
create or replace function app.nivel_permiso(p_codigo text)
returns int language plpgsql stable security definer set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_uid    uuid := auth.uid();
  v_perm   record;
  v_nivel  int := 0;
begin
  if v_tenant is null then
    return 0;
  end if;
  select p.id, p.plugin_id, pl.codigo as plugin_codigo into v_perm
  from platform.permisos p left join platform.plugins pl on pl.id = p.plugin_id
  where p.codigo = p_codigo;
  if not found then
    return 0;
  end if;
  if v_perm.plugin_id is not null and not app.plugin_habilitado(v_perm.plugin_codigo) then
    return 0;
  end if;
  if v_uid is null then
    return 3;  -- backend de confianza (service_role / elius_app) dentro de un solo tenant
  end if;

  select coalesce(max(case rp.nivel when 'lectura' then 1 when 'escritura' then 2 when 'total' then 3 else 0 end), 0)
    into v_nivel
  from platform.membresias m
  join platform.rol_permisos rp on rp.rol_id = m.rol_id and rp.permiso_id = v_perm.id
  where m.tenant_id = v_tenant and m.usuario_id = v_uid and m.estado = 'activo';

  if v_nivel < 2 and exists (
       select 1 from platform.membresias m
       join platform.accesos_especiales ae on ae.membresia_id = m.id and ae.permiso_id = v_perm.id
       where m.tenant_id = v_tenant and m.usuario_id = v_uid and m.estado = 'activo'
         and (ae.vence_en is null or ae.vence_en > now())) then
    v_nivel := 2;
  end if;

  if v_nivel < 3 and app.soporte_autorizado(v_uid, v_tenant) and exists (
       select 1 from platform.rol_permisos rp join platform.roles r on r.id = rp.rol_id
       where r.codigo = 'soporte' and rp.permiso_id = v_perm.id and rp.nivel = 'con_autorizacion') then
    v_nivel := 3;
  end if;
  return v_nivel;
end $$;

create or replace function app.puede(p_codigo text, p_nivel text)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.nivel_permiso(p_codigo) >= case p_nivel when 'lectura' then 1 when 'escritura' then 2 when 'total' then 3 else 99 end;
$$;

comment on function app.puede(text, text) is 'true si el usuario actual tiene al menos ese nivel (lectura, escritura, total) en el módulo';

-- -----------------------------------------------------------------------------
-- 3. Hook de Supabase Auth: agrega al JWT el tenant activo y el rol (DT-04)
--    Se activa en Supabase: Authentication → Hooks → Custom Access Token.
-- -----------------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid    uuid  := (event ->> 'user_id')::uuid;
  v_claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_tenant uuid;
  v_rol    text;
begin
  select m.tenant_id, r.codigo into v_tenant, v_rol
  from platform.membresias m
  join platform.roles r on r.id = m.rol_id
  join platform.tenants t on t.id = m.tenant_id
  where m.usuario_id = v_uid and m.estado = 'activo' and t.estado in ('prueba', 'activo')
  order by m.es_predeterminada desc, m.fecha_ingreso
  limit 1;

  if v_tenant is not null then
    v_claims := v_claims || jsonb_build_object('tenant_id', v_tenant, 'tenant_rol', v_rol);
  else
    v_claims := v_claims - 'tenant_id' - 'tenant_rol';
  end if;
  return jsonb_set(event, '{claims}', v_claims);
end $$;

revoke execute on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- -----------------------------------------------------------------------------
-- 4. Plantilla de políticas para tablas de negocio (modelo general y plugins)
--    select: lectura · insert/update: escritura · delete: total
--    (select …) hace que Postgres calcule la función una sola vez por consulta (DT-06)
-- -----------------------------------------------------------------------------
create or replace function app.aplicar_rls(p_tabla regclass, p_permiso text)
returns void language plpgsql set search_path = '' as $$
declare
  v_t text := p_tabla::text;
  v_n text := replace(split_part(v_t, '.', 2), '"', '');
  v_cond text := format('tenant_id = (select app.current_tenant_id())');
begin
  execute format('alter table %s enable row level security', v_t);
  execute format('create policy %I on %s for select using (%s and (select app.puede(%L, ''lectura'')))',
                 'sel_' || v_n, v_t, v_cond, p_permiso);
  execute format('create policy %I on %s for insert with check (%s and (select app.puede(%L, ''escritura'')))',
                 'ins_' || v_n, v_t, v_cond, p_permiso);
  execute format('create policy %I on %s for update using (%s and (select app.puede(%L, ''escritura''))) with check (%s)',
                 'upd_' || v_n, v_t, v_cond, p_permiso, v_cond);
  execute format('create policy %I on %s for delete using (%s and (select app.puede(%L, ''total'')))',
                 'del_' || v_n, v_t, v_cond, p_permiso);
end $$;

-- Tabla → permiso (módulo). Las tablas de plugin usan permisos del plugin, así que
-- además exigen que el plugin esté habilitado para el tenant (RN-P09).
do $$
declare
  r record;
begin
  for r in select * from (values
    -- elius: contactos y conversaciones
    ('elius.contactos', 'contactos'), ('elius.direcciones', 'contactos'), ('elius.consentimientos', 'contactos'),
    ('elius.identidades_contacto', 'conversaciones'), ('elius.conversaciones', 'conversaciones'),
    ('elius.mensajes', 'conversaciones'), ('elius.escalamientos', 'conversaciones'),
    ('elius.consumos_llm', 'reportes'), ('elius.eventos_embudo', 'reportes'),
    -- elius: configuración del negocio y de Eli
    ('elius.agentes', 'configuracion'), ('elius.canales', 'configuracion'), ('elius.parametros_negocio', 'configuracion'),
    ('elius.errores_agente', 'configuracion'), ('elius.eventos_salida', 'configuracion'),
    ('elius.pasarelas_pago', 'configuracion'),
    -- elius: catálogo
    ('elius.categorias_catalogo', 'catalogo'), ('elius.items_catalogo', 'catalogo'),
    ('elius.item_adicionales', 'catalogo'), ('elius.medios_item', 'catalogo'),
    -- elius: reservas
    ('elius.recursos', 'reservas'), ('elius.horarios_atencion', 'reservas'),
    ('elius.reservas', 'reservas'), ('elius.asignaciones_recurso', 'reservas'),
    -- elius: órdenes y pagos
    ('elius.ordenes', 'ordenes'), ('elius.orden_items', 'ordenes'), ('elius.entregas', 'ordenes'),
    ('elius.pagos', 'pagos'), ('elius.comprobantes_pago', 'pagos'), ('elius.recaudos', 'pagos'),
    ('elius.notificaciones_pasarela', 'pagos'),
    -- elius: conocimiento de Eli
    ('elius.documentos_conocimiento', 'conocimiento'), ('elius.fragmentos_conocimiento', 'conocimiento'),
    -- ext
    ('ext.instalaciones_extension', 'ext'), ('ext.sitios_autorizados', 'ext'),
    ('ext.conversaciones_capturadas', 'ext'), ('ext.mensajes_capturados', 'ext'),
    ('ext.patrones', 'ext'), ('ext.evidencias_patron', 'ext'),
    -- plugin veterinaria
    ('plugin_vet.mascotas', 'vet.pacientes'), ('plugin_vet.propietarios_mascota', 'vet.pacientes'),
    ('plugin_vet.atenciones', 'vet.pacientes'), ('plugin_vet.aplicaciones_vacuna', 'vet.pacientes'),
    ('plugin_vet.registros_clinicos', 'vet.historia_clinica'),
    -- plugin restaurante
    ('plugin_restaurant.alergenos', 'restaurant.menu'), ('plugin_restaurant.item_alergenos', 'restaurant.menu'),
    ('plugin_restaurant.grupos_modificador', 'restaurant.menu'), ('plugin_restaurant.opciones_modificador', 'restaurant.menu'),
    ('plugin_restaurant.item_grupos_modificador', 'restaurant.menu'),
    ('plugin_restaurant.menus_dia', 'restaurant.menu'), ('plugin_restaurant.menu_dia_items', 'restaurant.menu'),
    ('plugin_restaurant.orden_item_opciones', 'restaurant.cocina'), ('plugin_restaurant.estaciones_cocina', 'restaurant.cocina'),
    ('plugin_restaurant.comandas', 'restaurant.cocina'), ('plugin_restaurant.comanda_items', 'restaurant.cocina'),
    ('plugin_restaurant.celebraciones', 'restaurant.cocina'),
    -- plugin aerolínea
    ('plugin_airline.aeronaves', 'airline.vuelos'), ('plugin_airline.rutas', 'airline.vuelos'),
    ('plugin_airline.vuelos', 'airline.vuelos'), ('plugin_airline.tarifas_vuelo', 'airline.vuelos'),
    ('plugin_airline.reserva_pasajeros', 'airline.reservas'), ('plugin_airline.tramos_reserva', 'airline.reservas'),
    ('plugin_airline.tiquetes', 'airline.reservas'), ('plugin_airline.equipajes', 'airline.reservas')
  ) as t(tabla, permiso)
  loop
    perform app.aplicar_rls(r.tabla::regclass, r.permiso);
  end loop;
end $$;

-- Notificaciones push: cada usuario solo administra las de sus dispositivos
alter table elius.suscripciones_push enable row level security;
create policy push_propias on elius.suscripciones_push for all
  using (tenant_id = (select app.current_tenant_id()) and membresia_id = (select app.mi_membresia()))
  with check (tenant_id = (select app.current_tenant_id()) and membresia_id = (select app.mi_membresia()));
create policy push_backend on elius.suscripciones_push for select
  using (auth.uid() is null and tenant_id = (select app.current_tenant_id()));

-- RN-E01: lo capturado por la extensión solo lo ve quien lo capturó, salvo nivel total
-- (política RESTRICTIVA: se suma con AND a las políticas anteriores)
create policy solo_quien_captura on ext.conversaciones_capturadas as restrictive for select
  using (
    (select app.puede('ext', 'total'))
    or instalacion_id in (select i.id from ext.instalaciones_extension i where i.membresia_id = (select app.mi_membresia()))
  );
create policy solo_quien_captura on ext.mensajes_capturados as restrictive for select
  using (
    (select app.puede('ext', 'total'))
    or conversacion_id in (
      select c.id from ext.conversaciones_capturadas c
      join ext.instalaciones_extension i on i.id = c.instalacion_id
      where i.membresia_id = (select app.mi_membresia()))
  );

-- Aeropuertos: catálogo global de solo lectura (RN-A01)
alter table plugin_airline.aeropuertos enable row level security;
create policy aeropuertos_lectura on plugin_airline.aeropuertos for select using (auth.uid() is not null or auth.role() = 'service_role' or session_user = 'elius_app');
create policy aeropuertos_admin on plugin_airline.aeropuertos for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));

-- -----------------------------------------------------------------------------
-- 5. Políticas del esquema platform (lógica del tenant)
-- -----------------------------------------------------------------------------
alter table platform.planes                  enable row level security;
alter table platform.tenants                 enable row level security;
alter table platform.roles                   enable row level security;
alter table platform.permisos                enable row level security;
alter table platform.plugins                 enable row level security;
alter table platform.rol_permisos            enable row level security;
alter table platform.membresias              enable row level security;
alter table platform.accesos_especiales      enable row level security;
alter table platform.asignaciones_plataforma enable row level security;
alter table platform.tenant_plugins          enable row level security;
alter table platform.accesos_soporte         enable row level security;
alter table platform.invitaciones            enable row level security;
alter table platform.llaves_api              enable row level security;
alter table platform.consumos_periodo        enable row level security;
alter table audit.registros_auditoria        enable row level security;

-- Catálogos globales: todos los autenticados leen; solo el Super Admin cambia
create policy planes_lectura   on platform.planes       for select using (auth.uid() is not null);
create policy planes_admin     on platform.planes       for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));
create policy roles_lectura    on platform.roles        for select using (auth.uid() is not null);
create policy roles_admin      on platform.roles        for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));
create policy permisos_lectura on platform.permisos     for select using (auth.uid() is not null);
create policy permisos_admin   on platform.permisos     for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));
create policy plugins_lectura  on platform.plugins      for select using (auth.uid() is not null);
create policy plugins_admin    on platform.plugins      for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));
create policy rol_permisos_lectura on platform.rol_permisos for select using (auth.uid() is not null);
create policy rol_permisos_admin   on platform.rol_permisos for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));

-- Tenants: cada usuario ve los suyos (para cambiar de tenant); el Administrador edita el actual
create policy tenants_mios on platform.tenants for select
  using (id in (select m.tenant_id from platform.membresias m where m.usuario_id = auth.uid() and m.estado = 'activo')
         or id = (select app.current_tenant_id()) or (select app.es_super_admin()));
create policy tenants_editar on platform.tenants for update
  using (id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')))
  with check (id = (select app.current_tenant_id()));
create policy tenants_super_admin on platform.tenants for all
  using ((select app.es_super_admin())) with check ((select app.es_super_admin()));

-- Membresías: el usuario ve las suyas; quien tiene permiso de usuarios ve y gestiona las del tenant
create policy membresias_propias on platform.membresias for select using (usuario_id = auth.uid());
create policy membresias_tenant on platform.membresias for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'lectura')));
create policy membresias_gestion on platform.membresias for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')));

create policy accesos_especiales_tenant on platform.accesos_especiales for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'lectura')));
create policy accesos_especiales_gestion on platform.accesos_especiales for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')));

create policy asignaciones_propias on platform.asignaciones_plataforma for select
  using (usuario_id = auth.uid() or (select app.es_super_admin()));
create policy asignaciones_admin on platform.asignaciones_plataforma for all
  using ((select app.es_super_admin())) with check ((select app.es_super_admin()));

create policy tenant_plugins_lectura on platform.tenant_plugins for select
  using (tenant_id = (select app.current_tenant_id()) or (select app.es_super_admin()));
create policy tenant_plugins_gestion on platform.tenant_plugins for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')));

-- Accesos de soporte: los autoriza el Administrador; Soporte ve los que le dieron
create policy accesos_soporte_propios on platform.accesos_soporte for select using (usuario_soporte_id = auth.uid());
create policy accesos_soporte_gestion on platform.accesos_soporte for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total'))
              and autorizado_por = auth.uid());

create policy invitaciones_gestion on platform.invitaciones for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')));

create policy llaves_api_gestion on platform.llaves_api for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')));

create policy consumos_lectura on platform.consumos_periodo for select
  using ((tenant_id = (select app.current_tenant_id()) and (select app.puede('reportes', 'lectura'))) or (select app.es_super_admin()));
create policy consumos_backend on platform.consumos_periodo for all
  using (auth.uid() is null and tenant_id = (select app.current_tenant_id()))
  with check (auth.uid() is null and tenant_id = (select app.current_tenant_id()));

-- Auditoría: solo lectura. La escriben los triggers (security definer), nunca un usuario.
create policy auditoria_tenant on audit.registros_auditoria for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('auditoria', 'lectura')));
create policy auditoria_plataforma on audit.registros_auditoria for select
  using ((select app.es_super_admin()));

-- -----------------------------------------------------------------------------
-- 6. Permisos de los roles de la API de Supabase (las políticas RLS hacen el filtro)
-- -----------------------------------------------------------------------------
grant usage on schema platform, elius, ext, audit, app, plugin_vet, plugin_restaurant, plugin_airline
  to authenticated, service_role, elius_app;
grant select, insert, update, delete on all tables in schema platform, elius, ext, plugin_vet, plugin_restaurant, plugin_airline
  to authenticated, service_role, elius_app;
grant select on audit.registros_auditoria to authenticated, service_role, elius_app;
grant execute on all functions in schema app to authenticated, service_role, elius_app;
revoke execute on function app.aplicar_rls(regclass, text) from public, anon, authenticated, service_role, elius_app;
revoke all on schema reportes from public;
-- anon (sin iniciar sesión) no recibe ningún permiso sobre datos
