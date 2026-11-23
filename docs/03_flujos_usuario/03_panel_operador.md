# Flujo de usuario · Panel del Operador

## Atender un pendiente que escaló Eli

```mermaid
flowchart TD
  A([Eli no puede resolver:<br/>queja, pago, emergencia o pedido del cliente]) --> B[elius.escalar_conversacion]
  B --> C[Se asigna por turnos<br/>al Operador con menos casos]
  C --> D[Llega push y aparece en Pendientes]
  D --> E[El Operador abre la conversación]
  E --> F[Tomar conversación<br/>Eli deja de responder]
  F --> G[Responde al cliente]
  G --> H{¿Resuelto?}
  H -- No --> G
  H -- Sí --> I[Devolver a Eli]
  I --> J[Se cierra el escalamiento<br/>Eli vuelve a atender]
```

## Revisar un comprobante de pago (cobro tradicional)

```mermaid
flowchart TD
  A([El cliente envía la foto del comprobante]) --> B[Eli lo lee y lo registra<br/>elius.registrar_comprobante]
  B --> C{¿Alertas?<br/>monto distinto · repetido · destinatario raro}
  C -- Con alerta --> D[Aparece arriba en Comprobantes, marcado]
  C -- Sin alerta --> E[Aparece en Comprobantes]
  D --> F{El Operador revisa}
  E --> F
  F -- Rechazar --> G[rechazar_comprobante con motivo<br/>Eli avisa al cliente]
  F -- Aprobar --> H{¿Cubre el total?}
  H -- Sí --> I[aprobar_comprobante<br/>orden confirmada]
  H -- No --> J{¿El resto se paga<br/>en efectivo al entregar?}
  J -- Sí --> K[aprobar_comprobante con contra entrega<br/>orden confirmada]
  J -- No --> L[Pago parcial registrado<br/>Eli pide el resto]
  I --> M([Pasa a cocina o a la reserva])
  K --> M
```

## Reservas del día

```mermaid
flowchart TD
  A([Abre Agenda del día<br/>elius.v_agenda_dia]) --> B{¿Llegó el cliente?}
  B -- Sí --> C[Marcar llegada<br/>estado asistió]
  B -- No --> D{¿Pasó la tolerancia?<br/>hoy 20 minutos}
  D -- No --> B
  D -- Sí --> E[Tarea programada: no asistió<br/>se liberan las mesas]
  C --> F[Registrar novedades y salida]
```

## Cocina y domicilios (restaurante)

```mermaid
flowchart LR
  A[Orden confirmada] --> B[Comanda por estación<br/>parrilla, bar, fríos]
  B --> C[Cocina: en preparación]
  C --> D[Lista]
  D --> E{¿Tipo de entrega?}
  E -- Sitio o recoger --> F[Entregada]
  E -- Domicilio --> G[Domiciliario toma la entrega]
  G --> H[En camino]
  H --> I[Cobra el saldo en efectivo si lo hay]
  I --> F
```

**Reglas que aplican:** RN-C16, RN-C17, RN-C18, RN-C19, RN-C21, RN-C12, RN-R07, RN-R09.
