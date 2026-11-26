-- 0800 · Regla R1 del curso: no hay relaciones 1 a 1. accesos_bd.usuario_id era único (1-1 con el usuario);
-- ahora una persona puede tener varios usuarios de conexión directa (1 a muchos). Nada dependía de esa unicidad.
alter table platform.accesos_bd drop constraint if exists accesos_bd_usuario_id_key;
create index if not exists ix_accesos_bd_usuario on platform.accesos_bd (usuario_id);
