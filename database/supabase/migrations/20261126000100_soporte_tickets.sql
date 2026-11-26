-- =============================================================================
-- 4000 · Panel de Soporte con TICKETS, todo por vistas y procedimientos (sin tocar tablas)
--   · Tickets con código (TCK-0001) y categoría (01 General … 07 Integraciones), historial y notas.
--   · Soporte ve: tickets pendientes, historial de tickets, clientes (datos enmascarados), usuarios (sin claves) y el manual de soporte.
--   · Soporte actúa con procedimientos: tomar, anotar, resolver, corregir un dato de un cliente (con motivo), crear usuarios con su rol,
--     restablecer una clave (se muestra una sola vez) y cambiar rol o estado. Todo queda en la auditoría con rol «soporte».
--   · Las tablas nuevas no tienen políticas: nadie las lee ni las escribe directamente, solo las vistas y funciones definidas aquí.
--   · Los problemas que reporta el Trabajador pasan a ser tickets.
-- =============================================================================

-- 1. Tablas ------------------------------------------------------------------------------------------------------------
create table elius.tickets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id() references platform.tenants (id) on delete cascade,
  numero int not null,
  codigo text not null,
  categoria text not null constraint ck_tickets_categoria check (categoria in ('01', '02', '03', '04', '05', '06', '07')),
  prioridad text not null default 'media' constraint ck_tickets_prioridad check (prioridad in ('baja', 'media', 'alta', 'critica')),
  estado text not null default 'abierto' constraint ck_tickets_estado check (estado in ('abierto', 'en_proceso', 'resuelto')),
  asunto text not null constraint ck_tickets_asunto check (length(btrim(asunto)) >= 5),
  descripcion text not null default '',
  origen text not null default 'panel' constraint ck_tickets_origen check (origen in ('panel', 'reporte', 'soporte', 'demo')),
  creado_por uuid,
  creado_por_rol text,
  contacto_id uuid,
  asignado_a uuid,
  resuelto_por uuid,
  solucion text,
  resuelto_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_tickets_tenant_id unique (tenant_id, id),
  constraint uq_tickets_numero unique (tenant_id, numero),
  constraint ck_tickets_solucion check (estado <> 'resuelto' or length(btrim(coalesce(solucion, ''))) >= 3),
  constraint fk_tickets_contacto foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id)
);
create index ix_tickets_estado on elius.tickets (tenant_id, estado, creado_en desc);

create table elius.ticket_notas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  ticket_id uuid not null,
  autor_id uuid,
  autor_rol text not null,
  tipo text not null default 'nota' constraint ck_ticket_notas_tipo check (tipo in ('nota', 'estado', 'solucion', 'dato_corregido', 'usuario')),
  texto text not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_ticket_notas_tenant_id unique (tenant_id, id),
  constraint fk_ticket_notas_ticket foreign key (tenant_id, ticket_id) references elius.tickets (tenant_id, id) on delete cascade
);
create index ix_ticket_notas_ticket on elius.ticket_notas (tenant_id, ticket_id, creado_en);

