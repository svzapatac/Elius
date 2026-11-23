-- =============================================================================
-- ELIUS · Migración 0800 · Usuarios de conexión a PostgreSQL y sus permisos
-- "Conexión con usuarios: Admin, Privilegios, Consulting (non Super Admin)"
-- Sección 10.3 del levantamiento y DT-13.
--
--   Usuario         Puede                                            No puede
--   elius_admin     crear objetos, leer/escribir todo, otorgar       ser superusuario, saltarse RLS,
--                   permisos (WITH GRANT OPTION)                     ver varios tenants a la vez
--   elius_app       leer, insertar, actualizar, borrar en tablas     cambiar la estructura, leer la
--                   de negocio y ejecutar procedimientos             auditoría completa, saltarse RLS
--   elius_consulta  leer las vistas agregadas del esquema reportes   escribir, leer tablas, ver datos
--                                                                    personales
--
-- Ninguno tiene SUPERUSER ni BYPASSRLS (ver migración 0100). Como no son dueños de las
-- tablas, RLS les aplica: para trabajar fijan el tenant con
--   select set_config('app.tenant_id', '<uuid>', false);
-- y solo ven ese tenant.
-- =============================================================================

-- ---------- elius_admin: administrador del esquema --------------------------------
grant usage, create on schema platform, elius, ext, audit, app, reportes, plugin_vet, plugin_restaurant, plugin_airline
  to elius_admin;
grant all privileges on all tables in schema platform, elius, ext, audit, plugin_vet, plugin_restaurant, plugin_airline, reportes
  to elius_admin with grant option;
grant all privileges on all sequences in schema platform, elius, ext, audit, plugin_vet, plugin_restaurant, plugin_airline
  to elius_admin with grant option;
grant execute on all functions in schema app, platform, elius, plugin_vet, plugin_restaurant, plugin_airline
  to elius_admin with grant option;
grant usage on schema auth to elius_admin;

-- ---------- elius_app: privilegios de la aplicación ---------------------------------
-- (los GRANT de tablas y funciones de negocio se dieron en 0400 y 0700)
revoke truncate, references, trigger on all tables in schema platform, elius, ext, plugin_vet, plugin_restaurant, plugin_airline
  from elius_app;
revoke all on audit.registros_auditoria from elius_app;
grant select on audit.registros_auditoria to elius_app;           -- RLS: solo su tenant y con permiso de auditoría
revoke insert, update, delete on platform.planes, platform.roles, platform.permisos, platform.plugins, platform.rol_permisos
  from elius_app;                                                  -- catálogos globales: solo lectura
grant usage on schema auth to elius_app;

-- ---------- elius_consulta: solo vistas agregadas (consultoría) ---------------------
revoke all on all tables in schema platform, elius, ext, audit, plugin_vet, plugin_restaurant, plugin_airline
  from elius_consulta;
grant usage on schema reportes to elius_consulta;
grant select on all tables in schema reportes to elius_consulta;
-- Las vistas de reportes corren con los permisos de su dueño y solo devuelven conteos
-- y montos por tenant y mes, sin nombres, teléfonos ni contenidos.

-- ---------- Nada para anon ni para PUBLIC ------------------------------------------
revoke all on all tables in schema platform, elius, ext, audit, reportes, plugin_vet, plugin_restaurant, plugin_airline
  from anon, public;
revoke create on schema public from public;

-- ---------- Objetos futuros heredan los mismos permisos ------------------------------
alter default privileges in schema platform, elius, ext, plugin_vet, plugin_restaurant, plugin_airline
  grant select, insert, update, delete on tables to authenticated, service_role, elius_app;
alter default privileges in schema reportes grant select on tables to elius_consulta;
