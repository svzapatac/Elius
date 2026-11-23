# Flujo de usuario · Cliente final por WhatsApp con Eli

## Comprar y pagar

```mermaid
flowchart TD
  A([El cliente escribe al WhatsApp del negocio]) --> B[Eli identifica al cliente<br/>identidades_contacto]
  B --> C{¿Es nuevo?}
  C -- Sí --> D[Crea el contacto y pide<br/>autorización de datos · Ley 1581]
  C -- No --> E[Recupera su historial]
  D --> F[Conversa: menú, fotos, precios]
  E --> F
  F --> G[Arma el pedido en el borrador]
  G --> H[crear_orden y agregar_item<br/>totales calculados por la base]
  H --> I{estrategia_cobro}
  I -- llave Bre-B Factus --> J[Envía llave y QR<br/>por el monto exacto]
  J --> K{¿Pagó antes de vencer?}
  K -- Sí --> L[Webhook de Factus<br/>pago confirmado automático]
  K -- No --> M[Renueva el QR con la misma referencia]
  M --> K
  I -- comprobante --> N[Envía las cuentas del negocio]
  N --> O[El cliente manda la foto]
  O --> P[Un Operador aprueba]
  L --> Q([Pedido confirmado: cocina o entrega])
  P --> Q
  F --> R{¿Queja, emergencia<br/>o pide una persona?}
  R -- Sí --> S([Escala a un Operador])
```

## Reservar

```mermaid
flowchart TD
  A([Pide una reserva]) --> B[Eli pregunta fecha, hora y personas]
  B --> C{¿Dentro del horario y<br/>de la anticipación máxima?}
  C -- No --> B
  C -- Sí --> D{¿Hay recursos libres<br/>con capacidad suficiente?}
  D -- No --> E[Ofrece otro horario]
  E --> B
  D -- Sí --> F[agendar_reserva<br/>estado pendiente de pago]
  F --> G{¿Grupo grande?}
  G -- Sí --> H[Aviso al Administrador]
  G -- No --> I[Cobra la consignación]
  H --> I
  I --> J([Pago aprobado: reserva confirmada<br/>evento a Google Calendar])
```

**Reglas que aplican:** RN-C03 (consentimiento), RN-C22, RN-C23 (cobro), RN-C07, RN-R01, RN-R02, RN-R08, RN-R10 (reservas), RN-C18 (escalamiento).
