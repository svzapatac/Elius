# Flujo de usuario · Soporte al cliente

Soporte trabaja solo con vistas y procedimientos: el panel no le da acceso directo a las tablas. Ve los negocios que el Administrador le autorizó.

## Atender un ticket

```mermaid
flowchart TD
  A([Centro de soporte → Tickets pendientes]) --> B[Abre el ticket: categoría, prioridad, asunto y cronología]
  B --> C[Botón Tomar ticket<br/>elius.soporte_tomar_ticket → en proceso]
  C --> D{¿Necesita corregir algo?}
  D -- Un cliente --> E[Pestaña Clientes: elius.soporte_corregir_cliente<br/>deja nota en el ticket y auditoría]
  D -- Un usuario --> F[Pestaña Usuarios: crear, restablecer clave, cambiar rol o estado]
  D -- Solo consultar --> G[Pestaña Manual de soporte: pasos por categoría]
  E --> H[Escribe la solución]
  F --> H
  G --> H
  H --> I[elius.soporte_resolver_ticket → resuelto<br/>sin solución no se puede resolver]
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class D dec
  class A,I ok
```

## Ver lo técnico (errores, eventos y auditoría)

```mermaid
flowchart TD
  A([Centro de soporte → Técnico]) --> B[Estado: errores abiertos, eventos fallidos, avisos al celular]
  B --> C{¿Un evento falló?}
  C -- Sí --> D[Reintentar: elius.soporte_reintentar_evento]
  C -- No --> E[Revisar la auditoría de lo que se hizo en el negocio]
  D --> E
  classDef default fill:#dbeafe,stroke:#3b82f6,color:#1e293b
  classDef dec fill:#fef9c3,stroke:#ca8a04,color:#1e293b
  classDef ok fill:#dcfce7,stroke:#16a34a,color:#1e293b
  class C dec
  class A,E ok
```
