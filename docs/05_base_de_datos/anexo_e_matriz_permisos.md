# Matriz de permisos (rol general × módulo)

> Archivo generado por `database/modelo/documentar.py`. No editar a mano.

Niveles: **lectura** < **escritura** < **total**. *con_autorizacion* = Soporte solo cuando el Administrador abrió un acceso vigente (equivale a total). Los accesos especiales (★) los da el Administrador por usuario con `platform.otorgar_acceso_especial`.

| Plugin | Permiso | Super Admin | Soporte | Administrador | Operador | Analista | Eli |
| --- | --- | --- | --- | --- | --- | --- | --- |
| núcleo | `auditoria` | — | — | lectura | — | — | — |
| núcleo | `catalogo` | — | con_autorizacion | total | lectura | lectura | lectura |
| núcleo | `configuracion` | — | con_autorizacion | total | — | — | lectura |
| núcleo | `conocimiento` | — | con_autorizacion | total | lectura | lectura | lectura |
| núcleo | `contactos` | — | con_autorizacion | total | escritura | lectura | escritura |
| núcleo | `conversaciones` | — | con_autorizacion | total | escritura | lectura | escritura |
| núcleo | `ext` | — | con_autorizacion | total | escritura | — | — |
| núcleo | `ordenes` | — | con_autorizacion | total | escritura | lectura | escritura |
| núcleo | `pagos` | — | con_autorizacion | total | escritura | lectura | escritura |
| núcleo | `plataforma` | total | lectura | — | — | — | — |
| núcleo | `reportes` | — | con_autorizacion | total | — | lectura | escritura |
| núcleo | `reservas` | — | con_autorizacion | total | escritura | lectura | escritura |
| núcleo | `usuarios` | — | con_autorizacion | total | — | — | — |
| airline | `airline.documentos` ★ | — | — | total | — | — | — |
| airline | `airline.reservas` | — | con_autorizacion | total | escritura | lectura | escritura |
| airline | `airline.vuelos` | — | con_autorizacion | total | lectura | lectura | lectura |
| restaurant | `restaurant.cocina` | — | con_autorizacion | total | escritura | lectura | escritura |
| restaurant | `restaurant.menu` | — | con_autorizacion | total | lectura | lectura | lectura |
| restaurant | `restaurant.reversos` ★ | — | — | total | — | — | — |
| vet | `vet.historia_clinica` ★ | — | — | total | — | — | — |
| vet | `vet.pacientes` | — | con_autorizacion | total | escritura | lectura | escritura |
