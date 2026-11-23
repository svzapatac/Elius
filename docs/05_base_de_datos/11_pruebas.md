# Pruebas

Las pruebas crean una base PostgreSQL 16 limpia, simulan lo mínimo de Supabase (roles `anon`, `authenticated`, `service_role` y las funciones `auth.uid()` y `auth.jwt()`), aplican las 10 migraciones en orden y ejecutan **94 casos** con usuarios reales de cada rol. Cada caso imprime `OK` o detiene todo con `FALLA`.

```bash
bash database/tests/ejecutar_pruebas.sh
```

Resultado de la última ejecución: **94 OK, 0 fallas** ([resultado_pruebas.txt](../../database/tests/resultado_pruebas.txt)).

## Escenario

Tres negocios (Potrillos Terraza, Clínica Patitas y Vuela Colombia), creados con `crear_tenant` por sus dueños. Un Operador entra por invitación; además hay un Cajero, un Analista, la identidad de Eli, un Veterinario, el Super Admin y Soporte.

## Qué verifica cada grupo

| # | Grupo | Ejemplos de lo que se comprueba |
| --- | --- | --- |
| 1 | Crear negocios | Se instala el plugin de la vertical, se crea Eli y los parámetros base; la invitación funciona |
| 2 | Hook del JWT | El token lleva `tenant_id` y el rol general |
| 3 | Aislamiento | Un negocio no ve ni escribe en otro; `X-Tenant-ID` ajeno se ignora; una FK no cruza negocios |
| 4 | Roles | El Analista no escribe ni ve la auditoría; el Operador no borra ni apaga a Eli; la auditoría guarda el rol |
| 5 | Plugins | Un restaurante no puede usar tablas de veterinaria |
| 6 | Acceso especial | La historia clínica exige el acceso especial; no se edita después de 24 h; una mascota fallecida no recibe citas |
| 7 | Conversaciones | Bloqueo único, escalamiento por turnos, Eli calla con humano o apagada |
| 8 | Órdenes | Consecutivo, precio del catálogo, recargos, totales con impuesto, agotados, máximo de opciones |
| 9 | Comprobantes | Alertas de monto y de repetido, pago parcial con resto contra entrega, sin doble cobro |
| 10 | Factus Pay | Estrategia, recaudo, clave inválida, monto distinto, pago aplicado, webhook repetido, webhook por `service_role` |
| 11 | Reservas | Horario, capacidad, cruces, transiciones, aviso de grupo grande |
| 12 | Soporte y Super Admin | Soporte solo con autorización y auditado; el Super Admin no ve datos de negocio |
| 13 | Plataforma | Último Administrador y límite de usuarios del plan |
| 14 | Aerolínea | Capacidad, cupos, infantes, sillas, check-in, aviso de vuelo cancelado |
| 15 | Extensión de Chrome | Solo quien captura ve lo capturado |
| 16 | Vistas y usuarios de BD | Vistas respetan RLS; `elius_consulta` solo agregados; `elius_app` sin tenant no ve nada; ningún usuario es superusuario |

> Las pruebas verifican la base de datos. Las Edge Functions de Factus (`integraciones/edge-functions/`) son una implementación de referencia que todavía no se ha ejecutado contra el sandbox de Factus.
