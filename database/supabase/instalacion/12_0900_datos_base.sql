-- =============================================================================
-- ELIUS · Migración 0900 · Datos base
-- Planes, los 6 roles generales, plugins, catálogo de permisos y la matriz
-- rol → permiso → nivel (sección 10.1 del levantamiento), y aeropuertos de referencia.
-- =============================================================================

insert into platform.planes (codigo, nombre, precio_mensual, moneda, max_usuarios, max_conversaciones_mes, max_tokens_mes) values
  ('free',       'Prueba',     0,   'USD',  3,    300,   1000000),
  ('starter',    'Emprende',   29,  'USD',  5,   2000,   5000000),
  ('pro',        'Crece',      79,  'USD', 15,  10000,  25000000),
  ('enterprise', 'Empresa',    249, 'USD', 100, 100000, 250000000);

-- ---------- Los 6 roles generales y fijos (DT-05) ----------------------------------
insert into platform.roles (codigo, nombre, nivel, descripcion, orden) values
  ('super_admin',   'Super Admin',   'plataforma', 'Equipo Elius: administra la plataforma, tenants, planes y plugins. No ve datos de negocio.', 1),
  ('soporte',       'Soporte',       'plataforma', 'Equipo Elius: entra a un tenant solo con autorización del Administrador, por tiempo limitado y auditado.', 2),
  ('administrador', 'Administrador', 'tenant',     'Dueño o gerente: configura su negocio sin conocimientos técnicos.', 3),
  ('operador',      'Operador',      'tenant',     'Atiende el día a día: recepción, veterinario, mesero, cajero, cocina, domiciliario, ventas.', 4),
  ('analista',      'Analista',      'tenant',     'Consulta reportes y métricas y los exporta. No modifica nada.', 5),
  ('eli',           'Eli',           'tenant',     'Identidad del agente de IA: crea contactos, conversaciones, reservas y órdenes.', 6);

-- ---------- Plugins (microkernel, DT-09) --------------------------------------------
insert into platform.plugins (codigo, nombre, esquema, verticales, manifiesto) values
  ('vet', 'Veterinaria', 'plugin_vet', '{veterinaria}',
   '{"modulos": ["vet.pacientes"], "accesos_especiales": ["vet.historia_clinica"], "cargos": ["Veterinario", "Recepción", "Auxiliar"]}'),
  ('restaurant', 'Restaurante', 'plugin_restaurant', '{restaurante}',
   '{"modulos": ["restaurant.menu", "restaurant.cocina"], "accesos_especiales": ["restaurant.reversos"], "cargos": ["Mesero", "Cajero", "Cocina", "Domiciliario"]}'),
  ('airline', 'Aerolínea', 'plugin_airline', '{aerolinea}',
   '{"modulos": ["airline.vuelos", "airline.reservas"], "accesos_especiales": ["airline.documentos"], "cargos": ["Agente de counter", "Ventas", "Operaciones"]}');

