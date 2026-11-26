-- 3700 · Cada trigger lleva su descripción (regla de negocio + para qué sirve) y una vista para consultarlos.
--  · La auditoría del panel usa v_triggers_tabla para decir qué triggers actuaron en cada movimiento y para qué.
create temp table _desc_trg (nombre text primary key, descripcion text);
insert into _desc_trg values
 ('t00_origen_conexion',        'Auditoría: completa cada registro con la instancia, base, puerto, IP del cliente, login de BD y correo de quien lo hizo.'),
 ('t00_sin_baja_directa',       'Protección: nadie borra filas con DELETE; la baja se hace marcando la fila (borrado lógico) para conservar el historial.'),
 ('t00_sin_truncate_directo',   'Protección: bloquea TRUNCATE, que vaciaría la tabla completa de un golpe.'),
 ('t01_actualizado_en',         'Genérico (BEFORE UPDATE): pone actualizado_en = now() para saber cuándo cambió la fila por última vez.'),
 ('t02_auditoria',              'Genérico (AFTER): escribe en la bitácora quién, con qué rol, qué tabla y fila, y los datos antes y después (RN-P15).'),
 ('t02_auditoria_mensaje_humano','Auditoría: registra cuando una persona (no Eli) responde un mensaje a un cliente, sin guardar el texto completo.'),
 ('t10_nivel_rol',              'RN-P13: un rol de plataforma no se asigna dentro de un negocio, ni al revés.'),
 ('t11_ultimo_admin',           'RN-P04: impide quitar, desactivar o cambiar de rol al último Administrador de un negocio.'),
 ('t12_limite_usuarios',        'RN-P10: no deja pasar el máximo de usuarios que permite el plan.'),
 ('t20_antes_de_mensaje',       'RN-C19/C20/C06: Eli no habla si atiende un humano o está apagada; un mensaje del cliente reabre una conversación cerrada.'),
 ('t21_despues_de_mensaje',     'Actualiza la fecha del último mensaje y del último contacto de la conversación.'),
 ('t22_asignar_escalamiento',   'RN-C18: asigna el caso por turnos al Operador con menos casos abiertos.'),
 ('t23_despues_de_escalamiento','RN-C19: pasa la conversación a un humano; al resolver el último caso, la devuelve a Eli.'),
 ('t30_codigo_reserva',         'Genera el código o localizador de 6 caracteres, único dentro del negocio.'),
 ('t31_fecha_reserva',          'RN-C08/R10: no se reserva en el pasado ni más allá de la anticipación configurada.'),
 ('t32_transicion_reserva',     'RN-C09: solo se permiten los cambios de estado válidos (pendiente → confirmada → asistió, etc.).'),
 ('t33_eventos_reserva',        'RN-R08: emite eventos de salida (para n8n), incluido el aviso de grupo grande.'),
 ('t40_numero_orden',           'RN-C10: numera las órdenes de forma consecutiva por negocio, con bloqueo para que dos pedidos simultáneos no repitan número.'),
 ('t41_antes_de_linea',         'RN-C12/R03: toma el precio del catálogo, calcula la línea y bloquea ítems agotados u órdenes ya pagadas.'),
 ('t42_recalcular_orden',       'RN-C11: recalcula subtotal, impuestos y total de la orden cada vez que cambian sus líneas.'),
 ('t43_proteger_totales',       'RN-C11: los totales de una orden no se escriben a mano; solo los calcula el sistema.'),
 ('t44_eventos_orden',          'Emite un evento de salida por cada cambio de estado de la orden (cocina, domicilio, cliente).'),
 ('t50_proteger_pago',          'RN-C12: un pago aprobado no se modifica ni se borra; se corrige con otro pago.'),
 ('t51_aplicar_pago',           'RN-C17: si lo pagado más lo que se cobrará al entregar cubre el total, confirma la orden y su reserva.'),
 ('t52_revisar_comprobante',    'RN-C16: marca alertas en el comprobante: repetido, monto distinto o destinatario raro.'),
 ('t53_evento_comprobante',     'Avisa al equipo que llegó un comprobante de pago.'),
 ('t54_recaudo_pagado',         'RN-C22: cuando la pasarela confirma el recaudo, crea el pago (una sola vez).'),
 ('t55_solo_admin_decide',      'RN-C26: solo el Administrador aprueba o rechaza comprobantes.'),
 ('t56_aviso_celular_comprobante','Avisa por notificación al celular del equipo cuando llega un comprobante.'),
 ('t90_accesos_bd',             'Al crear un negocio, le prepara los accesos de base de datos por rol.'),
 ('t91_usuarios_por_negocio',   'Al crear un negocio, crea sus usuarios de prueba (superadmin, administrador, operador y soporte).'),
 ('tv1_no_atender_fallecida',   'RN-V06: una mascota fallecida no recibe citas.'),
 ('tv2_historia_inmutable',     'RN-V04: la historia clínica no se edita ni se borra pasadas 24 horas.'),
 ('tr0_precio_opcion',          'Toma el recargo de la opción elegida desde el catálogo del restaurante.'),
 ('tr1_sumar_recargos',         'RN-R04: suma los recargos de las opciones en la línea de la orden.'),
 ('ta1_capacidad',              'RN-A04: los cupos de un vuelo no superan la capacidad de la aeronave.'),
 ('ta2_ocupar_cupo',            'RN-A04: ocupa un cupo por pasajero; el CHECK impide vender más de lo disponible.'),
 ('ta3_infantes',               'RN-A06: en una reserva los infantes no superan a los adultos (se revisa al terminar la transacción).'),
 ('ta4_silla',                  'RN-A07: una silla no se asigna dos veces en el mismo vuelo.'),
 ('ta5_evento_vuelo',           'RN-A09: si el vuelo se cancela o se retrasa, avisa a sus pasajeros mediante un evento de salida.');

do $$
declare r record;
begin
  for r in
    select n.nspname as esq, c.relname as tabla, t.tgname as trg, d.descripcion
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join _desc_trg d on d.nombre = t.tgname
    where not t.tgisinternal
  loop
    execute format('comment on trigger %I on %I.%I is %L', r.trg, r.esq, r.tabla, r.descripcion);
  end loop;
end $$;

drop table _desc_trg;

create or replace view elius.v_triggers_tabla with (security_invoker = true) as
select n.nspname::text as esquema, c.relname::text as tabla, t.tgname::text as trigger,
       case when t.tgtype & 2 = 2 then 'BEFORE' when t.tgtype & 64 = 64 then 'INSTEAD OF' else 'AFTER' end as momento,
       concat_ws(', ', case when t.tgtype & 4 = 4 then 'INSERT' end, case when t.tgtype & 16 = 16 then 'UPDATE' end,
                       case when t.tgtype & 8 = 8 then 'DELETE' end, case when t.tgtype & 32 = 32 then 'TRUNCATE' end) as eventos,
       obj_description(t.oid, 'pg_trigger') as descripcion
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal and n.nspname in ('elius', 'platform', 'audit', 'ext') or (not t.tgisinternal and n.nspname like 'plugin\_%');
grant select on elius.v_triggers_tabla to authenticated, service_role, elius_app;
comment on view elius.v_triggers_tabla is 'Triggers de cada tabla: cuándo se disparan y para qué sirven (lo usa la auditoría del panel)';
