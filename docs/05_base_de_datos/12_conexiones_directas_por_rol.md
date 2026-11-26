# 12 · Conexiones directas a la base de datos, una por rol

Igual que en MySQL Workbench (una conexión por usuario: `vendedor`, `administrador`, `analista`), Elius tiene **un usuario de base de datos con login por rol**. Cada uno se conecta con su propio usuario y contraseña desde Workbench, DBeaver o psql, y tiene los permisos de su rol. Es el mismo modelo de seguridad del panel: la misma RLS y la misma matriz rol × permiso.

| Usuario de BD | Rol en la aplicación | Qué puede |
|---|---|---|
| `elius_superadmin` | Super Admin de plataforma + Administrador en todos los negocios | Leer, insertar, actualizar y borrar lo que la RLS permite; crear en `practica`; renovar el acceso de Soporte |
| `elius_administrador` | Administrador | Leer, insertar y actualizar (precios, catálogo, configuración). **No** borra ni da de baja |
| `elius_trabajador` | Operador (el que atiende) | Leer la operación, anotar novedades. **No** cambia precios ni catálogo, no borra |
| `elius_soporte` | Soporte al cliente | Ve un negocio solo con una autorización vigente (máximo 7 días); no borra |

Ninguno puede `DROP` ni `ALTER` (no es dueño de nada). `CREATE` solo en el esquema `practica`. Todo lo que hacen queda en la **Auditoría** con su rol, y el Administrador lo ve en el panel.

## Cómo se implementó

- `platform.accesos_bd` liga cada usuario de BD con una identidad de la aplicación (`auth.users`) que tiene sus membresías y su rol.
- `app.uid()` devuelve esa identidad cuando `session_user` es uno de esos usuarios; **ignora el token**, por lo que falsear `request.jwt.claims` no sirve. Las funciones y las 13 políticas que usaban `auth.uid()` ahora usan `app.uid()`.
- `app.current_tenant_id()` toma el negocio elegido con `platform.usar_negocio('slug')` (por defecto, el primero al que tiene acceso).
- Triggers `t00_sin_baja_directa` y `t00_sin_truncate_directo` en todas las tablas: bloquean `DELETE`, `TRUNCATE` y `eliminado_en` a Administrador, Trabajador y Soporte.
- Los 3 usuarios con membresía se crean en todos los negocios y en los que se creen después (trigger `t90_accesos_bd` en `platform.tenants`). No cuentan para el límite de usuarios del plan.
- Soporte usa el mecanismo de autorización que ya existía (`accesos_soporte`, máximo 7 días). Se renueva con `select platform.renovar_soporte_bd();` desde `elius_superadmin`.

## Asignar las contraseñas (una sola vez, en el Editor SQL de Supabase)

Las contraseñas no están en el repositorio. Elige una distinta para cada usuario:

```sql
alter role elius_superadmin    password 'ELIGE_UNA_CLAVE_LARGA_1';
alter role elius_administrador password 'ELIGE_UNA_CLAVE_LARGA_2';
alter role elius_trabajador    password 'ELIGE_UNA_CLAVE_LARGA_3';
alter role elius_soporte       password 'ELIGE_UNA_CLAVE_LARGA_4';
```

## Conectarse

En Supabase: **Connect → Session pooler**. El usuario se escribe `usuario.ref_del_proyecto`, por ejemplo `elius_administrador.xpvxcqvxbujblazuwomb`. Servidor y puerto: los que muestra Supabase (no el 3306 de MySQL). Base de datos: `postgres`.

## Usarlo

```sql
select * from platform.mis_negocios();          -- negocios a los que tienes acceso
select platform.usar_negocio('slug-del-negocio'); -- elegir con cuál trabajar
select * from elius.contactos;                  -- solo los de ese negocio
```

## Qué verá la profesora

| Intento | Resultado |
|---|---|
| Administrador: `delete from elius.contactos` | Error: no puede eliminar datos |
| Administrador: `update elius.contactos set eliminado_en = now()` | Error: no puede dar de baja |
| Administrador: `drop table elius.contactos` | Error: debe ser el dueño |
| Trabajador: `update elius.items_catalogo set precio = 1` | 0 filas afectadas (la RLS no se lo permite) |
| Trabajador: anotar una novedad en una reserva | Funciona y aparece en la Auditoría con rol operador |
| Cualquiera: falsear el token con `set_config('request.jwt.claims', ...)` | No cambia su identidad |
| Soporte sin autorización vigente | No ve datos |

Pruebas automáticas: `database/tests/11_conexiones_bd.sql`.

## Paneles funcionales por rol (migración 2800)

Cada rol tiene su propio panel con funciones reales, y Soporte ya **no** ve los datos del negocio:

