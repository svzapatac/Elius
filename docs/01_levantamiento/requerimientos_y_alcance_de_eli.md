# Elius — Levantamiento de requerimientos: qué hace Eli y hasta dónde llega

**Versión:** 26-nov-2026 · **Complementa:** `levantamiento_informacion.md` (contexto, entrevistas, reglas de negocio y modelo de datos).

Eli es el agente de IA que atiende por WhatsApp a los clientes de cada negocio. Este documento dice, función por función, **qué hace Eli por su cuenta, qué deja a una persona y qué no puede hacer**. Eli está en **etapa de aprendizaje**: en todo lo que mueve dinero o compromete al negocio, Eli prepara y avisa, y **una persona decide**.

## 1. Principio general: tres niveles de autonomía

| Nivel | Significado | Ejemplos |
| --- | --- | --- |
| **A. Autónomo** | Eli lo hace solo, sin pedir permiso, porque es de bajo riesgo y reversible. | Responder preguntas del catálogo, tomar un pedido, agendar una reserva dentro de las reglas. |
| **B. Propone y espera** | Eli lee, compara y avisa; **una persona aprueba o rechaza**. Hasta que no decide, no pasa nada. | Verificar un comprobante de pago. |
| **C. Prohibido** | Eli no puede hacerlo; la base de datos lo impide aunque Eli quisiera. | Aprobar un pago, ver historia clínica, borrar datos, ver otro negocio. |

Los niveles B y C no dependen de que Eli "se porte bien": los hace cumplir la base de datos (triggers, RLS y permisos). Por eso un error de Eli no puede saltarse la regla.

## 2. Qué hace Eli, paso a paso

### 2.1 Atender al cliente por WhatsApp
- **Lo que hace (A):** responde con el catálogo, el horario, los precios y la base de conocimiento **de su propio negocio** (RN-C14). Agrupa los mensajes seguidos del cliente antes de responder (RN-C21). Usa el tono y las instrucciones que el Administrador configuró.
- **Dónde se detiene:** si no tiene una respuesta confiable, si el cliente pide hablar con una persona, o si el tema es una queja, un pago o una emergencia, **escala a un humano** (RN-C05). Mientras un humano tiene la conversación, Eli **no responde** (RN-C19). El Administrador o Soporte pueden **apagarla al instante** (RN-C20).
- **No puede:** inventar productos (solo vende lo del catálogo, RN-C15), ofrecer un plato agotado (RN-R03) ni responder con datos de otro negocio.

### 2.2 Tomar pedidos
- **Lo que hace (A):** crea la orden, agrega los ítems con sus modificadores (por ejemplo, el término de la carne), pide dirección y teléfono si es domicilio, y deja los totales calculados por la base (RN-C11).
- **Dónde se detiene:** el pedido avanza por estados (recibido → en preparación → listo → entregado) y **lo mueve el equipo**, no Eli. Una orden pagada no se modifica (RN-C12). Solo se cancela antes de entrar a preparación.

### 2.3 Agendar reservas
- **Lo que hace (A):** crea la reserva si hay cupo, está dentro del horario, no supera la capacidad de la mesa y respeta la anticipación máxima (RN-C07, RN-R01, RN-R02, RN-R10). Si la reserva es grande (hoy 20 personas o más) **avisa al Administrador** (RN-R08).
- **Dónde se detiene:** la reserva queda pendiente de pago/confirmación según la política del negocio. **Eli no cancela ni reembolsa**: eso es del Administrador. Si el cliente no llega, el sistema libera el recurso y un Operador marca "llegó / no llegó" (RN-C29).

### 2.4 Verificar pagos (el caso más delicado)

Hoy el negocio cobra por **comprobante**: el cliente paga por Nequi, Bre-B o transferencia y envía la foto.

