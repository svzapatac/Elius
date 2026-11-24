"""Genera la migración 1200 (casos de prueba) y las ilustraciones SVG del panel.
Uso: python3 database/modelo/generar_casos_demo.py <carpeta_public_del_panel>"""
import json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from casos_demo import CASOS, COLOR

def q(s): return s.replace("'", "''")

def datos_sql(v):
    c = CASOS[v]
    d = {'negocio': c['negocio'], 'categorias': c['categoria'], 'contactos': c['contactos'],
         'items': [dict(cat=i[0], tipo=i[1], sku=i[2], nombre=i[3], desc=i[4], precio=i[5], iva=i[6], dur=i[7]) for i in c['items']],
         'guion': [dict(conv=g[0], emisor=g[1], texto=g[2], img=g[3]) for g in c['guion']]}
    return json.dumps(d, ensure_ascii=False)

ramas = '\n'.join(f"    when '{v}' then '{q(datos_sql(v))}'::jsonb" for v in CASOS)
sql = f"""-- =============================================================================
-- 1200 · Casos de prueba por vertical (restaurante, veterinaria, aerolínea)
-- El profesor elige un caso en el panel: se crea el negocio con su catálogo (5 ítems con imagen)
-- y, desde el panel, llegan 20 mensajes de prueba con las respuestas de Eli.
-- =============================================================================

create or replace function elius.datos_caso_demo(p_vertical text)
returns jsonb language sql immutable set search_path = '' as $$
  select case p_vertical
{ramas}
  end;
$$;

-- Crea los clientes del caso (uno por conversación) en un negocio de prueba
create or replace function elius.sembrar_clientes_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_canal uuid; v_contacto uuid; v_ident uuid; r jsonb;
begin
  select id into v_canal from elius.canales where tenant_id = p_tenant order by creado_en limit 1;
  delete from elius.contactos where tenant_id = p_tenant;   -- cascada: identidades, conversaciones y mensajes
  for r in select * from jsonb_array_elements(v_d->'contactos') loop
    insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen)
    values (p_tenant, r->>0, r->>1, r->>2, 'whatsapp') returning id into v_contacto;
    insert into elius.identidades_contacto (tenant_id, contacto_id, canal_id, id_externo, nombre_en_canal)
    values (p_tenant, v_contacto, v_canal, r->>2, (r->>0) || ' ' || (r->>1)) returning id into v_ident;
    insert into elius.conversaciones (tenant_id, identidad_id, flujo) values (p_tenant, v_ident, 'general');
  end loop;
  insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion)
  values (p_tenant, 'demo_indice', '0', 'numero', 'Mensajes de prueba ya entregados (caso de demostración)')
  on conflict (tenant_id, clave) do update set valor = '0';
end $$;

-- Crea (o reutiliza) el negocio de prueba del caso para el usuario que llama y lo deja activo
create or replace function platform.cargar_caso_demo(p_vertical text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_slug text;
  v_tenant uuid; v_agente uuid; v_canal uuid; v_ident uuid; v_contacto uuid;
  v_cats uuid[] := '{{}}'; v_cat uuid; v_item uuid;
  r jsonb; k int;
begin
  if v_uid is null then raise exception 'Debe iniciar sesión' using errcode = '42501'; end if;
  if v_d is null then raise exception 'Caso desconocido: %', p_vertical; end if;
  v_slug := 'demo-' || p_vertical || '-' || substr(replace(v_uid::text, '-', ''), 1, 6);

  select id into v_tenant from platform.tenants where slug = v_slug;
  if v_tenant is not null then
    -- si quedó de una versión anterior del caso (otro número de clientes), se vuelve a sembrar
    if (select count(*) from elius.conversaciones where tenant_id = v_tenant) <> jsonb_array_length(v_d->'contactos') then
      perform elius.sembrar_clientes_demo(v_tenant, p_vertical);
    end if;
    perform platform.cambiar_tenant(v_tenant);
    return v_tenant;
  end if;

  v_tenant := platform.crear_tenant(v_d->>'negocio', v_slug, p_vertical);
  select id into v_agente from elius.agentes where tenant_id = v_tenant limit 1;
  insert into elius.canales (tenant_id, agente_id, tipo, nombre, identificador_externo)
  values (v_tenant, v_agente, 'whatsapp', 'WhatsApp de prueba', 'demo-' || v_slug) returning id into v_canal;

  for r in select * from jsonb_array_elements(v_d->'categorias') loop
    insert into elius.categorias_catalogo (tenant_id, nombre, orden)
    values (v_tenant, r #>> '{{}}', coalesce(array_length(v_cats, 1), 0)) returning id into v_cat;
    v_cats := v_cats || v_cat;
  end loop;

  k := 0;
  for r in select * from jsonb_array_elements(v_d->'items') loop
    k := k + 1;
    insert into elius.items_catalogo (tenant_id, categoria_id, tipo, sku, nombre, descripcion, precio, impuesto_pct, duracion_min)
    values (v_tenant, v_cats[(r->>'cat')::int + 1], r->>'tipo', r->>'sku', r->>'nombre', r->>'desc',
            (r->>'precio')::numeric, (r->>'iva')::numeric, nullif(r->>'dur', '')::int)
    returning id into v_item;
    insert into elius.medios_item (tenant_id, item_id, tipo_archivo, url, descripcion, orden)
    values (v_tenant, v_item, 'foto', '/demo/' || p_vertical || '-' || k || '.svg', r->>'nombre', 0);
  end loop;

  perform elius.sembrar_clientes_demo(v_tenant, p_vertical);

  perform platform.cambiar_tenant(v_tenant);
  return v_tenant;
end $$;

-- Entrega el siguiente mensaje del guion (20 clientes por caso, cada uno con la respuesta de Eli). El panel lo llama cada pocos segundos.
-- Si una persona tomó la conversación, Eli no responde en ella (RN-C19) y se salta ese mensaje.
create or replace function elius.siguiente_mensaje_demo()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_vertical text; v_slug text; v_d jsonb; v_guion jsonb; v_i int; v_total int;
  v_g jsonb; v_conv uuid; v_estado text; v_texto text;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  select slug, vertical into v_slug, v_vertical from platform.tenants where id = v_tenant;
  if v_slug not like 'demo-%' then raise exception 'Este negocio no es un caso de prueba'; end if;
  v_d := elius.datos_caso_demo(v_vertical);
  v_guion := v_d->'guion'; v_total := jsonb_array_length(v_guion);
  select valor::int into v_i from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_indice';

  loop
    if v_i >= v_total then
      return jsonb_build_object('terminado', true, 'indice', v_i, 'total', v_total);
    end if;
    v_g := v_guion -> v_i;
    select c.id, c.estado into v_conv, v_estado
    from elius.conversaciones c
    join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
    where c.tenant_id = v_tenant order by i.id_externo offset (v_g->>'conv')::int limit 1;
    exit when not (v_g->>'emisor' = 'eli' and v_estado in ('humano', 'pausa'));
    v_i := v_i + 1;
  end loop;

  v_texto := v_g->>'texto';
  insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, url_adjunto, estado_entrega, procesado)
  values (v_tenant, v_conv, v_g->>'emisor',
          case when v_texto like '📎%' or (v_g->>'img') is not null then 'imagen' else 'texto' end, v_texto,
          case when (v_g->>'img') is not null then '/demo/' || v_vertical || '-' || (v_g->>'img') || '.svg' end,
          case when v_g->>'emisor' = 'cliente' then 'recibido' else 'entregado' end, true);
  v_i := v_i + 1;
  update elius.parametros_negocio set valor = v_i::text where tenant_id = v_tenant and clave = 'demo_indice';
  return jsonb_build_object('terminado', v_i >= v_total, 'indice', v_i, 'total', v_total,
                            'emisor', v_g->>'emisor', 'conversacion_id', v_conv, 'clientes', (v_i + 1) / 2);
end $$;

-- Vuelve a empezar la demostración del negocio de prueba actual
create or replace function elius.reiniciar_demo()
returns void language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id();
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  if not exists (select 1 from platform.tenants where id = v_tenant and slug like 'demo-%') then
    raise exception 'Este negocio no es un caso de prueba';
  end if;
  delete from elius.mensajes where tenant_id = v_tenant;
  update elius.conversaciones set estado = 'en_progreso', asignado_a = null where tenant_id = v_tenant;
  update elius.parametros_negocio set valor = '0' where tenant_id = v_tenant and clave = 'demo_indice';
end $$;

revoke execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() from public, anon;
revoke execute on function elius.sembrar_clientes_demo(uuid, text) from public, anon, authenticated;
grant execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() to authenticated;
comment on function platform.cargar_caso_demo(text) is 'Crea el negocio de prueba de un caso (restaurante/veterinaria/aerolinea) con catálogo e imágenes';
comment on function elius.siguiente_mensaje_demo() is 'Entrega el siguiente mensaje (de 20) del guion del caso de prueba';
"""
open(os.path.join(os.path.dirname(__file__), '..', 'supabase', 'migrations', '20261123001200_casos_demo.sql'), 'w').write(sql)
open(os.path.join(os.path.dirname(__file__), '..', 'supabase', 'instalacion', '15_1200_casos_demo.sql'), 'w').write(sql)
print('SQL generado')
