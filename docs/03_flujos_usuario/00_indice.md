# Flujos de usuario por panel

Cada flujo muestra qué hace la persona paso a paso, qué decide y qué regla de negocio interviene. Los diagramas usan Mermaid y GitHub los dibuja directamente.

| Panel | Rol general | Flujo |
| --- | --- | --- |
| Plataforma | Super Admin y Soporte | [01_panel_plataforma.md](01_panel_plataforma.md) |
| Administrador | Administrador | [02_panel_administrador.md](02_panel_administrador.md) |
| Operador | Operador (según cargo) | [03_panel_operador.md](03_panel_operador.md) |
| Analista | Analista | [04_panel_analista.md](04_panel_analista.md) |
| WhatsApp con Eli | Cliente final y Eli | [05_cliente_whatsapp.md](05_cliente_whatsapp.md) |
| Extensión de Chrome | Operador y Administrador | [06_extension_chrome.md](06_extension_chrome.md) |

Todos empiezan igual: **iniciar sesión → el JWT trae el negocio predeterminado → si la persona pertenece a varios negocios, elige uno** (`platform.cambiar_tenant`).