**Lo que hace Eli (B: propone y espera):**
1. Lee la imagen del comprobante con IA y extrae: **monto, aplicación de origen, referencia, remitente, destinatario y fecha/hora**.
2. Compara el **monto leído con el saldo que debe esa orden**.
3. Revisa si el comprobante **ya se usó**: mismo archivo (huella digital) o misma aplicación y misma referencia que otro comprobante anterior (RN-C16).
4. Revisa si el **destinatario es una cuenta del negocio**.
5. Guarda todo y deja una **alerta escrita** en el comprobante, por ejemplo: *"ALERTA: comprobante repetido; monto 50.000 distinto al esperado 60.000"*.
6. **Avisa al gerente** con una notificación en su celular: cliente, monto y un enlace para aprobar o rechazar. Si el monto no coincide, el aviso lo destaca (RN-C27).

**Dónde se detiene:** Eli **no aprueba**. El comprobante queda en *pendiente* hasta que el Administrador lo revisa en el panel y lo aprueba o rechaza. Un Operador o Analista puede verlo pero **no decidir**; si lo intenta, recibe un error (RN-C26). Solo al aprobar se crea el pago y se confirma la orden y su reserva.

**Qué comprueba la base sola y qué comprueba el gerente:**

| Comprobación | Quién | Cómo |
| --- | --- | --- |
| Monto = lo que debe la orden | Automática (alerta) | Compara `monto_leido` con `monto_esperado` |
| Comprobante ya usado | Automática (alerta) | Mismo archivo, o misma app y referencia |
| Destinatario es del negocio | Automática (alerta) | Contra las cuentas de pago configuradas |
| **Hora y nombre del remitente** | **Gerente** | Eli las lee y las muestra junto al comprobante; la base las guarda pero **no las usa para alertar** todavía |
| Que el dinero **realmente llegó** a la cuenta | **Gerente** | Mira su app o extracto del banco; Eli no tiene acceso al banco |

> **Decisión de diseño:** como Eli está aprendiendo y una foto puede ser falsa o editada, **la última palabra siempre es del dueño**. Eli reduce el trabajo (lee, compara, detecta repetidos y avisa), pero no sustituye la verificación contra el banco.

**Pagos parciales (RN-C17):** el cliente puede pagar una parte; el saldo se cobra en efectivo al entregar. **Devoluciones (RN-C12, RN-C25):** un pago aprobado no se edita; una devolución se registra como otro pago negativo hecho por el gerente.

**Extensión futura (no activa):** cobro automático con llave Bre-B y QR de Factus Pay, que confirma solo por webhook sin intervención humana (RN-C22 a RN-C24). Está diseñado y probado en la base, pero **desactivado** porque no hubo credenciales de sandbox. Ver `docs/04_pagos/verificacion_de_pagos.md`.

### 2.5 Avisos y automatizaciones
- **Lo que hace (A):** cuando algo pasa (pedido confirmado, comprobante recibido, reserva grande, vuelo retrasado) la base genera un **evento** y n8n avisa al equipo o al cliente, crea el evento en Calendar o envía recordatorios.
- **Dónde se detiene:** los avisos son un **respaldo**: si el servicio de notificaciones falla, el dato se guarda igual y el error queda registrado (RN-C28).

### 2.6 Aprender de lo que hace el equipo (extensión de Chrome)
- **Lo que hace:** detecta preguntas frecuentes y objeciones en las conversaciones capturadas y las agrupa como **patrones sugeridos**.
- **Dónde se detiene (B):** Eli **solo usa los patrones que un Administrador aprobó** (RN-E02). Solo captura en sitios autorizados por el negocio y lo capturado lo ve quien lo capturó (RN-E01, RN-E03).

### 2.7 Según el tipo de negocio
| Negocio | Qué hace Eli | Límite |
| --- | --- | --- |
| **Restaurante** | Menú del día (solo si el dueño lo confirmó), pedidos, domicilios, reservas, celebraciones | No vende agotados; reservas grandes se avisan; la consignación no se reembolsa (política) |
| **Veterinaria** | Citas con mascota y veterinario, recordatorio de vacunas 7 días antes, tono empático | **No ve la historia clínica** (solo veterinarios con permiso); ante una urgencia pasa **de inmediato** a un humano (RN-V03, RN-V07) |
| **Aerolínea** | Consulta vuelos y reservas, localizador, avisos de cambios | No asigna una silla a dos pasajeros; no supera la capacidad; los avisos de cancelación son automáticos (RN-A04, A07, A09) |