-- ---------- Catálogo de permisos (módulos) -------------------------------------------
insert into platform.permisos (plugin_id, codigo, modulo, descripcion, es_acceso_especial, protege_dato_sensible)
select (select id from platform.plugins where codigo = x.plugin), x.codigo, x.modulo, x.descr, x.especial, x.sensible
from (values
  (null, 'plataforma',     'plataforma',    'Tenants, planes y plugins disponibles', false, false),
  (null, 'configuracion',  'configuracion', 'Configuración del negocio, de Eli, canales, parámetros y pasarelas', false, false),
  (null, 'usuarios',       'usuarios',      'Usuarios, invitaciones, accesos especiales y de soporte', false, false),
  (null, 'contactos',      'contactos',     'Clientes finales, direcciones y consentimientos', false, false),
  (null, 'conversaciones', 'conversaciones','Conversaciones con Eli, mensajes y escalamientos', false, false),
  (null, 'catalogo',       'catalogo',      'Productos, servicios, paquetes, adicionales y fotos', false, false),
  (null, 'reservas',       'reservas',      'Recursos, horarios, reservas y asignaciones', false, false),
  (null, 'ordenes',        'ordenes',       'Órdenes, líneas y entregas', false, false),
  (null, 'pagos',          'pagos',         'Pagos, comprobantes y recaudos', false, false),
  (null, 'conocimiento',   'conocimiento',  'Base de conocimiento de Eli', false, false),
  (null, 'reportes',       'reportes',      'Métricas, embudo y consumo de IA', false, false),
  (null, 'auditoria',      'auditoria',     'Bitácora de cambios', false, false),
  (null, 'ext',            'ext',           'Extensión de Chrome', false, false),
  ('vet',        'vet.pacientes',        'veterinaria', 'Mascotas, propietarios, atenciones y vacunas', false, false),
  ('vet',        'vet.historia_clinica', 'veterinaria', 'Historia clínica (acceso especial para veterinarios)', true, true),
  ('restaurant', 'restaurant.menu',      'restaurante', 'Menú, alérgenos, modificadores y menú del día', false, false),
  ('restaurant', 'restaurant.cocina',    'restaurante', 'Comandas, estaciones, opciones y celebraciones', false, false),
  ('restaurant', 'restaurant.reversos',  'restaurante', 'Reversar pedidos pagados (acceso especial)', true, false),
  ('airline',    'airline.vuelos',       'aerolinea',   'Aeronaves, rutas, vuelos y tarifas', false, false),
  ('airline',    'airline.reservas',     'aerolinea',   'Pasajeros, tramos, tiquetes y equipaje', false, false),
  ('airline',    'airline.documentos',   'aerolinea',   'Documentos y necesidades de salud de pasajeros (acceso especial)', true, true)
) as x(plugin, codigo, modulo, descr, especial, sensible);

