# Procedimientos (funciones RPC)

Los procedimientos agrupan operaciones que tocan varias tablas y **deben ocurrir completas o no ocurrir**. Se llaman desde los paneles, Eli y las Edge Functions con `supabase.rpc('nombre', {...})`. El código está en `…0700_procedimientos.sql` y `…1000_integraciones.sql`; el inventario completo, en el [anexo D](anexo_d_inventario_funciones.md).

## INVOKER o DEFINER

| Seguridad | Corre con | Cuándo se usa |
| --- | --- | --- |
| `SECURITY INVOKER` (por defecto) | Los permisos de quien llama: **RLS sigue aplicando** | Casi todos |
| `SECURITY DEFINER` + `search_path = ''` | Los permisos del dueño | Solo si hay que crear filas que el usuario aún no puede ver (crear un negocio, aceptar una invitación) o si lo llama únicamente el servidor (webhook, Vault) |

## Plataforma

| Procedimiento | Quién lo llama | Qué hace | Regla |
| --- | --- | --- | --- |
| `platform.crear_tenant(nombre, slug, vertical, plan)` | Quien se registra | Crea el negocio, lo deja como Administrador, instala el plugin, crea a Eli y los parámetros base | RN-P08 |
| `platform.cambiar_tenant(tenant)` | Usuario con varios negocios | Cambia la membresía predeterminada (el cliente refresca el JWT) | DT-04 |
| `platform.invitar_usuario(email, rol)` | Administrador | Crea la invitación; devuelve el token una sola vez y guarda solo su hash | RN-P11, RN-P12 |
| `platform.aceptar_invitacion(token)` | El invitado | Valida token, vencimiento y correo; crea la membresía | RN-P12 |
| `platform.otorgar_acceso_especial(membresía, permiso, motivo, vence)` | Administrador | Activa un acceso especial del plugin | sección 10.2 |
| `platform.autorizar_soporte(usuario, motivo, horas)` | Administrador | Autoriza a Soporte por un tiempo | RN-P16 |

## Conversaciones

| Procedimiento | Quién | Qué hace | Regla |
| --- | --- | --- | --- |
| `elius.tomar_bloqueo(conversación, segundos)` / `soltar_bloqueo` | Eli | Un solo proceso por conversación; el bloqueo vence solo | RN-C21 |
| `elius.escalar_conversacion(conversación, motivo, …)` | Eli | Crea el pendiente; el trigger lo asigna por turnos | RN-C18 |
| `elius.tomar_conversacion(conversación)` | Operador | Pasa la conversación a humano | RN-C19 |
| `elius.devolver_a_eli(conversación)` | Operador | Cierra los pendientes y devuelve la conversación a Eli | RN-C19 |
| `elius.resolver_escalamiento(id)` | Operador | Cierra un pendiente | RN-C18 |
| `elius.encender_eli(activo)` | Administrador o Soporte | Interruptor de emergencia | RN-C20 |

## Reservas, órdenes y pagos

| Procedimiento | Quién | Qué hace | Regla |
| --- | --- | --- | --- |
| `elius.agendar_reserva(contacto, tipo, inicio, fin, personas, recursos[], …)` | Eli, Operador | Valida horario y capacidad, crea la reserva y ocupa los recursos (la exclusión evita cruces) | RN-R01, RN-R02, RN-C07 |
| `elius.marcar_llegada(reserva)` | Operador | Registra la llegada | — |
| `elius.marcar_no_asistidas()` | Solo backend, tarea programada | Marca no asistió después de la tolerancia y libera recursos | RN-R07 |
| `elius.crear_orden(...)`, `elius.agregar_item(orden, ítem, cantidad)` | Eli, Operador | Crea la orden; el precio y los totales los pone la base | RN-C10, RN-C11 |
| `elius.registrar_comprobante(...)` | Eli | Guarda el comprobante con el saldo como monto esperado | RN-C16 |
| `elius.aprobar_comprobante(comprobante, resto_contra_entrega)` | Administrador | **Atómico**: crea el pago, deja el resto contra entrega y confirma la orden; un repetido devuelve `ya_pagada` | RN-C16, RN-C17 |
| `elius.rechazar_comprobante(comprobante, motivo)` | Operador | Rechaza con motivo | RN-C16 |
| `elius.estrategia_cobro(monto)` | Eli | `llave_breb_factus` o `comprobante` | RN-C22, RN-C23 |
| `elius.registrar_recaudo(orden, código, monto, llave, qr, expira)` | Edge Function con el JWT de Eli | Guarda el recaudo de Factus; si se repite la referencia, renueva el QR | RN-C23 |
| `elius.procesar_webhook_factus(pasarela, clave_valida, carga)` | Solo backend | Guarda la notificación, valida clave y monto, aplica el pago, idempotente | RN-C24 |
| `elius.webhook_factus(...)` | Solo `service_role` | Punto de entrada del webhook: fija el tenant de la pasarela y llama al anterior | RN-C24 |
| `elius.srv_secreto`, `srv_actualizar_secreto`, `srv_pasarela_webhook` | Solo `service_role` | Leer y rotar secretos de Vault | DT-18 |

## Plugins

| Procedimiento | Qué hace | Regla |
| --- | --- | --- |
| `plugin_restaurant.confirmar_menu_dia(menú)` | El dueño confirma el menú; sin confirmar, Eli no lo ofrece | RN-R11 |
| `plugin_restaurant.agregar_opcion(línea, opción, cantidad)` | Agrega una opción respetando el máximo del grupo | RN-R04 |
| `plugin_vet.registrar_vacuna(mascota, vacuna, lote, …)` | Registra y calcula la próxima dosis desde el catálogo | RN-V05 |
| `plugin_airline.hacer_checkin(tiquete, silla)` | Check-in entre 48 h y 1 h antes de salir | RN-A08 |

## Ejemplo desde un panel

```ts
// Aprobar un comprobante y dejar el resto para cobrar al entregar
const { data, error } = await supabase.schema('elius')
  .rpc('aprobar_comprobante', { p_comprobante: id, p_resto_contra_entrega: true });
// data = 'pagada' | 'pago_parcial' | 'ya_pagada'
```