## 3. Qué NO hace Eli (límites duros)

| Eli no puede… | Quién lo impide |
| --- | --- |
| Aprobar o rechazar un comprobante, ni crear pagos | Trigger `solo_admin_decide` (RN-C26) |
| Ver o modificar la historia clínica | Permiso especial + RLS (RN-V03) |
| Ver usuarios, auditoría, contraseñas o datos de otro negocio | RLS y rol Eli sin accesos especiales |
| Borrar definitivamente información | Soft delete; solo el Super Admin elimina de verdad |
| Cancelar o reembolsar una reserva por su cuenta | Solo el Administrador (`cancelar_reserva`) |
| Seguir respondiendo si un humano tomó la conversación o si fue apagada | Trigger `t20_antes_de_mensaje` (RN-C19/C20) |
| Responder a dos mensajes a la vez en una misma conversación | `tomar_bloqueo` (RN-C21) |
| Cobrar por Factus Pay | Está desactivado hasta tener credenciales |
| Confirmar contra el banco que el dinero llegó | No tiene integración bancaria |

## 4. Transparencia y control
- **Todo queda auditado** (RN-C32): cada cambio, quién lo hizo, con qué rol, antes y después; también cada intento bloqueado.
- **Consumo de IA registrado** (RN-C13): tokens, costo y latencia por llamada.
- **Errores de Eli** visibles para Soporte en el Centro de soporte.
- **Interruptor de emergencia:** el Administrador o Soporte apagan a Eli de inmediato.

## 5. Requerimientos funcionales (resumen verificable)

| ID | Requerimiento | Nivel | Regla |
| --- | --- | --- | --- |
| RF-01 | Eli responde solo con el catálogo y conocimiento de su negocio | A | RN-C14, C15 |
| RF-02 | Eli escala a un humano ante queja, pago, emergencia o falta de confianza | A | RN-C05 |
| RF-03 | Eli se calla cuando un humano toma la conversación o se la apaga | C | RN-C19, C20 |
| RF-04 | Eli crea pedidos con totales calculados por la base | A | RN-C11 |
| RF-05 | Eli agenda reservas respetando horario, capacidad y cruces | A | RN-C07, R01, R02 |
| RF-06 | Eli lee comprobantes y compara monto, repetido y destinatario | B | RN-C16 |
| RF-07 | Eli avisa al gerente de cada comprobante, destacando discrepancias | B | RN-C27 |
| RF-08 | Solo el Administrador aprueba o rechaza pagos | C | RN-C26 |
| RF-09 | Eli propone patrones; solo los aprobados se usan | B | RN-E02 |
| RF-10 | Eli en veterinaria no accede a la historia clínica | C | RN-V03 |
| RF-11 | Toda acción queda auditada y el consumo de IA registrado | — | RN-C13, C32 |

## 6. Limitaciones conocidas (dicho con honestidad)
1. **La lectura del comprobante es IA:** puede equivocarse con imágenes borrosas, recortadas o editadas. Por eso el gerente decide.
2. **No hay verificación bancaria automática:** hasta activar Factus Pay (o similar), alguien debe mirar su banco.
3. **Hora y nombre del remitente se muestran, no se validan automáticamente.** Es una mejora futura: alertar si la hora del comprobante es anterior al pedido o si el remitente no coincide con el contacto.
4. **Eli en aprendizaje:** el alcance del nivel A se irá ampliando a medida que el equipo confíe en sus resultados; cualquier ampliación pasa por el Administrador.
5. Reglas marcadas "por validar" en el levantamiento (RN-C06, RN-V04, RN-V05, RN-A08, RN-E03) aún necesitan confirmación con el negocio.
