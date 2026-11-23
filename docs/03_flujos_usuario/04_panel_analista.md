# Flujo de usuario · Panel del Analista

```mermaid
flowchart TD
  A([Inicia sesión]) --> B[Elige el periodo]
  B --> C{¿Qué analiza?}
  C --> D[Ventas por día y canal<br/>v_ventas_diarias]
  C --> E[Productos más vendidos<br/>v_items_mas_vendidos]
  C --> F[Desempeño de Eli<br/>v_metricas_conversaciones]
  C --> G[Embudo de conversión<br/>v_embudo_diario]
  C --> H[Costo y latencia de IA<br/>v_consumo_ia_mensual]
  C --> I[Saldos por cobrar<br/>v_saldo_ordenes]
  C --> J[Vistas del plugin<br/>ocupación de vuelos · vacunas por vencer]
  D --> K{¿Exportar?}
  E --> K
  F --> K
  G --> K
  H --> K
  I --> K
  J --> K
  K -- Sí --> L([Descarga CSV])
  K -- No --> C
  C -.->|"intenta editar"| M([La base lo rechaza:<br/>rol analista = solo lectura])
```

**Qué no puede hacer:** escribir, ver la auditoría, ver datos sensibles ni la configuración. Lo bloquea RLS, no solo el panel (prueba 4 de `database/tests`).