-- ---------- Matriz rol → permiso → nivel (sección 10.1) -------------------------------
insert into platform.rol_permisos (rol_id, permiso_id, nivel, origen)
select r.id, p.id, x.nivel, case when x.permiso like '%.%' then split_part(x.permiso, '.', 1) else 'nucleo' end
from (values
  -- Super Admin: solo la plataforma
  ('super_admin', 'plataforma', 'total'),
  -- Soporte: lee la plataforma y entra al negocio solo con autorización
  ('soporte', 'plataforma', 'lectura'),
  ('soporte', 'configuracion', 'con_autorizacion'), ('soporte', 'usuarios', 'con_autorizacion'),
  ('soporte', 'contactos', 'con_autorizacion'), ('soporte', 'conversaciones', 'con_autorizacion'),
  ('soporte', 'catalogo', 'con_autorizacion'), ('soporte', 'reservas', 'con_autorizacion'),
  ('soporte', 'ordenes', 'con_autorizacion'), ('soporte', 'pagos', 'con_autorizacion'),
  ('soporte', 'conocimiento', 'con_autorizacion'), ('soporte', 'reportes', 'con_autorizacion'),
  ('soporte', 'ext', 'con_autorizacion'), ('soporte', 'vet.pacientes', 'con_autorizacion'),
  ('soporte', 'restaurant.menu', 'con_autorizacion'), ('soporte', 'restaurant.cocina', 'con_autorizacion'),
  ('soporte', 'airline.vuelos', 'con_autorizacion'), ('soporte', 'airline.reservas', 'con_autorizacion'),
  -- Administrador: todo su negocio, incluidos los datos sensibles
  ('administrador', 'configuracion', 'total'), ('administrador', 'usuarios', 'total'),
  ('administrador', 'contactos', 'total'), ('administrador', 'conversaciones', 'total'),
  ('administrador', 'catalogo', 'total'), ('administrador', 'reservas', 'total'),
  ('administrador', 'ordenes', 'total'), ('administrador', 'pagos', 'total'),
  ('administrador', 'conocimiento', 'total'), ('administrador', 'reportes', 'total'),
  ('administrador', 'auditoria', 'lectura'), ('administrador', 'ext', 'total'),
  ('administrador', 'vet.pacientes', 'total'), ('administrador', 'vet.historia_clinica', 'total'),
  ('administrador', 'restaurant.menu', 'total'), ('administrador', 'restaurant.cocina', 'total'),
  ('administrador', 'restaurant.reversos', 'total'),
  ('administrador', 'airline.vuelos', 'total'), ('administrador', 'airline.reservas', 'total'),
  ('administrador', 'airline.documentos', 'total'),
  -- Operador: el día a día; lo sensible solo con acceso especial
  ('operador', 'contactos', 'escritura'), ('operador', 'conversaciones', 'escritura'),
  ('operador', 'reservas', 'escritura'), ('operador', 'ordenes', 'escritura'), ('operador', 'pagos', 'escritura'),
  ('operador', 'catalogo', 'lectura'), ('operador', 'conocimiento', 'lectura'), ('operador', 'ext', 'escritura'),
  ('operador', 'vet.pacientes', 'escritura'),
  ('operador', 'restaurant.menu', 'lectura'), ('operador', 'restaurant.cocina', 'escritura'),
  ('operador', 'airline.vuelos', 'lectura'), ('operador', 'airline.reservas', 'escritura'),
  -- Analista: solo lectura y reportes
  ('analista', 'contactos', 'lectura'), ('analista', 'conversaciones', 'lectura'), ('analista', 'catalogo', 'lectura'),
  ('analista', 'reservas', 'lectura'), ('analista', 'ordenes', 'lectura'), ('analista', 'pagos', 'lectura'),
  ('analista', 'conocimiento', 'lectura'), ('analista', 'reportes', 'lectura'),
  ('analista', 'vet.pacientes', 'lectura'), ('analista', 'restaurant.menu', 'lectura'),
  ('analista', 'restaurant.cocina', 'lectura'), ('analista', 'airline.vuelos', 'lectura'),
  ('analista', 'airline.reservas', 'lectura'),
  -- Eli: atiende clientes; no ve usuarios, auditoría ni datos sensibles
  ('eli', 'contactos', 'escritura'), ('eli', 'conversaciones', 'escritura'), ('eli', 'reservas', 'escritura'),
  ('eli', 'ordenes', 'escritura'), ('eli', 'pagos', 'escritura'), ('eli', 'catalogo', 'lectura'),
  ('eli', 'conocimiento', 'lectura'), ('eli', 'configuracion', 'lectura'), ('eli', 'reportes', 'escritura'),
  ('eli', 'vet.pacientes', 'escritura'), ('eli', 'restaurant.menu', 'lectura'), ('eli', 'restaurant.cocina', 'escritura'),
  ('eli', 'airline.vuelos', 'lectura'), ('eli', 'airline.reservas', 'escritura')
) as x(rol, permiso, nivel)
join platform.roles r on r.codigo = x.rol
join platform.permisos p on p.codigo = x.permiso;

-- ---------- Aeropuertos de referencia (RN-A01, códigos IATA) --------------------------
insert into plugin_airline.aeropuertos (codigo_iata, nombre, ciudad, pais, zona_horaria) values
  ('BOG', 'El Dorado', 'Bogotá', 'CO', 'America/Bogota'),
  ('MDE', 'José María Córdova', 'Rionegro', 'CO', 'America/Bogota'),
  ('CLO', 'Alfonso Bonilla Aragón', 'Cali', 'CO', 'America/Bogota'),
  ('CTG', 'Rafael Núñez', 'Cartagena', 'CO', 'America/Bogota'),
  ('BAQ', 'Ernesto Cortissoz', 'Barranquilla', 'CO', 'America/Bogota'),
  ('SMR', 'Simón Bolívar', 'Santa Marta', 'CO', 'America/Bogota'),
  ('BGA', 'Palonegro', 'Bucaramanga', 'CO', 'America/Bogota'),
  ('PEI', 'Matecaña', 'Pereira', 'CO', 'America/Bogota'),
  ('ADZ', 'Gustavo Rojas Pinilla', 'San Andrés', 'CO', 'America/Bogota'),
  ('MIA', 'Miami International', 'Miami', 'US', 'America/New_York'),
  ('MAD', 'Adolfo Suárez Madrid-Barajas', 'Madrid', 'ES', 'Europe/Madrid'),
  ('MEX', 'Benito Juárez', 'Ciudad de México', 'MX', 'America/Mexico_City');