create table elius.manual_soporte (          -- contenido global (igual para todos los negocios); lo edita solo el CIS adm
  id uuid primary key default gen_random_uuid(),
  categoria text not null constraint ck_manual_categoria check (categoria in ('01', '02', '03', '04', '05', '06', '07')),
  titulo text not null,
  pasos text not null,
  orden int not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

-- Sin políticas = nadie accede directo a las tablas (solo las vistas y funciones de este archivo)
alter table elius.tickets enable row level security;
alter table elius.ticket_notas enable row level security;
alter table elius.manual_soporte enable row level security;
revoke all on elius.tickets, elius.ticket_notas, elius.manual_soporte from anon, authenticated;

create trigger t01_actualizado_en before update on elius.tickets for each row execute function app.set_actualizado_en();
create trigger t01_actualizado_en before update on elius.ticket_notas for each row execute function app.set_actualizado_en();
create trigger t01_actualizado_en before update on elius.manual_soporte for each row execute function app.set_actualizado_en();
create trigger t02_auditoria after insert or update or delete on elius.tickets for each row execute function app.auditar();
create trigger t02_auditoria after insert or update or delete on elius.ticket_notas for each row execute function app.auditar();
create trigger t00_sin_baja_directa before delete or update on elius.tickets for each row execute function app.bloquear_baja_directa();
create trigger t00_sin_truncate_directo before truncate on elius.tickets for each statement execute function app.bloquear_baja_directa();
create trigger t00_sin_baja_directa before delete or update on elius.ticket_notas for each row execute function app.bloquear_baja_directa();
create trigger t00_sin_truncate_directo before truncate on elius.ticket_notas for each statement execute function app.bloquear_baja_directa();

-- 2. Triggers propios --------------------------------------------------------------------------------------------------
create or replace function app.codigo_ticket()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.numero is null then
    perform pg_advisory_xact_lock(hashtext('tickets:' || new.tenant_id::text));
    select coalesce(max(numero), 0) + 1 into new.numero from elius.tickets where tenant_id = new.tenant_id;
  end if;
  new.codigo := 'TCK-' || lpad(new.numero::text, 4, '0');
  return new;
end $$;
create trigger t60_codigo_ticket before insert on elius.tickets for each row execute function app.codigo_ticket();

create or replace function app.estado_ticket()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.estado = 'resuelto' and new.estado <> 'resuelto' then
    raise exception 'RN-S01: un ticket resuelto no se reabre; crea uno nuevo y menciona el código %', old.codigo using errcode = '23514';
  end if;
  if new.estado = 'resuelto' and old.estado <> 'resuelto' then
    if length(btrim(coalesce(new.solucion, ''))) < 3 then
      raise exception 'RN-S01: para resolver un ticket hay que escribir la solución' using errcode = '23514';
    end if;
    new.resuelto_en := now();
  end if;
  return new;
end $$;
create trigger t61_estado_ticket before update on elius.tickets for each row execute function app.estado_ticket();

comment on trigger t60_codigo_ticket on elius.tickets is 'Numera los tickets por negocio (TCK-0001, TCK-0002…) con bloqueo para que dos tickets simultáneos no repitan número';
comment on trigger t61_estado_ticket on elius.tickets is 'RN-S01: un ticket resuelto exige solución y no se reabre; guarda la fecha de resolución';
comment on trigger t01_actualizado_en on elius.tickets is 'Genérico (BEFORE UPDATE): pone actualizado_en = now() para saber cuándo cambió la fila por última vez.';
comment on trigger t02_auditoria on elius.tickets is 'Genérico (AFTER): escribe en la bitácora quién, con qué rol, qué tabla y fila, y los datos antes y después (RN-P15).';
comment on trigger t00_sin_baja_directa on elius.tickets is 'Baja lógica: eliminar = desactivar (eliminado_en). Solo el Administrador desactiva o restaura; el DELETE real solo lo hace el CIS adm.';

-- 3. Auxiliares ---------------------------------------------------------------------------------------------------------
create or replace function elius.nombre_categoria_ticket(p text) returns text language sql immutable as $$
  select case p when '01' then 'General' when '02' then 'Reservas y agenda' when '03' then 'Pedidos y cocina' when '04' then 'Pagos y comprobantes'
                when '05' then 'Contabilidad' when '06' then 'Usuarios y accesos' when '07' then 'Integraciones' else p end
$$;
create or replace function elius.enmascarar_telefono(p text) returns text language sql immutable as $$
  select case when p is null then null when length(p) >= 8 then left(p, 3) || '•••' || right(p, 4) else '•••' end
$$;
create or replace function elius.enmascarar_correo(p text) returns text language sql immutable as $$
  select case when p is null then null when position('@' in p) > 1 then left(p, 1) || '•••@' || split_part(p, '@', 2) else '•••' end
$$;
create or replace function app.clave_temporal() returns text language sql volatile set search_path = '' as $$
  select string_agg(substr('abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + (get_byte(b, i) % 56), 1), '')
  from (select extensions.gen_random_bytes(12) as b) x, generate_series(0, 11) i
$$;
create or replace function app.soporte_o_admin() returns text language plpgsql stable security definer set search_path = '' as $$
declare v text := app.mi_rol();
begin
  if v is null or v not in ('soporte', 'administrador') then raise exception 'Solo Soporte o el Administrador' using errcode = '42501'; end if;
  return v;
end $$;
create or replace function elius.nota_ticket_interna(p_ticket uuid, p_tipo text, p_texto text) returns void
language sql security definer set search_path = '' as $$
  insert into elius.ticket_notas (tenant_id, ticket_id, autor_id, autor_rol, tipo, texto)
  values (app.current_tenant_id(), p_ticket, auth.uid(), coalesce(app.mi_rol(), 'sistema'), p_tipo, left(p_texto, 1000));
$$;
revoke execute on function elius.nota_ticket_interna(uuid, text, text), app.soporte_o_admin(), app.clave_temporal() from public, anon, authenticated;

-- 4. Vistas (lo único que lee Soporte; no hay acceso a las tablas) --------------------------------------------------------
create or replace view elius.v_soporte_tickets as
  select t.id, t.codigo, t.numero, t.categoria, elius.nombre_categoria_ticket(t.categoria) as categoria_nombre, t.prioridad, t.estado,
         t.asunto, t.descripcion, t.origen, t.creado_por_rol, coalesce(uc.email, '—') as creado_por, t.contacto_id,
         case when c.id is not null then btrim(c.nombres || ' ' || coalesce(c.apellidos, '')) end as cliente,
         ua.email as asignado_a, t.solucion, ur.email as resuelto_por, t.resuelto_en, t.creado_en,
         (extract(epoch from (coalesce(t.resuelto_en, now()) - t.creado_en)) / 60)::int as minutos
  from elius.tickets t
  left join auth.users uc on uc.id = t.creado_por
  left join auth.users ua on ua.id = t.asignado_a
  left join auth.users ur on ur.id = t.resuelto_por
  left join elius.contactos c on c.tenant_id = t.tenant_id and c.id = t.contacto_id
  where t.tenant_id = app.current_tenant_id() and app.mi_rol() in ('soporte', 'administrador');

create or replace view elius.v_soporte_tickets_pendientes as select * from elius.v_soporte_tickets where estado <> 'resuelto';
create or replace view elius.v_soporte_historial_tickets as select * from elius.v_soporte_tickets where estado = 'resuelto';

create or replace view elius.v_soporte_ticket_notas as
  select n.id, n.ticket_id, n.creado_en, coalesce(u.email, '—') as autor, n.autor_rol, n.tipo, n.texto
  from elius.ticket_notas n left join auth.users u on u.id = n.autor_id
  where n.tenant_id = app.current_tenant_id() and app.mi_rol() in ('soporte', 'administrador');

create or replace view elius.v_soporte_clientes as
  select c.id, btrim(c.nombres || ' ' || coalesce(c.apellidos, '')) as nombre,
         elius.enmascarar_correo(c.email) as email, elius.enmascarar_telefono(c.telefono) as telefono,
         case when c.numero_documento is not null then coalesce(c.tipo_documento, '') || ' •••' || right(c.numero_documento, 3) end as documento,
         c.origen, c.creado_en,
         (select count(*) from elius.tickets x where x.tenant_id = c.tenant_id and x.contacto_id = c.id and x.estado <> 'resuelto')::int as tickets_abiertos
  from elius.contactos c
  where c.tenant_id = app.current_tenant_id() and c.eliminado_en is null and app.mi_rol() in ('soporte', 'administrador');

create or replace view elius.v_soporte_usuarios as
  select m.usuario_id, u.email, r.codigo as rol, r.nombre as rol_nombre, m.cargo, m.estado, u.last_sign_in_at as ultimo_acceso, m.fecha_ingreso,
         exists (select 1 from platform.accesos_bd b where b.usuario_id = m.usuario_id) as cuenta_directa
  from platform.membresias m
  join platform.roles r on r.id = m.rol_id
  join auth.users u on u.id = m.usuario_id
  where m.tenant_id = app.current_tenant_id() and app.mi_rol() in ('soporte', 'administrador');

create or replace view elius.v_soporte_manual as
  select s.id, s.categoria, elius.nombre_categoria_ticket(s.categoria) as categoria_nombre, s.titulo, s.pasos, s.orden
  from elius.manual_soporte s
  where app.mi_rol() in ('soporte', 'administrador');

grant select on elius.v_soporte_tickets, elius.v_soporte_tickets_pendientes, elius.v_soporte_historial_tickets, elius.v_soporte_ticket_notas,
  elius.v_soporte_clientes, elius.v_soporte_usuarios, elius.v_soporte_manual to authenticated;

-- 5. Procedimientos -----------------------------------------------------------------------------------------------------
create or replace function elius.crear_ticket(p_categoria text, p_prioridad text, p_asunto text, p_descripcion text default '', p_contacto uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_rol text := app.mi_rol(); v_id uuid;
begin
  if v_rol is null or v_rol not in ('administrador', 'operador', 'soporte') then
    raise exception 'No tienes permiso para crear tickets' using errcode = '42501';
  end if;
  insert into elius.tickets (tenant_id, categoria, prioridad, asunto, descripcion, origen, creado_por, creado_por_rol, contacto_id)
  values (app.current_tenant_id(), p_categoria, coalesce(nullif(p_prioridad, ''), 'media'), btrim(p_asunto), btrim(coalesce(p_descripcion, '')),
          case when v_rol = 'soporte' then 'soporte' else 'panel' end, auth.uid(), v_rol, p_contacto)
  returning id into v_id;
  return v_id;
end $$;

-- El problema que reporta el Trabajador ahora es un ticket (categoría 01)
create or replace function elius.reportar_problema(p_mensaje text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_rol text := app.mi_rol(); v_id uuid; v_txt text := btrim(coalesce(p_mensaje, ''));
begin
  if v_rol is null or v_rol not in ('administrador', 'operador', 'soporte') then
    raise exception 'No tienes permiso para reportar problemas' using errcode = '42501';
  end if;
  if length(v_txt) < 5 then raise exception 'Describe el problema (mínimo 5 caracteres)'; end if;
  insert into elius.tickets (tenant_id, categoria, prioridad, asunto, descripcion, origen, creado_por, creado_por_rol)
  values (app.current_tenant_id(), '01', 'media', left(v_txt, 120), left(v_txt, 500), 'reporte', auth.uid(), v_rol)
  returning id into v_id;
  return v_id;
end $$;

create or replace function elius.soporte_tomar_ticket(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform app.soporte_o_admin();
  update elius.tickets set estado = 'en_proceso', asignado_a = auth.uid()
   where id = p_id and tenant_id = app.current_tenant_id() and estado = 'abierto';
  if not found then raise exception 'El ticket no existe o ya está en proceso o resuelto'; end if;
  perform elius.nota_ticket_interna(p_id, 'estado', 'Tomó el ticket y lo puso en proceso');
end $$;

create or replace function elius.soporte_nota_ticket(p_id uuid, p_texto text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform app.soporte_o_admin();
  if length(btrim(coalesce(p_texto, ''))) < 3 then raise exception 'Escribe la nota'; end if;
  if not exists (select 1 from elius.tickets where id = p_id and tenant_id = app.current_tenant_id()) then raise exception 'El ticket no existe'; end if;
  perform elius.nota_ticket_interna(p_id, 'nota', btrim(p_texto));
end $$;

create or replace function elius.soporte_resolver_ticket(p_id uuid, p_solucion text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform app.soporte_o_admin();
  if length(btrim(coalesce(p_solucion, ''))) < 3 then raise exception 'Escribe la solución: qué se hizo para resolverlo'; end if;
  update elius.tickets set estado = 'resuelto', solucion = btrim(p_solucion), resuelto_por = auth.uid(),
         asignado_a = coalesce(asignado_a, auth.uid())
   where id = p_id and tenant_id = app.current_tenant_id() and estado <> 'resuelto';
  if not found then raise exception 'El ticket no existe o ya está resuelto'; end if;
  perform elius.nota_ticket_interna(p_id, 'solucion', btrim(p_solucion));
end $$;

-- «Modificar datos manual»: corrige un dato de un cliente con motivo y ligado a un ticket abierto (sin tocar la tabla)
create or replace function elius.soporte_corregir_cliente(p_contacto uuid, p_ticket uuid, p_nombres text default null, p_apellidos text default null,
                                                          p_telefono text default null, p_email text default null, p_motivo text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare c elius.contactos%rowtype; v_cambios text[] := '{}'; t uuid := app.current_tenant_id();
begin
  perform app.soporte_o_admin();
  if length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Escribe el motivo de la corrección (mínimo 5 caracteres)'; end if;
  if not exists (select 1 from elius.tickets where id = p_ticket and tenant_id = t and estado <> 'resuelto') then
    raise exception 'Toda corrección va ligada a un ticket abierto del negocio';
  end if;
  select * into c from elius.contactos where id = p_contacto and tenant_id = t and eliminado_en is null;
  if not found then raise exception 'El cliente no existe'; end if;
  if p_telefono is not null and p_telefono !~ '^\+[0-9]{8,15}$' then raise exception 'Teléfono con indicativo y solo números, por ejemplo +573001234567'; end if;
  if p_email is not null and p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then raise exception 'Correo con dominio, por ejemplo nombre@empresa.com'; end if;
  if coalesce(nullif(btrim(p_nombres), ''), nullif(btrim(p_apellidos), ''), p_telefono, p_email) is null then raise exception 'No indicaste ningún dato para corregir'; end if;
  if nullif(btrim(p_nombres), '') is not null then v_cambios := v_cambios || ('nombres: ' || c.nombres || ' → ' || btrim(p_nombres)); end if;
  if nullif(btrim(p_apellidos), '') is not null then v_cambios := v_cambios || ('apellidos: ' || coalesce(c.apellidos, '—') || ' → ' || btrim(p_apellidos)); end if;
  if p_telefono is not null then v_cambios := v_cambios || ('teléfono: ' || coalesce(elius.enmascarar_telefono(c.telefono), '—') || ' → ' || elius.enmascarar_telefono(p_telefono)); end if;
  if p_email is not null then v_cambios := v_cambios || ('correo: ' || coalesce(elius.enmascarar_correo(c.email), '—') || ' → ' || elius.enmascarar_correo(p_email)); end if;
  update elius.contactos set nombres = coalesce(nullif(btrim(p_nombres), ''), nombres), apellidos = coalesce(nullif(btrim(p_apellidos), ''), apellidos),
         telefono = coalesce(p_telefono, telefono), email = coalesce(p_email, email)
   where id = p_contacto and tenant_id = t;
  perform elius.nota_ticket_interna(p_ticket, 'dato_corregido', 'Corrigió datos del cliente (' || array_to_string(v_cambios, '; ') || '). Motivo: ' || btrim(p_motivo));
  return array_to_string(v_cambios, '; ');
exception when unique_violation then
  raise exception 'Ese teléfono o correo ya pertenece a otro cliente del negocio' using errcode = '23505';
end $$;

-- Crea un usuario del negocio con su rol y una clave temporal (se muestra una sola vez)
create or replace function elius.soporte_crear_usuario(p_ticket uuid, p_email text, p_rol text, p_cargo text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(btrim(coalesce(p_email, ''))); v_id uuid; v_clave text; v_rol uuid; t uuid := app.current_tenant_id(); v_nuevo boolean := false;
begin
  perform app.soporte_o_admin();
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then raise exception 'Correo con dominio, por ejemplo nombre@empresa.com'; end if;
  if p_rol not in ('administrador', 'operador', 'analista') then raise exception 'Rol no válido: usa administrador, operador o analista'; end if;
  select id into v_rol from platform.roles where codigo = p_rol and nivel = 'tenant';
  if v_rol is null then raise exception 'El rol % no existe', p_rol; end if;
  select id into v_id from auth.users where lower(email) = v_email;
  if v_id is not null and exists (select 1 from platform.membresias where tenant_id = t and usuario_id = v_id) then
    raise exception 'Ese correo ya es usuario de este negocio';
  end if;
  if v_id is null then
    v_nuevo := true; v_id := gen_random_uuid(); v_clave := app.clave_temporal();
    if exists (select 1 from information_schema.columns where table_schema = 'auth' and table_name = 'users' and column_name = 'encrypted_password') then
      execute format($f$insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current,
                          phone_change, phone_change_token, reauthentication_token)
                        values (%L, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', %L, extensions.crypt(%L, extensions.gen_salt('bf')), now(),
                          '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '')$f$, v_id, v_email, v_clave);
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
              'email', now(), now(), now());
    else
      insert into auth.users (id, email) values (v_id, v_email);
    end if;
  end if;
  insert into platform.membresias (tenant_id, usuario_id, rol_id, estado, cargo, invitado_por)
  values (t, v_id, v_rol, 'activo', coalesce(nullif(btrim(p_cargo), ''), initcap(p_rol)), auth.uid());
  if p_ticket is not null and exists (select 1 from elius.tickets where id = p_ticket and tenant_id = t) then
    perform elius.nota_ticket_interna(p_ticket, 'usuario', 'Creó el usuario ' || v_email || ' con rol ' || p_rol);
  end if;
  return jsonb_build_object('usuario_id', v_id, 'email', v_email, 'rol', p_rol, 'clave_temporal', v_clave, 'nuevo', v_nuevo);
end $$;

create or replace function elius.soporte_restablecer_clave(p_usuario uuid, p_ticket uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_email text; v_clave text := app.clave_temporal(); t uuid := app.current_tenant_id();
begin
  perform app.soporte_o_admin();
  select u.email into v_email from platform.membresias m join auth.users u on u.id = m.usuario_id where m.tenant_id = t and m.usuario_id = p_usuario;
  if v_email is null then raise exception 'El usuario no pertenece a este negocio'; end if;
  if p_usuario = auth.uid() then raise exception 'Tu propia clave no se restablece aquí'; end if;
  if exists (select 1 from platform.accesos_bd where usuario_id = p_usuario) then raise exception 'Las cuentas de conexión directa a la base de datos no se restablecen desde el panel'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'auth' and table_name = 'users' and column_name = 'encrypted_password') then
    execute format($f$update auth.users set encrypted_password = extensions.crypt(%L, extensions.gen_salt('bf')), updated_at = now() where id = %L$f$, v_clave, p_usuario);
  end if;
  insert into audit.registros_auditoria (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_nuevos)
  values (t, auth.uid(), app.mi_rol(), case when app.mi_rol() = 'soporte' then 'soporte' else 'app' end, 'auth', 'users', p_usuario, 'UPDATE',
          jsonb_build_object('accion', 'restablecer_clave', 'usuario', v_email));
  if p_ticket is not null and exists (select 1 from elius.tickets where id = p_ticket and tenant_id = t) then
    perform elius.nota_ticket_interna(p_ticket, 'usuario', 'Restableció la clave de ' || v_email || ' (clave temporal entregada una sola vez)');
  end if;
  return jsonb_build_object('email', v_email, 'clave_temporal', v_clave);
end $$;

create or replace function elius.soporte_cambiar_rol_usuario(p_usuario uuid, p_rol text, p_ticket uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_rol uuid; t uuid := app.current_tenant_id(); v_email text;
begin
  perform app.soporte_o_admin();
  if p_rol not in ('administrador', 'operador', 'analista') then raise exception 'Rol no válido: usa administrador, operador o analista'; end if;
  if p_usuario = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if exists (select 1 from platform.accesos_bd where usuario_id = p_usuario) then raise exception 'Las cuentas de conexión directa no se modifican desde el panel'; end if;
  select id into v_rol from platform.roles where codigo = p_rol and nivel = 'tenant';
  update platform.membresias set rol_id = v_rol where tenant_id = t and usuario_id = p_usuario;
  if not found then raise exception 'El usuario no pertenece a este negocio'; end if;
  select email into v_email from auth.users where id = p_usuario;
  if p_ticket is not null and exists (select 1 from elius.tickets where id = p_ticket and tenant_id = t) then
    perform elius.nota_ticket_interna(p_ticket, 'usuario', 'Cambió el rol de ' || v_email || ' a ' || p_rol);
  end if;
end $$;

create or replace function elius.soporte_estado_usuario(p_usuario uuid, p_activo boolean, p_ticket uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare t uuid := app.current_tenant_id(); v_email text;
begin
  perform app.soporte_o_admin();
  if p_usuario = auth.uid() then raise exception 'No puedes desactivar tu propio usuario'; end if;
  if exists (select 1 from platform.accesos_bd where usuario_id = p_usuario) then raise exception 'Las cuentas de conexión directa no se modifican desde el panel'; end if;
  update platform.membresias set estado = case when p_activo then 'activo' else 'inactivo' end where tenant_id = t and usuario_id = p_usuario;
  if not found then raise exception 'El usuario no pertenece a este negocio'; end if;
  select email into v_email from auth.users where id = p_usuario;
  if p_ticket is not null and exists (select 1 from elius.tickets where id = p_ticket and tenant_id = t) then
    perform elius.nota_ticket_interna(p_ticket, 'usuario', (case when p_activo then 'Reactivó' else 'Desactivó' end) || ' al usuario ' || v_email);
  end if;
end $$;

-- Para la prueba en vivo: inventa un ticket real con su problema (solo en negocios de demostración)
create or replace function elius.generar_ticket_prueba(p_tipo text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t uuid := app.current_tenant_id(); v_rol text := app.mi_rol(); v_tipo text := coalesce(p_tipo, (array['cliente', 'usuario'])[1 + floor(random() * 2)::int]);
  v_n int := 100 + floor(random() * 900)::int; v_id uuid; v_cod text; v_contacto uuid; v_tel text := '+57310' || lpad((floor(random() * 10000000))::int::text, 7, '0');
begin
  perform app.soporte_o_admin();
  if not exists (select 1 from platform.tenants where id = t and slug like 'demo-%') then raise exception 'Solo disponible en los negocios de demostración'; end if;
  if not exists (select 1 from elius.tickets where tenant_id = t and origen = 'demo' and estado = 'resuelto') then      -- historial inicial para consultar
    insert into elius.tickets (tenant_id, categoria, prioridad, asunto, descripcion, origen, creado_por_rol, estado, solucion, resuelto_en, creado_en)
    values (t, '05', 'media', 'Cliente no recibe la confirmación de su reserva', 'El cliente dice que nunca le llega el mensaje de confirmación.', 'demo', 'operador', 'resuelto',
            'El teléfono estaba incompleto (faltaban dígitos). Se corrigió desde Clientes con el formulario de corrección y se reenvió la confirmación.', now() - interval '3 days', now() - interval '3 days 2 hours'),
           (t, '06', 'alta', 'Trabajador nuevo no puede entrar al panel', 'Se contrató una persona para caja y no tiene usuario.', 'demo', 'administrador', 'resuelto',
            'Se creó el usuario con rol Operador desde la pestaña Usuarios y se entregó la clave temporal; debe cambiarla al entrar.', now() - interval '2 days', now() - interval '2 days 1 hour'),
           (t, '07', 'baja', 'Aviso al celular no llega', 'El equipo no recibe el aviso de comprobantes.', 'demo', 'operador', 'resuelto',
            'El evento estaba fallido. Se reintentó desde la pestaña Técnico y el aviso salió.', now() - interval '1 day', now() - interval '1 day 3 hours');
  end if;
  if v_tipo = 'cliente' then
    insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen)
    values (t, 'Cliente', 'Prueba ' || v_n, left(v_tel, 8), 'panel') returning id into v_contacto;
    insert into elius.tickets (tenant_id, categoria, prioridad, asunto, descripcion, origen, creado_por, creado_por_rol, contacto_id)
    values (t, '05', 'alta', 'Cliente Prueba ' || v_n || ' no recibe la confirmación',
            'El cliente Prueba ' || v_n || ' dice que no le llega ningún mensaje. Su teléfono quedó incompleto al registrarlo. El número correcto es ' || v_tel || '. Corregirlo desde Clientes y resolver.',
            'demo', auth.uid(), v_rol, v_contacto) returning id, codigo into v_id, v_cod;
  else
    insert into elius.tickets (tenant_id, categoria, prioridad, asunto, descripcion, origen, creado_por, creado_por_rol)
    values (t, '06', 'media', 'Crear usuario para el nuevo ayudante ' || v_n,
            'Entra una persona nueva al equipo. Crear el usuario ayudante' || v_n || '@elius.local con rol Operador (cargo Ayudante), entregar la clave temporal y resolver.',
            'demo', auth.uid(), v_rol) returning id, codigo into v_id, v_cod;
  end if;
  return jsonb_build_object('id', v_id, 'codigo', v_cod, 'tipo', v_tipo);
end $$;

-- 6. Manual de soporte (contenido inicial) -------------------------------------------------------------------------------
insert into elius.manual_soporte (categoria, titulo, pasos, orden) values
 ('01', 'Cómo atender un ticket', E'1. Abre Tickets pendientes y toma el ticket (pasa a «En proceso»).\n2. Busca en el Historial si otra persona ya lo resolvió (por código, categoría o palabra).\n3. Sigue el artículo del manual que corresponda a la categoría.\n4. Deja una nota con cada paso y, al terminar, resuelve escribiendo qué se hizo.\n5. Un ticket resuelto no se reabre: si el problema vuelve, crea uno nuevo y menciona el código anterior.', 1),
 ('01', 'Prioridades', E'Crítica: el negocio no puede vender ni atender.\nAlta: una función importante falla para una persona o varias.\nMedia: molestia con alternativa.\nBaja: consulta o mejora.', 2),
 ('02', 'Una reserva no aparece en la agenda', E'1. Confirma con quien reservó la fecha y la hora.\n2. En Clientes verifica que la persona exista y que su teléfono esté completo.\n3. Si la reserva está en estado «pendiente de pago», no aparece como confirmada hasta que se apruebe el comprobante.\n4. Si nada de lo anterior aplica, anota el caso y escálalo al Administrador.', 1),
 ('03', 'El total de una orden no coincide', E'El total se calcula solo a partir de las líneas (no se escribe a mano). Revisa que las líneas tengan el precio del catálogo vigente y que el ítem no haya cambiado de precio después de agregarlo. Si hay una diferencia real, el Administrador la corrige con un pago de reverso, nunca editando el total.', 1),
 ('04', 'Comprobante repetido o con monto distinto', E'El sistema marca la alerta automáticamente. Solo el Administrador aprueba o rechaza el comprobante. Soporte documenta el caso en el ticket y avisa al Administrador.', 1),
 ('05', 'El cliente no recibe confirmaciones (teléfono o correo mal escrito)', E'1. Toma el ticket y abre la pestaña Clientes.\n2. Busca al cliente por su nombre. Los datos aparecen enmascarados por privacidad.\n3. Usa «Corregir datos» e indica el teléfono con indicativo (por ejemplo +573001234567) o el correo correcto.\n4. Escribe el motivo y guarda: la corrección queda en el ticket y en la auditoría.\n5. Resuelve el ticket con una nota de lo que se hizo.', 1),
 ('06', 'Crear un usuario nuevo y asignar su rol', E'1. Abre la pestaña Usuarios y pulsa «Crear usuario».\n2. Escribe el correo, elige el rol (Operador para el equipo del día a día, Analista para solo consulta, Administrador solo si el dueño lo autoriza) y el cargo.\n3. Se muestra una clave temporal UNA sola vez: entrégala por un canal seguro.\n4. Registra la acción en el ticket y resuélvelo.\nEl plan limita cuántos usuarios puede tener el negocio.', 1),
 ('06', 'Restablecer la clave de un usuario', E'1. En Usuarios pulsa «Restablecer clave» en la fila de la persona.\n2. Entrega la clave temporal que aparece (no se vuelve a mostrar).\n3. Pide a la persona que la cambie al entrar.\nLas cuentas de conexión directa a la base de datos no se restablecen desde el panel.', 2),
 ('07', 'Un evento de salida quedó fallido', E'En la pestaña Técnico abre Eventos fallidos y pulsa Reintentar. Si falla otra vez, anota el tipo de evento en el ticket y escálalo: no se ve el contenido del evento, solo su estado.', 1);

-- 7. Los reportes que ya existían (errores_agente 'reporte:*') pasan a ser tickets y dejan de contarse como errores técnicos
do $$
begin
  insert into elius.tickets (tenant_id, categoria, prioridad, asunto, descripcion, origen, creado_por_rol, estado, solucion, resuelto_en, creado_en)
  select e.tenant_id, '01', 'media', left(e.mensaje, 120), left(e.mensaje, 500), 'reporte', coalesce(e.detalle ->> 'reportado_por_rol', split_part(e.origen, ':', 2)),
         case when e.resuelto_en is not null then 'resuelto' else 'abierto' end,
         case when e.resuelto_en is not null then coalesce(nullif(btrim(e.notas), ''), 'Resuelto') end, e.resuelto_en, e.creado_en
  from elius.errores_agente e where e.origen like 'reporte:%'
  order by e.creado_en;
  update elius.errores_agente set resuelto_en = coalesce(resuelto_en, now()), notas = coalesce(notas || E'\n', '') || 'Migrado a tickets'
   where origen like 'reporte:%' and resuelto_en is null;
end $$;

create or replace view elius.v_soporte_errores as
  select e.id, e.creado_en, e.origen, e.mensaje, e.resuelto_en, e.notas, (e.resuelto_en is null) as abierto
  from elius.errores_agente e
  where e.tenant_id = app.current_tenant_id() and app.mi_rol() in ('soporte', 'administrador') and e.origen not like 'reporte:%';

drop view if exists elius.v_mis_reportes;
create view elius.v_mis_reportes as
  select t.id, t.creado_en, (t.codigo || ' · ' || t.asunto) as mensaje, t.resuelto_en, t.solucion as notas, (t.estado <> 'resuelto') as abierto
  from elius.tickets t
  where t.tenant_id = app.current_tenant_id() and t.origen = 'reporte'
    and app.mi_rol() in ('operador', 'administrador')
    and (app.mi_rol() = 'administrador' or t.creado_por = auth.uid());
grant select on elius.v_mis_reportes to authenticated;
comment on view elius.v_mis_reportes is 'Problemas que la persona reportó (el Administrador ve los de todo el negocio): son tickets, con el estado y la solución que les da Soporte';

create or replace function elius.soporte_estado_integraciones()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare t uuid := app.current_tenant_id();
begin
  perform app.soporte_o_admin();
  return jsonb_build_object(
    'tickets_abiertos', (select count(*) from elius.tickets where tenant_id = t and estado <> 'resuelto'),
    'errores_abiertos', (select count(*) from elius.errores_agente where tenant_id = t and resuelto_en is null and origen not like 'reporte:%'),
    'eventos_fallidos', (select count(*) from elius.eventos_salida where tenant_id = t and estado = 'fallido'),
    'eventos_pendientes', (select count(*) from elius.eventos_salida where tenant_id = t and estado = 'pendiente'),
    'ultimo_evento_enviado', (select max(procesado_en) from elius.eventos_salida where tenant_id = t and estado = 'enviado'),
    'avisos_push_configurados', exists (select 1 from platform.ajustes_globales where clave = 'push_service_url' and coalesce(valor, '') <> ''),
    'dispositivos_con_avisos', (select count(*) from platform.push_suscripciones s join platform.membresias m on m.usuario_id = s.usuario_id and m.tenant_id = t where s.activo),
    'eli_encendida', coalesce((select a.activo from elius.agentes a where a.tenant_id = t order by a.version desc limit 1), false));
end $$;

-- 8. Permisos de ejecución y descripciones -------------------------------------------------------------------------------
revoke execute on function elius.crear_ticket(text, text, text, text, uuid), elius.reportar_problema(text), elius.soporte_tomar_ticket(uuid),
  elius.soporte_nota_ticket(uuid, text), elius.soporte_resolver_ticket(uuid, text),
  elius.soporte_corregir_cliente(uuid, uuid, text, text, text, text, text), elius.soporte_crear_usuario(uuid, text, text, text),
  elius.soporte_restablecer_clave(uuid, uuid), elius.soporte_cambiar_rol_usuario(uuid, text, uuid), elius.soporte_estado_usuario(uuid, boolean, uuid),
  elius.generar_ticket_prueba(text), elius.soporte_estado_integraciones() from public, anon;
grant execute on function elius.crear_ticket(text, text, text, text, uuid), elius.reportar_problema(text), elius.soporte_tomar_ticket(uuid),
  elius.soporte_nota_ticket(uuid, text), elius.soporte_resolver_ticket(uuid, text),
  elius.soporte_corregir_cliente(uuid, uuid, text, text, text, text, text), elius.soporte_crear_usuario(uuid, text, text, text),
  elius.soporte_restablecer_clave(uuid, uuid), elius.soporte_cambiar_rol_usuario(uuid, text, uuid), elius.soporte_estado_usuario(uuid, boolean, uuid),
  elius.generar_ticket_prueba(text), elius.soporte_estado_integraciones() to authenticated;

comment on table elius.tickets is 'Tickets de soporte por negocio (TCK-0001). Sin políticas: solo se leen por las vistas v_soporte_* y se cambian con los procedimientos soporte_*';
comment on table elius.ticket_notas is 'Cronología de cada ticket: notas, cambios de estado, datos corregidos y usuarios creados';
comment on table elius.manual_soporte is 'Manual de soporte (contenido global por categoría de ticket)';
comment on view elius.v_soporte_tickets_pendientes is 'Tickets abiertos o en proceso del negocio (Soporte y Administrador)';
comment on view elius.v_soporte_historial_tickets is 'Tickets ya resueltos con su solución: consultar si otra persona ya lo solucionó';
comment on view elius.v_soporte_clientes is 'Clientes del negocio con teléfono, correo y documento enmascarados';
comment on view elius.v_soporte_usuarios is 'Usuarios del negocio con su rol y estado; nunca muestra claves';
comment on view elius.v_soporte_manual is 'Manual de soporte por categoría';
comment on function elius.crear_ticket(text, text, text, text, uuid) is 'Abre un ticket (registro manual) con categoría y prioridad';
comment on function elius.soporte_tomar_ticket(uuid) is 'Soporte toma el ticket: pasa a En proceso y queda asignado';
comment on function elius.soporte_resolver_ticket(uuid, text) is 'Soporte resuelve el ticket con la solución escrita';
comment on function elius.soporte_corregir_cliente(uuid, uuid, text, text, text, text, text) is 'Corrige un dato de un cliente con motivo y ligado a un ticket abierto; queda en la nota del ticket y en la auditoría';
comment on function elius.soporte_crear_usuario(uuid, text, text, text) is 'Crea un usuario del negocio con su rol y una clave temporal que se muestra una sola vez';
comment on function elius.soporte_restablecer_clave(uuid, uuid) is 'Genera una clave temporal nueva para un usuario del negocio (se muestra una sola vez)';
comment on function elius.generar_ticket_prueba(text) is 'Inventa un ticket real con su problema para la prueba en vivo (solo negocios de demostración)';

-- 9. Descripción de los triggers (misma explicación que sus equivalentes genéricos) ---------------------------------------
do $$
declare r record; v_desc text;
begin
  for r in
    select c.relname, t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'elius' and c.relname in ('tickets', 'ticket_notas', 'manual_soporte') and not t.tgisinternal
      and obj_description(t.oid, 'pg_trigger') is null
  loop
    select obj_description(t2.oid, 'pg_trigger') into v_desc
      from pg_trigger t2 join pg_class c2 on c2.oid = t2.tgrelid join pg_namespace n2 on n2.oid = c2.relnamespace
     where n2.nspname = 'elius' and c2.relname = 'contactos' and t2.tgname = r.tgname and not t2.tgisinternal;
    if v_desc is not null then
      execute format('comment on trigger %I on elius.%I is %L', r.tgname, r.relname, v_desc);
    end if;
  end loop;
end $$;
