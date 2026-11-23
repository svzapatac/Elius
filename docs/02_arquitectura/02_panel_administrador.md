# Arquitectura · Panel del Administrador

**Quién lo usa:** el dueño o gerente de la pyme. Configura su negocio **sin conocimientos técnicos**: usuarios, Eli, catálogo, horarios, canales, plugin y cobros.

```mermaid
flowchart LR
  AD["Administrador"] --> PA["Panel del Administrador"]
  PA -->|"login"| AUTH["Supabase Auth<br/>JWT con tenant_id"]
  PA -->|"JWT"| API["API / RPC"]
  PA <-->|"Realtime"| RT["pendientes, comprobantes,<br/>pedidos en vivo"]
  API --> SEC{"RLS<br/>rol administrador = total"}
  SEC --> U["Usuarios<br/>platform.membresias · invitaciones<br/>accesos_especiales · accesos_soporte"]
  SEC --> C["Configuración<br/>elius.agentes · canales · parametros_negocio<br/>horarios_atencion · pasarelas_pago"]
  SEC --> K["Catálogo<br/>categorias · items · adicionales · medios"]
  SEC --> O["Operación<br/>reservas · ordenes · pagos · comprobantes"]
  SEC --> PL["Plugin de su vertical<br/>plugin_vet / restaurant / airline"]
  SEC --> AU["audit.registros_auditoria (lectura)"]
  PA -->|"Conectar WhatsApp<br/>Embedded Signup de Meta"| EF["Edge Function"]
  EF -->|"token"| VA["Supabase Vault"]
  PA -->|"Activar Factus Pay"| EF2["Edge Function"]
  EF2 -->|"credenciales y clave del webhook"| VA
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class SEC dec
```

## Procedimientos que llama

| Botón del panel | Procedimiento | Regla |
| --- | --- | --- |
| Invitar usuario | `platform.invitar_usuario(email, rol)` | RN-P12 |
| Activar historia clínica a un veterinario | `platform.otorgar_acceso_especial(membresía, 'vet.historia_clinica')` | RN-V03 |
| Autorizar a Soporte | `platform.autorizar_soporte(usuario, motivo, horas)` | RN-P16 |
| Apagar o encender a Eli | `elius.encender_eli(true/false)` | RN-C20 |
| Confirmar el menú del día | `plugin_restaurant.confirmar_menu_dia(menu)` | RN-R11 |
| Cambiar de negocio | `platform.cambiar_tenant(tenant)` y refrescar sesión | DT-04 |

## Protecciones que la base aplica aunque el panel falle

- No puede quitarse a sí mismo si es el último Administrador (RN-P04, trigger `t11_ultimo_admin`).
- No puede pasar el límite de usuarios de su plan (RN-P10, trigger `t12_limite_usuarios`).
- No puede escribir montos de órdenes a mano (RN-C11, trigger `t43_proteger_totales`).
