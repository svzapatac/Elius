# Flujo de sistema · Avisos al celular, triggers y webhooks

Lo que pasa por dentro cuando llega un comprobante, y cómo activa un Administrador los avisos. Es el complemento técnico del flujo del Administrador ([02](02_panel_administrador.md)). Decisión de diseño: DT-19 y DT-20 del [levantamiento](../01_levantamiento/levantamiento_informacion.md).

## De comprobante a notificación, y de la notificación a la decisión

```mermaid
flowchart TD
  A([Eli o n8n guardan el comprobante<br/>elius.registrar_comprobante]) --> B[(elius.comprobantes_pago)]
  B -- AFTER INSERT · t56 --> C[app.avisar_comprobante_celular]
  C --> D[app.enviar_push_tenant<br/>suscripciones de los Administradores activos]
  D -- "pg_net: POST /enviar + token" --> E[Servicio notificaciones<br/>Easypanel · Web Push y VAPID]
  E --> F[Servicio push del navegador<br/>Google · Apple · Mozilla]
  F --> G([Celular del Administrador])
  C -- "pg_net: POST a ntfy.sh<br/>tema secreto" --> H[ntfy.sh<br/>respaldo]
  H --> G
  C -. si algo falla .-> I[Solo deja un aviso en el registro<br/>el comprobante se guarda igual]
  G --> J[Abre /#/comprobantes]
  J --> K[aprobar_comprobante<br/>o rechazar_comprobante]
  K -- BEFORE UPDATE · t53 y t55 --> L{¿Quien decide<br/>es Administrador?}
  L -- No --> M([Error: solo un Administrador decide])
  L -- Sí --> N[Se registra el pago, se confirma la orden<br/>y queda en la auditoría]
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class L dec
  class A,G,M,N ok
```

## Activar los avisos en un dispositivo

```mermaid
flowchart TD
  A([Administrador abre Comprobantes]) --> B[Activar notificaciones<br/>en este dispositivo]
  B --> C{¿Permite las notificaciones<br/>en el navegador?}
  C -- No --> X([No se activa<br/>puede intentarlo otra vez])
  C -- Sí --> D[Service worker registrado<br/>pide la llave pública VAPID<br/>elius.push_clave_publica]
  D --> E[El navegador crea la suscripción<br/>endpoint, p256dh y auth]
  E --> F[elius.guardar_suscripcion_push]
  F --> G{¿Es Administrador?}
  G -- No --> Y([La base lo rechaza])
  G -- Sí --> H[(platform.push_suscripciones)]
  H --> I[Enviar notificación de prueba<br/>elius.enviar_push_prueba]
  I --> J([Suena el celular])
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class C,G dec
  class A,J,X,Y ok
```

En iPhone el panel debe agregarse antes a la pantalla de inicio. Los secretos (token del servicio y llave privada VAPID) no están en el repositorio: viven en las variables de entorno del servicio.

**Reglas que aplican:** RN-C16, RN-C26, RN-C27, RN-C28.
