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
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class H dec
  class A ok
```

## Comprobantes de pago: el Operador consulta, el Administrador decide

```mermaid
flowchart TD
  A([El cliente envía la foto del comprobante]) --> B[Eli lo lee y lo registra<br/>elius.registrar_comprobante]
  B --> C{¿Alertas?<br/>monto distinto · repetido · destinatario raro}
  C -- Con alerta --> D[Aparece arriba en Comprobantes, marcado]
  C -- Sin alerta --> E[Aparece en Comprobantes]
  B --> N[Un trigger avisa al celular del Administrador]
  D --> F[El Operador lo ve y puede atender al cliente]
  E --> F
  F --> G{¿Intenta aprobar o rechazar?}
  G -- No --> H([Espera la decisión del Administrador<br/>y sigue con pendientes y reservas])
  G -- Sí --> X([La base lo rechaza:<br/>solo un Administrador decide])
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class C,G dec
  class A,H,X ok
```

## Reservas del día: llegó o no llegó (los tres casos)

```mermaid
flowchart TD
  A([Abre Reservas<br/>elius.v_agenda_dia]) --> B{¿Llegó el cliente?}
  B -- Sí --> C[Botón Llegó<br/>elius.marcar_llegada → asistió]
  B -- No --> D{¿Pasó la tolerancia?<br/>hoy 20 minutos}
  D -- No --> B
  D -- Sí --> E[Botón No llegó<br/>elius.marcar_no_llegada → no asistió<br/>se libera la mesa, la cita o el cupo]
  C --> F[Registrar novedades y salida]
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class B,D dec
  class A ok
```

Lo mismo en restaurante (mesa), veterinaria (cita) y aerolínea (check-in del pasajero). Lo pueden marcar el Operador y el Administrador.

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
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class E dec
```

**Reglas que aplican:** RN-C16, RN-C17, RN-C18, RN-C19, RN-C21, RN-C12, RN-R07, RN-R09.
