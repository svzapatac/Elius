-- 3900 · Las copias de seguridad también se guardan en un bucket PRIVADO de Supabase Storage, y solo el CIS adm las ve y descarga desde el panel.
--  · El servicio de respaldo (Easypanel) las sube con la llave de servicio; nadie más tiene acceso: no hay políticas para otros roles.
--  · Cada copia sube dos archivos: la copia cifrada (.tar.age) y su manifiesto.xml (solo nombres de tablas, conteos y huellas: sin datos).
do $$ begin
  if to_regclass('storage.objects') is null then
    raise notice 'Supabase Storage no está disponible en esta base: se omite el bucket de respaldos';
    return;
  end if;
  insert into storage.buckets (id, name, public) values ('respaldos', 'respaldos', false) on conflict (id) do nothing;
  drop policy if exists respaldos_cis_leer on storage.objects;
  create policy respaldos_cis_leer on storage.objects for select to authenticated
    using (bucket_id = 'respaldos' and (select app.es_super_admin()));
end $$;
