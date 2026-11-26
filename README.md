# Elius

Plataforma SaaS multi-tenant que centraliza los datos de **Eli**, el agente de inteligencia artificial. PostgreSQL sobre Supabase, modelo **pool** (`tenant_id` + RLS). Verticales piloto: veterinaria, restaurante y aerolínea, implementadas como **plugins** (microkernel).

## Contenido del repositorio

| Carpeta | Qué contiene |
| --- | --- |
| [`docs/01_levantamiento`](docs/01_levantamiento/levantamiento_informacion.md) | Documento de levantamiento de información: contexto, requisitos, 73 reglas de negocio, 18 decisiones técnicas con fuentes |
| [`docs/02_arquitectura`](docs/02_arquitectura/00_arquitectura_general.md) | Diagramas de flujo de la arquitectura: general y por panel (plataforma, administrador, operador, analista), canal WhatsApp/Eli y extensión de Chrome |
| [`docs/03_flujos_usuario`](docs/03_flujos_usuario/00_indice.md) | Diagramas de flujo de usuario por panel |
| [`docs/04_pagos`](docs/04_pagos/verificacion_de_pagos.md) | Verificación de pagos: **Factus Pay** (llave Bre-B) con el comprobante tradicional como alternativa |
| [`docs/05_base_de_datos`](docs/05_base_de_datos/00_indice.md) | Sustentación de la base de datos: modelo E/R, diccionario, relaciones, restricciones, RLS, roles y permisos, triggers, vistas, procedimientos, pruebas |
| `database/modelo` | Fuente única del modelo (`modelo.py`) y generadores de diagramas, DBML, SQL y documentación |
| `database/supabase/migrations` | 10 migraciones SQL listas para Supabase |
| `database/tests` | 369 pruebas automáticas sobre PostgreSQL 16 |
| `integraciones/edge-functions` | Edge Functions de referencia para Factus Pay |

## Base de datos de un vistazo

- **87 tablas**: 61 del modelo general (`platform`, `audit`, `elius`, `ext`) y 26 de plugins (`plugin_vet`, `plugin_restaurant`, `plugin_airline`), separados en esquemas distintos.
- **201 relaciones**, 24 tablas de transición con datos propios; sin relaciones 1 a 1 ni muchos a muchos (validado por script).
- **6 roles generales fijos** (Super Admin, Soporte, Administrador, Operador, Analista, Eli); los plugins solo personalizan con accesos especiales y cargos.
- **3 usuarios de conexión** sin superusuario: `elius_admin`, `elius_app`, `elius_consulta`.
- RLS en las 86 tablas propias (290 políticas; las que no tienen políticas, como `tickets` y las de avisos, solo se leen por vistas y funciones de confianza), 364 triggers, 39 vistas y 143 funciones.

**Modelo E/R completo:** [`docs/05_base_de_datos/modelo_er.md`](docs/05_base_de_datos/modelo_er.md) (diagrama de las 87 tablas y uno por módulo).

Para sustentar, empezar por [`docs/05_base_de_datos/00_indice.md`](docs/05_base_de_datos/00_indice.md).

## Cómo ejecutar

```bash
# Pruebas (PostgreSQL 16 local; aplica las migraciones y corre 369 casos)
bash database/tests/ejecutar_pruebas.sh

# Regenerar diagramas, DBML y SQL de tablas desde el modelo
cd database/modelo && python3 generar.py
```

Para Supabase: `supabase db push`, activar el hook *Custom Access Token* (`public.custom_access_token_hook`) y exponer los esquemas del modelo en *Settings → API*. No se versionan secretos; las claves de Factus y contraseñas de los usuarios de conexión se configuran fuera del repositorio (Vault / variables de entorno).

## Limitaciones conocidas

- Las Edge Functions de Factus Pay son de referencia y no se han ejecutado contra el sandbox de Factus.
- El control fino de `restaurant.reversos` y `airline.documentos` está pendiente.
