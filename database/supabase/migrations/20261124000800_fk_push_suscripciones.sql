-- 0800 · Llave foránea de las suscripciones push hacia auth.users (platform.usuarios en el modelo).
-- Al borrar un usuario se borran sus dispositivos. Antes la columna no tenía llave.
delete from platform.push_suscripciones s where not exists (select 1 from auth.users u where u.id = s.usuario_id);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'fk_push_suscripciones_usuario_id') then
    alter table platform.push_suscripciones add constraint fk_push_suscripciones_usuario_id
      foreign key (usuario_id) references auth.users (id) on delete cascade;
  end if;
end $$;
