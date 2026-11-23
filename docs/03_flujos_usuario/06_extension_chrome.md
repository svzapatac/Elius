# Flujo de usuario · Extensión de Chrome

```mermaid
flowchart TD
  A([El Operador instala la extensión<br/>e inicia sesión]) --> B[Se registra la instalación<br/>ligada a su membresía]
  B --> C[Abre WhatsApp Web u otro sitio]
  C --> D{¿Sitio autorizado<br/>por el Administrador?}
  D -- No --> E([No captura nada])
  D -- Sí --> F[Captura la conversación y sus mensajes]
  F --> G[Se calculan embeddings]
  G --> H[El detector agrupa mensajes parecidos]
  H --> I[Propone un patrón:<br/>pregunta frecuente, objeción o intención]
  I --> J{El Administrador revisa}
  J -- Rechaza --> K[Patrón rechazado]
  J -- Aprueba --> L[Patrón aprobado con respuesta sugerida]
  L --> M([Eli lo usa al responder])
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class D,J dec
  class A,E,M ok
```

**Privacidad:** cada Operador solo ve lo que capturó; el Administrador ve todo (RN-E01). Solo se captura en sitios autorizados (RN-E03). Ningún patrón llega a Eli sin aprobación (RN-E02).