| Rol | Qué hace en su panel |
|---|---|
| Trabajador (Operador) | Ve la agenda, **toma una reserva** (queda como responsable), marca **llegó / no llegó**, atiende conversaciones y comprobantes, y **reporta un problema** que llega a Soporte |
| Soporte al cliente | Elige un negocio que le autorizaron (máx. 7 días) y ve solo lo técnico: **errores** (los de Eli y los que reporta el Trabajador), **eventos de salida fallidos** (sin su contenido), **auditoría técnica** (rol, tabla, operación y columnas cambiadas, sin valores) y el **estado de las integraciones**. Puede **marcar un error como resuelto** (con nota) y **reintentar un evento** |
| Administrador | Todo lo del negocio, más el Centro de soporte |

Lo que Soporte **ya no puede ver**: clientes, conversaciones, órdenes, pagos, catálogo, configuración ni usuarios (antes tenía «con autorización» en todo eso). Solo accede a vistas y funciones acotadas: `v_soporte_errores`, `v_soporte_eventos`, `v_soporte_auditoria`, `soporte_resolver_error`, `soporte_reintentar_evento`, `soporte_estado_integraciones`.

Tres servicios en Easypanel, uno por rol (`VITE_PANEL=administrador | trabajador | soporte`): ver el README del panel.

## El panel del Trabajador cambia según el negocio (migración 2900)

Un trabajador de restaurante, de veterinaria y de aerolínea no hacen lo mismo, así que su panel («Mi trabajo») depende del plugin del negocio. Usa los permisos que ya tiene el rol Operador sobre cada plugin; vistas `security_invoker`, así la RLS sigue mandando.

| Negocio | Qué hace el Trabajador | Vistas y funciones |
|---|---|---|
| Restaurante | Cocina: ve las comandas por estación, las empieza y las marca listas. Ve las celebraciones del día (decoración y notas) y el menú del día | `v_trab_cocina`, `v_trab_celebraciones`, `v_trab_menu`, `trab_avanzar_comanda` |
| Veterinaria | Ve las citas con la mascota (alergias en rojo), registra peso y temperatura (inicia la atención), la finaliza y ve las vacunas por vencer para llamar | `v_trab_citas_vet`, `v_trab_vacunas`, `trab_registrar_signos`, `trab_cerrar_atencion` |
| Aerolínea | Hace el check-in con la silla (ventana de 48 h a 1 h antes), ve necesidades especiales y los vuelos con su ocupación | `v_trab_checkin`, `v_trab_necesidades`, `v_trab_vuelos`, `trab_hacer_checkin` |

Un Trabajador de un negocio no ve lo de otro plugin (probado: el de veterinaria no ve la cocina, el de aerolínea tampoco).

## Un solo panel: cada persona entra al suyo

Se entra con usuario y contraseña. El Administrador del negocio crea a la persona en *Usuarios* con el rol que le asigna (la invitación la lleva a su negocio y su rol). Al iniciar sesión el panel la lleva a su pantalla: Administrador, Trabajador (en su negocio), Analista o Soporte. Quien ya tiene un negocio real entra directo; el selector de casos es solo para las pruebas.

## Entrar al panel con los usuarios `bd.*`

Los cuatro usuarios `bd.superadmin@elius.local`, `bd.administrador@elius.local`, `bd.trabajador@elius.local` y `bd.soporte@elius.local` también sirven para el panel (un solo login: según el usuario, el panel lleva a la pantalla de su rol). La migración 3000 (`20261125000400_usuarios_bd_login_panel.sql`) deja completos los datos que Supabase Auth exige (id de instancia, fechas, identidad de correo). La contraseña del panel no va en el repositorio; se fija una sola vez en el editor SQL:

```sql
update auth.users set encrypted_password = extensions.crypt('una-clave-larga', extensions.gen_salt('bf'))
 where email = 'bd.trabajador@elius.local';
```

Es distinta de la contraseña de la conexión directa (`alter role elius_trabajador password '…'`).

## Un usuario por rol y por tipo de negocio

La migración 3100 crea, solo para los negocios de demostración, estos usuarios (sin contraseña; se fija con el `update` de arriba):

| Correo | Rol | Negocio |
|---|---|---|
| `trabajador.restaurante@elius.local` | Trabajador | Restaurante |
| `trabajador.veterinaria@elius.local` | Trabajador | Veterinaria |
| `trabajador.aerolinea@elius.local` | Trabajador | Aerolínea |
| `admin.restaurante@elius.local` | Administrador | Restaurante |
| `admin.veterinaria@elius.local` | Administrador | Veterinaria |
| `admin.aerolinea@elius.local` | Administrador | Aerolínea |

Cada uno pertenece a un solo negocio, así que al entrar el panel lo lleva directo a su pantalla, sin selector. Los negocios demo nuevos reciben estas asignaciones automáticamente (disparador `t91`).
