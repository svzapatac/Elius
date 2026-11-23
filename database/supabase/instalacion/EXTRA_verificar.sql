-- Verificación después de instalar. Todo debe dar los valores de la columna "esperado".
select 'tablas propias' as que, count(*) as obtenido, 80 as esperado
  from pg_tables where schemaname in ('platform','audit','elius','ext','plugin_vet','plugin_restaurant','plugin_airline')
union all
select 'tablas con RLS', count(*), 80
  from pg_tables where schemaname in ('platform','audit','elius','ext','plugin_vet','plugin_restaurant','plugin_airline') and rowsecurity
union all
select 'llaves foráneas', count(*), 191
  from pg_constraint c join pg_namespace n on n.oid = c.connamespace
  where c.contype = 'f' and n.nspname in ('platform','audit','elius','ext','plugin_vet','plugin_restaurant','plugin_airline')
union all
select 'roles generales', count(*), 6 from platform.roles
union all
select 'planes', count(*), (select count(*) from platform.planes) from platform.planes
union all
select 'plugins', count(*), 3 from platform.plugins
union all
select 'permisos', count(*), 21 from platform.permisos
union all
select 'vistas', count(*), 20
  from pg_views where schemaname in ('elius','reportes','plugin_vet','plugin_restaurant','plugin_airline');
