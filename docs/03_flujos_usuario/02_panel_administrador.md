# Flujo de usuario · Panel del Administrador

## Primer uso: crear el negocio

```mermaid
flowchart TD
  A([Se registra en Elius]) --> B[Completa nombre, identificador y vertical]
  B --> C[platform.crear_tenant]
  C --> D[Se crea el tenant en prueba 14 días<br/>queda como Administrador]
  D --> E[Se instala el plugin de su vertical]
  E --> F[Se crea Eli con un tono según la vertical]
  F --> G[Se cargan parámetros base<br/>anticipación, tolerancia, grupo grande]
  G --> H[Conecta su WhatsApp<br/>Embedded Signup de Meta]
  H --> I[Carga su catálogo, horarios y fotos]
  I --> J{¿Usará Factus Pay?}
  J -- Sí --> K[Registra la cuenta de Factus<br/>credenciales en Vault]
  J -- No --> L[Escribe sus cuentas de pago<br/>parámetro cuentas_pago]
  K --> M[Invita a su equipo]
  L --> M
  M --> N([Eli empieza a atender])
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class J dec
  class A,N ok
```

## Día a día del Administrador

```mermaid
flowchart TD
  A([Inicia sesión]) --> B[Tablero: ventas de hoy, pendientes,<br/>comprobantes con alerta]
  B --> C{¿Qué hace?}
  C --> D[Equipo]
  C --> E[Eli]
  C --> F[Catálogo y menú del día]
  C --> G[Pagos]
  C --> H[Auditoría]
  D --> D1[Invitar con un rol general]
  D --> D2[Asignar cargo: mesero, veterinario…]
  D --> D3[Activar acceso especial<br/>ej. historia clínica]
  D --> D4[Autorizar a Soporte por horas]
  E --> E1[Ajustar tono, bienvenida, instrucciones]
  E --> E2{¿Emergencia?}
  E2 -- Sí --> E3[Apagar a Eli<br/>elius.encender_eli false]
  F --> F1[Marcar agotados]
  F --> F2[Confirmar el menú del día<br/>sin confirmar, Eli no lo ofrece]
  G --> G1[Revisar comprobantes con alerta]
  G --> G2[Ver saldos y recaudos de Factus]
  H --> H1[Ver quién cambió qué y cuándo]
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class C,E2 dec
  class A ok
```

**Reglas que aplican:** RN-P04 (último Administrador), RN-P08 (crear tenant), RN-P10 (límite del plan), RN-P12 (invitaciones), RN-C20 (apagar a Eli), RN-R11 (menú confirmado), RN-V03 (acceso especial).
