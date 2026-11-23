# Arquitectura · Extensión de Chrome

**Quién la usa:** Operadores y Administradores que todavía atienden por WhatsApp Web u otros sitios. La extensión captura las conversaciones (solo en sitios autorizados) para que Elius detecte preguntas frecuentes, objeciones e intenciones y Eli aprenda de ellas.

```mermaid
flowchart LR
  OP["Operador"] --> CH["Navegador con la extensión"]
  CH -->|"login"| AUTH["Supabase Auth"]
  CH -->|"¿sitio autorizado?"| SA["ext.sitios_autorizados"]
  CH -->|"JWT"| API["API PostgREST"]
  API --> SEC{"RLS + política RESTRICTIVA<br/>solo quien captura (RN-E01)"}
  SEC --> I["ext.instalaciones_extension"]
  SEC --> C["ext.conversaciones_capturadas"]
  SEC --> M["ext.mensajes_capturados<br/>+ embedding"]
  EF["Edge Function: detector de patrones"] -->|"agrupa por similitud (pgvector)"| P["ext.patrones (sugerido)"]
  EF --> E["ext.evidencias_patron"]
  AD["Administrador"] -->|"aprueba"| P
  P -->|"solo aprobados"| ELI["Eli los usa como conocimiento"]
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class SEC dec
```

## Privacidad

- Solo captura en los dominios de `ext.sitios_autorizados` (RN-E03).
- Lo capturado lo ve **quien lo capturó**. Para ver lo de todos hace falta nivel **total** en `ext` (Administrador). Lo hace cumplir una política **RESTRICTIVA**, que se suma con AND a las demás (prueba 15).
- Un patrón no llega a Eli hasta que un Administrador lo aprueba (RN-E02, `CHECK ck_patrones_aprobacion`).
