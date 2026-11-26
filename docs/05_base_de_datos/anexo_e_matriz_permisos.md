# Matriz de permisos (rol general × módulo)

> Archivo generado por `database/modelo/documentar.py`. No editar a mano.

Niveles: **lectura** < **escritura** < **total**. *con_autorizacion* = Soporte solo cuando el Administrador abrió un acceso vigente (equivale a total). Los accesos especiales (★) los da el Administrador por usuario con `platform.otorgar_acceso_especial`.

| Plugin | Permiso | Super Admin | Soporte | Administrador | Operador | Analista | Eli |
| --- | --- | --- | --- | --- | --- | --- | --- |
| núcleo | `auditoria` | — | — | lectura | — | — | — |
| núcleo | `catalogo` | — | — | total | lectura | lectura | lectura |
| núcleo | `configuracion` | — | — | total | — | — | lectura |
| núcleo | `conocimiento` | — | — | total | lectura | lectura | lectura |
| núcleo | `contactos` | — | — | total | escritura | lectura | escritura |
| núcleo | `conversaciones` | — | — | total | escritura | lectura | escritura |
| núcleo | `ext` | — | — | total | escritura | — | — |
| núcleo | `ordenes` | — | — | total | escritura | lectura | escritura |
| núcleo | `pagos` | — | — | total | escritura | lectura | escritura |
| núcleo | `plataforma` | total | lectura | — | — | — | — |
| núcleo | `reportes` | — | — | total | — | lectura | escritura |
| núcleo | `reservas` | — | — | total | escritura | lectura | escritura |
| núcleo | `usuarios` | — | — | total | — | — | — |
| airline | `airline.documentos` ★ | — | — | total | — | — | — |
| airline | `airline.reservas` | — | — | total | escritura | lectura | escritura |
| airline | `airline.vuelos` | — | — | total | lectura | lectura | lectura |
| restaurant | `restaurant.cocina` | — | — | total | escritura | lectura | escritura |
| restaurant | `restaurant.menu` | — | — | total | lectura | lectura | lectura |
| restaurant | `restaurant.reversos` ★ | — | — | total | — | — | — |
| vet | `vet.historia_clinica` ★ | — | — | total | — | — | — |
| vet | `vet.pacientes` | — | — | total | escritura | lectura | escritura |
