# Flujo de usuario · Panel de Plataforma

## Super Admin

```mermaid
flowchart TD
  A([Inicia sesión]) --> B{¿Tiene asignación<br/>super_admin vigente?}
  B -- No --> X([Sin acceso al panel])
  B -- Sí --> C[Tablero de la plataforma<br/>reportes.v_resumen_tenants]
  C --> D{¿Qué necesita?}
  D --> E[Planes: crear o ajustar límites]
  D --> F[Plugins: publicar versión o desactivar]
  D --> G[Tenants: suspender o reactivar]
  D --> H[Uso y costo de IA por negocio<br/>reportes.v_uso_por_tenant]
  D --> I[Asignar Soporte a una persona del equipo]
  G --> J{¿Cancelar o suspender?}
  J -- Suspender --> K[estado = suspendido<br/>sus usuarios dejan de ver datos]
  J -- Cancelar --> L[estado = cancelado]
  H --> M([Exporta el reporte])
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class B,D,J dec
  class A,M,X ok
```

## Soporte

```mermaid
flowchart TD
  A([El negocio pide ayuda<br/>por WhatsApp o correo]) --> B[El Administrador autoriza a Soporte<br/>platform.autorizar_soporte · máx. 7 días]
  B --> C([Soporte inicia sesión])
  C --> D[Elige el negocio autorizado<br/>X-Tenant-ID]
  D --> E{¿Autorización vigente?}
  E -- No --> F([No ve nada: 0 filas])
  E -- Sí --> G{¿Qué resuelve?}
  G --> H[Conectar o reparar WhatsApp]
  G --> I[Revisar errores de Eli<br/>elius.errores_agente]
  G --> J[Configurar Factus Pay]
  G --> K[Ajustar catálogo o parámetros]
  H --> L[Cada cambio queda auditado<br/>origen = soporte]
  I --> L
  J --> L
  K --> L
  L --> M{¿Terminó?}
  M -- Sí --> N[El Administrador revoca<br/>o la autorización vence sola]
  M -- No --> G
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class E,G,M dec
  class A,C,F ok
```

**Reglas que aplican:** RN-P16 (acceso con autorización y vencimiento), RN-P06 (tenant suspendido no opera), RN-P15 (auditoría).
