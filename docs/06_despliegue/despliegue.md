# Despliegue

## 1. Base de datos en Supabase

Ver [`database/supabase/instalacion/README.md`](../../database/supabase/instalacion/README.md). Estado del proyecto `Elius` (us-east-2): 14 archivos aplicados y verificados (80 tablas, 80 con RLS, 191 relaciones), hook del token activo y esquemas `platform`, `elius`, `ext` y los tres plugins expuestos en la Data API.

## 2. Panel en Easypanel

Repositorio: [`svzapatac/elius-panel`](https://github.com/svzapatac/elius-panel), rama `elius-base-nueva`.

| Campo en Easypanel | Valor |
| --- | --- |
| Fuente | GitHub · `svzapatac/elius-panel` · rama `elius-base-nueva` |
| Build | Dockerfile (en la raíz) |
| Build argument `VITE_SUPABASE_URL` | `https://xpvxcqvxbujblazuwomb.supabase.co` |
| Build argument `VITE_SUPABASE_KEY` | la clave *publishable* del proyecto (Settings → API Keys). **Nunca** la `service_role` |
| Build argument `VITE_NEGOCIO_NOMBRE` | `Elius` |
| Puerto | 80 |

Las claves públicas de Supabase van dentro del navegador por diseño: lo que protege los datos es RLS.

## 3. Usuarios

1. En Supabase → Authentication → Users → *Add user* se crea cada persona (con contraseña propia).
2. Super Admin: `database/supabase/instalacion/EXTRA_primer_super_admin.sql`.
3. Negocio del dueño (opcional): `EXTRA_negocio_demo.sql`. La profesora no entra a ese negocio: al iniciar sesión elige un caso de prueba y el panel le crea el suyo.

## 4. Revisión del profesor

La profesora entra al panel con su usuario, elige un caso de prueba (queda como Administrador de ese negocio de prueba), abre **Consola SQL** y puede:

| Puede | No puede |
| --- | --- |
| `SELECT` de todo lo del negocio, del catálogo (tablas, columnas, triggers, vistas, funciones) y de las políticas RLS | `DROP`, `DELETE`, `TRUNCATE`, `ALTER`, `GRANT`, `COPY`, `SET` |
| `INSERT` y `UPDATE` en las tablas del negocio (con RLS: solo su negocio) | Escribir en `platform` ni en `audit` |
| `CREATE` tablas, vistas, índices y funciones **solo en el esquema `practica`** | Entrar directo a la base de datos |

Implementación: función `elius.consola_sql` (migración 1100). Corre con el rol `elius_revisor`, que no es superusuario ni salta RLS, tiene un tiempo máximo de 8 s por sentencia y una sola sentencia por ejecución. Cada ejecución queda en `audit.registros_auditoria`. Pruebas: grupo 17 de `database/tests`.

Limitación conocida: es una barrera por lista de palabras bloqueadas más los privilegios del rol. Está pensada para revisión académica con una persona de confianza, no para dar SQL libre a usuarios anónimos.

## Casos de prueba para la revisión (restaurante, veterinaria, aerolínea)

Al iniciar sesión, el panel muestra una pantalla para **elegir el caso**, cada uno con su logo y el nombre de la prueba:

| Caso | Negocio | Prueba |
| --- | --- | --- |
| 1 | Restaurante Sabor Criollo | Reservas y pedidos a domicilio por WhatsApp |
| 2 | Clínica Veterinaria Huellitas | Citas, vacunas y urgencias de mascotas |
| 3 | Aerolínea Cóndor Andino | Cotización y reserva de vuelos |

Al elegir uno, `platform.cargar_caso_demo(vertical)` crea el negocio de prueba (la persona queda como Administrador), con un catálogo de **5 ítems con imagen** y **20 clientes**, cada uno con su conversación. Luego el panel llama a `elius.siguiente_mensaje_demo()` cada pocos segundos y los chats se llenan en **Conversaciones**, en vivo, con Eli respondiendo y enviando las fotos del catálogo.

**Conversaciones hasta el pago.** En cada caso, algunos clientes llevan el pedido completo: piden, confirman y **envían su comprobante de pago** (imagen real de Nequi/DaviPlata). El comprobante aparece en **Comprobantes** con su foto, el monto leído contra el monto de la orden y las alertas (RN-C16). La barra superior avisa «Esperando que revises N comprobantes». La prueba espera la decisión: al pulsar **Aceptar pago**, la orden queda confirmada y Eli continúa la conversación (confirma el pedido y se despide); al **Rechazar**, Eli le avisa al cliente y le pide otro comprobante. En el restaurante hay dos pagos: uno correcto y otro con comprobante equivocado (monto distinto y repetido), para ver las alertas.

**Todas las secciones se ven con datos.** Mientras corre la prueba: *Conversaciones* (los 20 chats), *Pendientes* (casos que Eli pasa a una persona, p. ej. un reclamo o una alergia), *Comprobantes* y *Pedidos* (el pago aprobado confirma la orden), *Agenda de hoy* (reservas que Eli deja con su recurso), *Catálogo* con imágenes y *Métricas* (ventas, ítems más vendidos, % resuelto por Eli y consumo de IA de cada respuesta).

**Más allá del chat.** *Agenda* es un calendario mensual con el detalle de cada día (vista `elius.v_agenda_calendario`). *Modelo de datos* muestra los diagramas E-R, los flujos y el diccionario con zoom y desplazamiento. *Vistas* deja al Administrador crear sus propias vistas en el esquema `practica`. El selector «Ver el panel como» cambia el rol de quien prueba entre Administrador, Operador y Analista (`elius.cambiar_rol_demo`); la base sigue aplicando los permisos de cada rol. Los seis roles del sistema están en la sección Usuarios.

La barra superior permite pausar o reiniciar la prueba y cambiar de caso. Si la persona toma una conversación, Eli deja de responder en ella (RN-C19). Los negocios de prueba (slug `demo-…`) son la única excepción a RN-C12 al reiniciar: se pueden borrar sus pagos aprobados.

Los guiones están en `database/modelo/casos_demo.py`; las ilustraciones se generan con `database/modelo/ilustraciones_demo.py`. Pruebas: grupo 18 de `database/tests`.
