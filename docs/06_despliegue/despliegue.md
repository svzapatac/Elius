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
3. Negocio demo y profesor: `EXTRA_negocio_demo.sql` crea el negocio y deja al profesor como Administrador de ese negocio.

## 4. Revisión del profesor

El profesor entra al panel con su usuario (rol Administrador del negocio demo), abre **Consola SQL** y puede:

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

Al elegir uno, `platform.cargar_caso_demo(vertical)` crea el negocio de prueba (la persona queda como Administrador), con un catálogo de **5 ítems con imagen** y 3 conversaciones. Luego el panel llama a `elius.siguiente_mensaje_demo()` cada pocos segundos: llegan **20 mensajes** por caso (10 de clientes y 10 respuestas de Eli) y se ven en **Conversaciones** en vivo. La barra superior permite pausar o reiniciar la prueba y cambiar de caso. Si la persona toma una conversación, Eli deja de responder en ella (RN-C19).

Los guiones están en `database/modelo/casos_demo.py`; las ilustraciones se generan con `database/modelo/ilustraciones_demo.py`. Pruebas: grupo 18 de `database/tests`.
