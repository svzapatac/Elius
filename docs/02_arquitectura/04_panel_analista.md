# Arquitectura · Panel del Analista

**Quién lo usa:** el contador, un socio o quien revisa resultados. **Solo lee y exporta**; no modifica nada.

```mermaid
flowchart LR
  AN["Analista"] --> PN["Panel del Analista"]
  PN -->|"login"| AUTH["Supabase Auth"]
  PN -->|"JWT"| API["API PostgREST"]
  API --> SEC{"RLS<br/>rol analista = lectura"}
  SEC --> V1["elius.v_ventas_diarias"]
  SEC --> V2["elius.v_items_mas_vendidos"]
  SEC --> V3["elius.v_metricas_conversaciones"]
  SEC --> V4["elius.v_embudo_diario"]
  SEC --> V5["elius.v_consumo_ia_mensual"]
  SEC --> V6["elius.v_saldo_ordenes"]
  SEC --> V7["Vistas del plugin<br/>v_ocupacion_vuelos · v_vacunas_por_vencer"]
  SEC -.->|"no puede"| NO["escribir · auditoría<br/>datos sensibles · configuración"]
  PN -->|"exportar CSV"| CSV["Archivo descargado"]
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class SEC dec
```

## Por qué las vistas son seguras para este rol

Todas las vistas de negocio se crearon con `security_invoker = true` (DT-14). La vista aplica el RLS **de quien consulta**: el Analista solo ve su tenant y lo que su rol permite. Sin esa opción, una vista correría con los permisos de su dueño y mostraría datos de todos los negocios.

## Diferencia con el usuario de base de datos `elius_consulta`

| | Rol Analista (aplicación) | Usuario `elius_consulta` (PostgreSQL) |
| --- | --- | --- |
| Quién | Una persona del negocio | Consultoría o BI del equipo Elius |
| Alcance | Su tenant | Todos los tenants, **solo agregados** |
| Qué lee | Vistas de `elius` y del plugin | Vistas del esquema `reportes` |
| Datos personales | Ve nombres de sus clientes | No ve ninguno |
