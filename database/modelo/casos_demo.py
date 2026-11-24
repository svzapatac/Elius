# Datos de los 3 casos de prueba (restaurante, veterinaria, aerolínea). Los usa generar_casos_demo.py.
CASOS = {
 'restaurante': {
  'negocio': 'Restaurante Sabor Criollo', 'categoria': ['Platos fuertes', 'Bebidas', 'Postres', 'Celebraciones y eventos'],
  'items': [  # categoría(idx), tipo, sku, nombre, descripción, precio, iva, duración
   (0,'producto','RES-01','Bandeja paisa','Frijoles, arroz, carne molida, chicharrón, chorizo, huevo, plátano maduro y arepa.',38000,8,None),
   (0,'producto','RES-02','Hamburguesa de la casa','Carne de res 180 g, queso, tocineta y papas a la francesa.',28000,8,None),
   (0,'producto','RES-03','Arepa rellena de pollo','Arepa de maíz rellena de pollo desmechado con guacamole.',16000,8,None),
   (1,'producto','RES-04','Limonada de coco','Limonada cremada con coco, servida bien fría.',12000,8,None),
   (2,'producto','RES-05','Tres leches','Bizcocho bañado en tres leches con crema y canela.',14000,8,None),
   (3,'servicio','RES-06','Pack cumpleaños','Decoración de mesa con globos y letrero de feliz cumpleaños para tu celebración en el restaurante.',50000,8,120),
   (3,'servicio','RES-07','Cena de aniversario','Mesa para dos con decoración romántica, velas, flores y postre de cortesía.',80000,8,120),
   (3,'servicio','RES-08','Pack bautizo','Mesa decorada en tonos suaves y torta de bautizo para tu celebración.',90000,8,180),
   (3,'servicio','RES-09','Pack grado','Arco de globos, torta personalizada y mesa decorada para celebrar tu grado.',65000,8,180),
   (3,'servicio','RES-10','Aniversario premium','Cena de aniversario para dos con decoración completa, flores, velas y botella de vino.',160000,8,180),
   (3,'servicio','RES-11','Pack adicional de globos','Arco de globos y mesa de dulces para sumar a cualquier celebración.',69000,8,60),
   (3,'servicio','RES-12','Celebración sin decoración','Reserva de mesa para tu celebración, sin decoración (la traes tú).',30000,8,120)],
  'imagenes': {
    'RES-01': 'https://commons.wikimedia.org/wiki/Special:FilePath/Bandeja%20Paisa%20%28Bogot%C3%A1%29.jpg?width=640',
    'RES-02': 'https://commons.wikimedia.org/wiki/Special:FilePath/Cheeseburger%20and%20fries.jpg?width=640',
    'RES-03': 'https://commons.wikimedia.org/wiki/Special:FilePath/Colombian%20Food%2C%20Arepas.jpg?width=640',
    'RES-04': 'https://commons.wikimedia.org/wiki/Special:FilePath/Limonada%20de%20coco.jpg?width=640',
    'RES-05': 'https://commons.wikimedia.org/wiki/Special:FilePath/Tres%20leches%20cake.jpg?width=640',
    'RES-06': 'https://commons.wikimedia.org/wiki/Special:FilePath/Birthday%20decoration.jpg?width=640',
    'RES-07': 'https://commons.wikimedia.org/wiki/Special:FilePath/DZ6%202628%20Cozy%20candlelit%20dinner%20for%20two%20elegant%20Thai%20restaurant%20setting%20with%20twinkling%20lights%20and%20a%20delicate%20orchid%20centerpiece.jpg?width=640',
    'RES-08': 'https://commons.wikimedia.org/wiki/Special:FilePath/Christening%20Cake%20%289696366409%29.jpg?width=640',
    'RES-09': '/demo/restaurante-9.jpg',
    'RES-10': 'https://commons.wikimedia.org/wiki/Special:FilePath/DZ6%202648%20A%20cozy%20candlelit%20dinner%20setup%20a%20delicate%20orchid%20soft%20lamp%20glow%20and%20an%20empty%20wine%20glass%20waiting%20for%20the%20evening%20to%20begin.jpg?width=640',
    'RES-11': 'https://commons.wikimedia.org/wiki/Special:FilePath/Organic%20Arch%202016%20balloon%20decorations.jpg?width=640',
    'RES-12': 'https://commons.wikimedia.org/wiki/Special:FilePath/Table%20set%20for%20dinner%20in%20a%20restaurant.jpg?width=640'},
  },
 'veterinaria': {
  'negocio': 'Clínica Veterinaria Huellitas', 'categoria': ['Consultas y cirugía', 'Prevención', 'Estética'],
  'items': [
   (0,'servicio','VET-01','Consulta general','Examen clínico completo con orientación de tratamiento.',60000,0,30),
   (1,'servicio','VET-02','Vacuna múltiple','Esquema anual para perros y gatos, con carné actualizado.',75000,0,20),
   (2,'servicio','VET-03','Baño y peluquería','Baño medicado, corte de pelo y de uñas, limpieza de oídos.',55000,19,90),
   (1,'servicio','VET-04','Desparasitación','Desparasitante interno y externo según el peso de la mascota.',35000,0,15),
   (0,'servicio','VET-05','Esterilización canina','Cirugía con anestesia, exámenes previos y control posoperatorio.',320000,0,120)],
  'imagenes': {
    'VET-01': 'https://commons.wikimedia.org/wiki/Special:FilePath/Close-up%20of%20a%20veterinarian%20examining%20a%20maltese%20dog%20with%20a%20stethoscope.%20%2851687314898%29.jpg?width=640',
    'VET-02': 'https://commons.wikimedia.org/wiki/Special:FilePath/USMC-04462.jpg?width=640',
    'VET-03': 'https://commons.wikimedia.org/wiki/Special:FilePath/Dog%20Groomer%20Norwich.jpg?width=640',
    'VET-04': 'https://commons.wikimedia.org/wiki/Special:FilePath/U.S.%20Army%20Capt.%20Brooke%20Henderson%2C%20left%2C%20a%20veterinarian%20with%20the%20993rd%20Medical%20Detachment%2C%20U.S.%20Army%20Reserve%2C%20examines%20a%20Maltese%20mix%20puppy%20while%20Sgt.%20Andrew%20King%2C%20with%20the%20949th%20Medical%20Detachment%2C%20holds%20the%20dog%20120418-F-ZH346-001.jpg?width=640',
    'VET-05': 'https://commons.wikimedia.org/wiki/Special:FilePath/Surgery%20on%20a%20dog%2C%20University%20of%20Agricultural%20Sciences%20and%20Veterinary%20Medicine%2C%20Cluj-Napoka.jpg?width=640'},
  },
 'aerolinea': {
  'negocio': 'Aerolínea Cóndor Andino', 'categoria': ['Tarifas', 'Servicios adicionales'],
  'items': [
   (0,'tarifa','AER-01','Bogotá – Medellín (Light)','Solo equipaje de mano. Sin cambios ni devolución.',189000,19,None),
   (0,'tarifa','AER-02','Bogotá – Cartagena (Flex)','Maleta de 23 kg incluida y un cambio de fecha sin costo.',275000,19,None),
   (0,'tarifa','AER-03','Bogotá – San Andrés (Promo)','Tarifa promocional con equipaje de mano, cupos limitados.',415000,19,None),
   (1,'adicional','AER-04','Maleta de bodega 23 kg','Equipaje adicional para tu vuelo.',85000,19,None),
   (1,'adicional','AER-05','Selección de asiento','Elige ventana o pasillo antes del check-in.',25000,19,None)],
  'imagenes': {
    'AER-01': 'https://commons.wikimedia.org/wiki/Special:FilePath/Valley%20of%20Medell%C3%ADn-%20skyline.jpg?width=640',
    'AER-02': 'https://commons.wikimedia.org/wiki/Special:FilePath/The%20Clock%20Tower%2C%20Las%20Murallas%2C%20the%20walls%20of%20Cartagena%2C%20Colombia%20%2823955879634%29.jpg?width=640',
    'AER-03': 'https://commons.wikimedia.org/wiki/Special:FilePath/San%20andres%20Island%20-%20Colombia.jpg?width=640',
    'AER-04': 'https://commons.wikimedia.org/wiki/Special:FilePath/Bag%20drop%20self%20service%20Luggage%20check-in%20Baggage%20registration%20Conveyor%20belt%20%28selvbetjent%20bagasjeinnlevering%20innsjekking%20automat%20rulleb%C3%A5nd%29%20Avinor%20SAS%20Norwegian%20Wideroe%20Bergen%20Airport%20Flesland%2C%20Norway%202019-11-29%20DSC01301.jpg?width=640',
    'AER-05': 'https://commons.wikimedia.org/wiki/Special:FilePath/Window%20seat.jpg?width=640'},
  },
}


# Cada cliente escribe una vez y Eli responde (con la foto del catálogo cuando ofrece un ítem).
# (nombre, apellido, mensaje del cliente, respuesta de Eli, número del ítem cuya foto envía Eli o None)
CLIENTES = {
 'restaurante': [
  ('Camila','Rojas','Hola, buenas noches. ¿Tienen mesa para 4 personas mañana a las 8 pm?','¡Hola Camila! Bienvenida a Sabor Criollo 🍽️ Mañana a las 8:00 p. m. tenemos mesa para 4 en la terraza. ¿Te la reservo a tu nombre?',None),
  ('Andrés','Pardo','Buenas, quiero pedir a domicilio una bandeja paisa','¡Hola Andrés! Esta es nuestra Bandeja paisa ($38.000): frijoles, arroz, carne molida, chicharrón, chorizo, huevo, plátano y arepa. ¿A qué dirección la enviamos?',1),
  ('Laura','Gómez','Hola, ¿ustedes tienen opciones sin gluten?','Hola Laura 😊 La Arepa rellena de pollo ($16.000) es de maíz y no lleva gluten. Si tu alergia es severa te paso con el administrador para confirmar con cocina.',3),
  ('Felipe','Martínez','¿Cuánto vale la hamburguesa?','Hola Felipe, la Hamburguesa de la casa cuesta $28.000: carne de res de 180 g, queso, tocineta y papas a la francesa.',2),
  ('Valentina','Ortiz','Quiero algo fresco para tomar, ¿qué me recomiendas?','¡Hola Valentina! Te recomiendo la Limonada de coco ($12.000), cremada y bien fría 🥥',4),
  ('Daniel','Herrera','¿Tienen postres? Es para un cumpleaños','¡Claro, Daniel! 🎂 Nuestro Tres leches ($14.000) es el favorito para celebrar; podemos llevarlo con una vela.',5),
  ('Sofía','Vargas','Hola, ¿a qué hora abren hoy?','Hola Sofía, hoy atendemos de 12:00 m. a 10:00 p. m. ¿Quieres que te reserve una mesa?',None),
  ('Juan','Castillo','Necesito reservar para 12 personas el sábado','Hola Juan, para grupos grandes aviso de inmediato al administrador para organizar la mesa. ¿Me confirmas la hora y un teléfono de contacto?',None),
  ('Mariana','Suárez','Me gustaría pedir 2 arepas rellenas y una limonada','¡Perfecto, Mariana! 2 Arepas rellenas ($32.000) y 1 Limonada de coco ($12.000): total $44.000. ¿Domicilio o recoges en el local?',3),
  ('Camilo','Reyes','¿Hacen domicilios a Chapinero?','Sí, Camilo, llegamos a Chapinero. El domicilio vale $5.000 y tarda unos 40 minutos. ¿Qué te provoca pedir?',None),
  ('Natalia','Moreno','¿La bandeja paisa alcanza para dos?','Hola Natalia, la Bandeja paisa es generosa y para dos personas puede alcanzar si piden entradas. Aquí te la muestro 😊',1),
  ('Esteban','Cárdenas','Quiero cancelar mi reserva de mañana','Listo Esteban, ¿me confirmas a nombre de quién estaba? Cancelo la reserva y te aviso. La consignación se puede reagendar según disponibilidad.',None),
  ('Paula','Jiménez','¿Cuánto demora el domicilio a Usaquén?','Hola Paula, a Usaquén llegamos en unos 35 minutos y el domicilio cuesta $5.000. ¿Qué te provoca pedir?',None),
  ('Sebastián','Ruiz','¿Tienen parqueadero?','Hola Sebastián, sí, tenemos parqueadero gratuito para clientes con reserva. ¿Quieres que te reserve mesa?',None),
  ('Isabela','Pineda','¿Tienen menú para niños?','Hola Isabela, tenemos porciones pequeñas: la Hamburguesa de la casa en tamaño infantil. Aquí está la versión normal para que la veas.',2),
  ('Tomás','Aguirre','Quiero la bandeja paisa y un tres leches','¡Buena elección, Tomás! 1 Bandeja paisa ($38.000) + 1 Tres leches ($14.000) = $52.000. ¿Lo enviamos a domicilio?',5),
  ('Gabriela','Salazar','¿Aceptan pago con Nequi?','Sí, Gabriela: aceptamos Nequi, Bre-B y transferencia. Envíanos el comprobante y confirmamos tu pedido.',None),
  ('Mateo','Duarte','¿Se puede reservar en la terraza?','Claro, Mateo 🌿 Te dejé reservada una mesa en la terraza hoy a las 7:30 p. m. para 4 personas. ¡Te esperamos!',None),
  ('Alejandra','Rincón','Mi pedido no ha llegado, llevo una hora esperando','Lamento la demora, Alejandra. Ya aviso al administrador para que lo revise de inmediato y te escribe una persona del equipo en unos minutos.',None),
  ('Nicolás','Quintero','Gracias, todo estuvo delicioso 😍','¡Qué alegría, Nicolás! Gracias por visitarnos. Te esperamos pronto en Sabor Criollo 🍽️',None)],
 'veterinaria': [
  ('Mariana','Ruiz','Hola, mi perro Max tiene las vacunas atrasadas, ¿puedo sacar cita?','¡Hola Mariana! 🐶 Para Max tenemos la Vacuna múltiple ($75.000). Hay cupo el jueves a las 10:00 a. m. o a las 3:00 p. m.',2),
  ('Julián','Castro','Mi gata Luna lleva dos días sin comer y está decaída','Hola Julián, lamento que Luna esté así 🐱 Dos días sin comer requiere revisión pronta. Te doy cita de Consulta general ($60.000) hoy a las 4:00 p. m.',1),
  ('Paola','Díaz','Tengo un cachorro de 3 meses, ¿qué necesita?','¡Hola Paola, qué ternura! 🐕 A los 3 meses necesita esquema de vacunas y desparasitación ($35.000). Te muestro cómo es.',4),
  ('Camilo','Torres','¿Cuánto cuesta el baño para un golden?','Hola Camilo, el Baño y peluquería cuesta $55.000 e incluye baño medicado, corte de pelo y de uñas y limpieza de oídos.',3),
  ('Lucía','Ramírez','Quiero esterilizar a mi perra, ¿cuánto vale?','Hola Lucía, la Esterilización canina cuesta $320.000 con exámenes previos, anestesia y control posoperatorio. Agendamos primero una consulta de valoración.',5),
  ('Andrés','Cifuentes','Mi perro se comió un chocolate, ¿qué hago?','Andrés, es una urgencia: llévalo ya a la clínica. Aviso al veterinario de turno para que lo reciba de inmediato. ¿Cuánto pesa y cuánto comió?',None),
  ('Diana','Mejía','¿Atienden los sábados?','Hola Diana, sí, los sábados atendemos de 8:00 a. m. a 1:00 p. m. ¿Quieres que te agende una consulta?',None),
  ('Santiago','Londoño','Necesito desparasitar a mis dos gatos','Perfecto, Santiago. La Desparasitación ($35.000 por mascota) se da según el peso. Para los dos serían $70.000. ¿Qué día te sirve?',4),
  ('Carolina','Ospina','¿Tienen servicio de peluquería para un schnauzer?','Claro, Carolina 🐾 El Baño y peluquería ($55.000) incluye corte de raza. Hay cupo mañana a las 9:00 a. m.',3),
  ('Mauricio','Gil','Mi perro cojea desde ayer','Hola Mauricio, conviene que lo vea el veterinario pronto. Te agendo una Consulta general ($60.000) hoy o mañana a primera hora. ¿Cuál prefieres?',1),
  ('Juliana','Arango','¿A qué edad se esteriliza una gata?','Hola Juliana, normalmente desde los 6 meses, según su peso y salud. Lo ideal es una consulta para valorarla antes de agendar.',None),
  ('Ricardo','Bermúdez','Quiero cancelar la cita de hoy','Listo Ricardo, ¿me confirmas el nombre de la mascota? Cancelo la cita y te ofrezco otra fecha cuando quieras.',None),
  ('Manuela','Parra','¿Cuánto cuesta la consulta?','Hola Manuela, la Consulta general cuesta $60.000. Aquí te muestro el servicio.',1),
  ('Felipe','Osorio','¿Atienden urgencias en la noche?','Hola Felipe, las urgencias las atendemos hasta las 10:00 p. m. Pasada esa hora te recomiendo una clínica 24 horas; si quieres te paso la dirección.',None),
  ('Angélica','Mora','¿La vacuna múltiple sirve para gatos?','Hola Angélica, para gatos usamos la vacuna triple felina; la Vacuna múltiple ($75.000) cubre el esquema anual según la especie. Aquí te la muestro.',2),
  ('Jorge','Villa','¿Tienen guardería para perros?','Hola Jorge, por ahora no ofrecemos guardería, pero sí consulta, vacunas, baño y cirugías. ¿Te ayudo con alguno?',None),
  ('Natalia','Cortés','Mi cachorro tiene diarrea hace 2 días','Hola Natalia, en cachorros la diarrea puede deshidratar rápido. Te agendo una Consulta general ($60.000) hoy mismo y aviso al veterinario.',1),
  ('Oscar','Franco','¿Cómo es el procedimiento de la esterilización?','Hola Óscar, se hace con anestesia y exámenes previos; la mascota sale el mismo día con indicaciones de cuidado. Te muestro el servicio.',5),
  ('Daniela','Peña','¿Puedo llevar a mi mascota sin cita?','Hola Daniela, para urgencias sí; para consultas de rutina es mejor agendar y así no esperas. ¿Te busco un cupo?',None),
  ('Esteban','Vega','Gracias por atender tan rápido a Luna 🐱','¡Gracias a ti, Esteban! Nos alegra que Luna esté mejor. Cualquier duda, aquí estoy.',None)],
 'aerolinea': [
  ('Sergio','Molina','Hola, necesito un vuelo Bogotá–Medellín el viernes en la mañana','¡Hola Sergio! ✈️ El viernes tengo vuelo a las 7:10 a. m. y a las 9:40 a. m. en tarifa Light desde $189.000 (equipaje de mano).',1),
  ('Daniela','Vargas','¿Cuánto cuesta ir a Cartagena el 20 de diciembre?','Hola Daniela. A Cartagena el 20 de diciembre tengo la tarifa Flex en $275.000, con maleta de 23 kg y un cambio de fecha sin costo.',2),
  ('Carlos','Núñez','¿Tienen vuelos baratos a San Andrés en enero?','Hola Carlos 🏝️ Para enero tengo la tarifa Promo a San Andrés en $415.000 con equipaje de mano, con cupos limitados.',3),
  ('Laura','Cárdenas','¿Cuánto cuesta agregar una maleta?','Hola Laura, la Maleta de bodega de 23 kg cuesta $85.000 por trayecto si la agregas antes del viaje.',4),
  ('Andrés','Rojas','Quiero elegir asiento de ventana','Claro, Andrés. La Selección de asiento cuesta $25.000 y puedes elegir ventana o pasillo antes del check-in.',5),
  ('Paula','Medina','¿Puedo cambiar la fecha de mi vuelo?','Hola Paula, con la tarifa Flex tienes un cambio de fecha sin costo; con Light no hay cambios. ¿Qué tarifa compraste?',2),
  ('Julián','Pardo','Necesito 3 tiquetes Bogotá–Medellín para el viernes','Perfecto, Julián. 3 pasajeros en tarifa Light son $567.000. ¿Me envías nombres completos y documentos?',1),
  ('Camila','Soto','¿Cuánto equipaje puedo llevar en la tarifa Light?','Hola Camila, la tarifa Light incluye solo equipaje de mano. Si necesitas maleta puedes agregarla por $85.000.',4),
  ('Felipe','Gómez','Mi cédula es 1.020.345.678, ¿ya quedó mi reserva?','Gracias Felipe. Tu reserva se mantiene por 24 horas mientras envías el comprobante de pago.',None),
  ('Valeria','Sánchez','¿Cómo pago el tiquete?','Hola Valeria, pagas por consignación o transferencia y envías la foto del comprobante; una persona verifica el monto y emitimos el tiquete.',None),
  ('Mateo','Arias','¿Puedo viajar con un menor de edad solo?','Hola Mateo, los menores de 12 años viajan con un adulto; entre 12 y 17 años se requiere permiso notarial. Si necesitas más detalle te paso con una persona del equipo.',None),
  ('Sara','Londoño','¿Hay vuelos a Cartagena en diciembre con maleta incluida?','Sí, Sara: la tarifa Flex a Cartagena ($275.000) incluye maleta de 23 kg. ¿Qué fechas tienes?',2),
  ('Nicolás','Ibarra','Quiero cancelar mi vuelo','Hola Nicolás, ¿me confirmas tu código de reserva? Reviso las condiciones de tu tarifa: Light no tiene devolución y Flex permite un cambio de fecha.',None),
  ('Isabella','Rey','¿A qué hora sale el vuelo a San Andrés?','Hola Isabella, el vuelo a San Andrés sale a las 6:30 a. m. y llega a las 8:20 a. m. Aquí te muestro la tarifa Promo.',3),
  ('David','Correa','¿Puedo viajar con mi mascota?','Hola David, aceptamos mascotas pequeñas en cabina con guacal y certificado. Te paso con una persona del equipo para confirmar requisitos.',None),
  ('Luisa','Bernal','Somos 2 adultos y un niño de 5 años','Hola Luisa, el niño paga tarifa completa si ocupa asiento. Para 3 pasajeros en Light a Medellín serían $567.000. ¿Fecha de viaje?',1),
  ('Diego','Vásquez','¿Cuánto cuesta la maleta de bodega para San Andrés?','Hola Diego, la Maleta de bodega de 23 kg cuesta $85.000 por trayecto.',4),
  ('Mónica','Pacheco','Quiero que mi asiento quede junto a mi esposo','Claro, Mónica. Con la Selección de asiento ($25.000 c/u) eligen asientos contiguos antes del check-in. Tu vuelo de hoy sale a las 6:30 p. m.',5),
  ('Alejandro','Ríos','Perdí mi tiquete, ¿me lo reenvían?','Hola Alejandro, claro. Te lo reenvío por este chat; ¿me confirmas tu número de documento para ubicarlo?',None),
  ('Juliana','Cano','Gracias, excelente servicio ✈️','¡Gracias a ti, Juliana! Buen viaje y aquí estamos para lo que necesites.',None)],
}
PRE = {'restaurante': '+573001110', 'veterinaria': '+573002220', 'aerolinea': '+573003330'}
SKU = {'restaurante': 'RES', 'veterinaria': 'VET', 'aerolinea': 'AER'}

# Conversaciones completas hasta el pago. Cada "pagador" escribe en dos tandas; en la segunda envía el
# comprobante (foto real de prueba). La conversación queda esperando hasta que quien revisa aprueba o rechaza
# el comprobante en el panel; entonces Eli continúa con los mensajes de "aprobado" o "rechazado".
# Mensajes: (emisor, texto, foto del catálogo | None).   Comprobante: dict con la foto y los datos que "lee" Eli.
PAGOS = {
 'restaurante': [],   # los siete pagadores del restaurante se generan abajo con los comprobantes de prueba reales
 'veterinaria': [
  {'conv': 0, 'items': [('VET-02', 1)], 'entrega': 'no_aplica',
   'a': [('cliente', 'Hola, mi perro Max tiene las vacunas atrasadas, ¿puedo sacar cita?', None),
         ('eli', '¡Hola Mariana! 🐶 Para Max tenemos la Vacuna múltiple ($75.000). Hay cupo el jueves a las 10:00 a. m. o a las 3:00 p. m. ¿Cuál te sirve?', 2),
         ('cliente', 'El jueves a las 10', None),
         ('eli', 'Agendado: jueves 10:00 a. m. Para dejar la cita confirmada se paga la vacuna por adelantado: Nequi al 300 416 5923 por $75.000. Envíame el comprobante 📸', None)],
   'b': [('cliente', 'Ya pagué por Nequi', None),
         ('eli', 'Gracias Mariana, envíame la foto del comprobante para validarlo.', None),
         ('cliente', '📎 Comprobante de pago Nequi', 'comprobante'),
         ('eli', 'Recibido ✅ Lo pasé al equipo para validar el monto y confirmarte la cita.', None)],
   'comp': {'img': 'comprobante-veterinaria', 'monto': 75000, 'destinatario': 'Luis Rodriguez', 'app': 'Nequi', 'ref': 'M19936704', 'fecha': '10 de julio de 2026 a las 06:32 p. m.', 'hash': 'demo-veterinaria-1'},
   'aprobado': [('eli', '¡Pago confirmado! ✅ La cita de Max quedó confirmada para el jueves a las 10:00 a. m. (orden #{orden}). Trae su carné de vacunación.'),
                ('cliente', 'Perfecto, ahí estaremos'),
                ('eli', 'Los esperamos, Mariana. ¡Un abrazo a Max! 🐾')],
   'rechazado': [('eli', 'Mariana, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?')]}],
 'aerolinea': [
  {'conv': 0, 'items': [('AER-02', 1), ('AER-04', 1)], 'entrega': 'no_aplica',
   'a': [('cliente', 'Hola, necesito un vuelo Bogotá–Cartagena el 20 de diciembre, con maleta', None),
         ('eli', '¡Hola Sergio! ✈️ El 20 de diciembre a Cartagena tengo la tarifa Flex en $275.000 (cambio de fecha sin costo). La Maleta de bodega de 23 kg son $85.000. Total $360.000. ¿Te reservo?', 2),
         ('cliente', 'Sí, a nombre de Sergio Molina, cédula 1.020.345.678', None),
         ('eli', 'Reservado ✅ Tu reserva se mantiene 24 horas. Paga $360.000 por DaviPlata o Nequi al 300 416 5923 y envíame el comprobante para emitir el tiquete.', None)],
   'b': [('cliente', 'Ya hice el pago por DaviPlata', None),
         ('eli', 'Gracias Sergio, envíame la foto del comprobante para validarlo.', None),
         ('cliente', '📎 Comprobante de pago DaviPlata', 'comprobante'),
         ('eli', 'Recibido ✅ Lo pasé al equipo para validar el monto y emitir tu tiquete.', None)],
   'comp': {'img': 'comprobante-aerolinea', 'monto': 360000, 'destinatario': 'Luis Fernando Rodríguez Sandoval', 'app': 'DaviPlata', 'ref': '948312', 'fecha': 'Julio 09 de 2026 - 05:39 p. m.', 'hash': 'demo-aerolinea-1'},
   'aprobado': [('eli', '¡Pago confirmado! ✅ Tu tiquete Bogotá–Cartagena del 20 de diciembre quedó emitido (orden #{orden}). Te lo envío por este chat. ¡Buen viaje!'),
                ('cliente', 'Muchas gracias'),
                ('eli', 'A ti, Sergio. ¡Que tengas un excelente vuelo! ✈️')],
   'rechazado': [('eli', 'Sergio, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?')]}],
}
# Orden de llegada: ('q', n) cliente de una sola respuesta; ('a', k) / ('b', k) primera / segunda tanda del pagador k
COLA = {
 'restaurante': [('a', 0), ('q', 2), ('q', 3), ('a', 1), ('q', 4), ('q', 5), ('q', 6), ('q', 7), ('b', 0), ('q', 8), ('q', 9), ('q', 10), ('b', 1)] + [('q', n) for n in range(11, 20)],
 'veterinaria': [('a', 0)] + [('q', n) for n in range(1, 6)] + [('b', 0)] + [('q', n) for n in range(6, 20)],
 'aerolinea': [('a', 0)] + [('q', n) for n in range(1, 6)] + [('b', 0)] + [('q', n) for n in range(6, 20)],
}
# ---- Pagadores adicionales (se generan con plantillas): correctos y con monto distinto al del comprobante ----
def _m(n): return '$' + format(n, ',').replace(',', '.')
_NOM = {i[2]: (i[3], i[5]) for c in CASOS.values() for i in c['items']}
_IMG = {'restaurante': ('comprobante-restaurante', 80000, 'Luis Rodriguez', 'Nequi', '18 de julio de 2026 a las 08:33 p. m.'),
        'veterinaria': ('comprobante-veterinaria', 75000, 'Luis Rodriguez', 'Nequi', '10 de julio de 2026 a las 06:32 p. m.'),
        'aerolinea': ('comprobante-aerolinea', 360000, 'Luis Fernando Rodríguez Sandoval', 'DaviPlata', 'Julio 09 de 2026 - 05:39 p. m.')}
# vertical: [(conv, pedido del cliente, [(sku, cant)], entrega, qué es el pedido al confirmar)]
_EXTRA = {
 'restaurante': [
   (0, 'Quiero la cena de aniversario para mi esposo y para mí', [('RES-07', 1)], 'no_aplica', 'Quedó reservada con su decoración. ¡Feliz aniversario! 💐',
    ('comprobante-res-2', 80000, 'Luis Rodriguez', 'Nequi', 'M25797932', '18 de julio de 2026 a las 08:33 p. m.')),
   (4, 'Quiero la cena de aniversario premium', [('RES-10', 1)], 'no_aplica', 'Quedó reservada con decoración completa y vino. ¡Feliz aniversario! 🍷',
    ('comprobante-res-1', 160000, 'Luis Rodriguez', 'Nequi', 'M26257385', '14 de julio de 2026 a las 11:16 p. m.')),
   (5, 'Quiero el pack de cumpleaños para mi hija', [('RES-06', 1)], 'no_aplica', 'Quedó reservada la decoración de cumpleaños 🎈',
    ('comprobante-res-3', 50000, 'Luis Rodriguez', 'Nequi', 'M16356689', '09 de julio de 2026 a las 05:11 p. m.')),
   (8, 'Necesito el pack adicional de globos y mesa de dulces', [('RES-11', 1)], 'no_aplica', 'Quedó agregado a tu celebración 🎈',
    ('comprobante-res-5', 69000, 'Luis Rodriguez', 'Nequi', 'M19936704', '10 de julio de 2026 a las 06:32 p. m.')),
   (12, 'Quiero el pack de grado para mi hermano', [('RES-09', 1)], 'no_aplica', 'Quedó reservado el pack de grado 🎓',
    ('comprobante-res-4', 65000, 'Luis Rodriguez', 'Bancolombia', 'TRrUw0H9AIEC', '11 de julio de 2026 a las 9:27 a. m.')),
   (13, 'Quiero reservar mesa para celebrar, sin decoración', [('RES-12', 1)], 'no_aplica', 'Quedó reservada tu mesa para la celebración.',
    ('comprobante-res-6', 30000, 'Luis Rodriguez', 'Transferencia', 'T120712-1104', '12 de julio de 2026 a las 11:04 a. m.')),
   (16, 'Quiero el pack de cumpleaños', [('RES-06', 1)], 'no_aplica', 'Quedó reservada la decoración de cumpleaños 🎈',
    ('comprobante-res-7', 75000, 'Luis Rodriguez', 'Nequi', 'M19936704', '10 de julio de 2026 a las 06:32 p. m.'))],
 'veterinaria': [(14, 'Quiero la vacuna múltiple para mi gata Nina', [('VET-02', 1)], 'no_aplica', 'Quedó agendada para mañana a las 9:00 a. m. Trae su carné.'),
                 (3, 'Quiero el baño y peluquería para mi golden', [('VET-03', 1)], 'no_aplica', 'Quedó agendado para mañana a las 11:00 a. m.'),
                 (7, 'Necesito desparasitar a mis dos gatos', [('VET-04', 2)], 'no_aplica', 'Quedó agendado para mañana a las 2:00 p. m.')],
 'aerolinea': [(1, 'Quiero el vuelo a Cartagena del 20 de diciembre con maleta', [('AER-02', 1), ('AER-04', 1)], 'no_aplica', 'Tu tiquete quedó emitido y te lo envío por este chat.'),
               (6, 'Necesito 3 tiquetes Bogotá–Medellín para el viernes', [('AER-01', 3)], 'no_aplica', 'Tus tiquetes quedaron emitidos.'),
               (2, 'Quiero la tarifa promo a San Andrés en enero', [('AER-03', 1)], 'no_aplica', 'Tu tiquete quedó emitido.')],
}
for _v, _lst in _EXTRA.items():
    for _j, _e in enumerate(_lst, start=len(PAGOS[_v]) + 1):
        _cv, _pedido, _its, _ent, _fin = _e[:5]
        if len(_e) > 5: _img, _mi, _dest, _app, _ref, _fec = _e[5]
        else: _img, _mi, _dest, _app, _fec = _IMG[_v]; _ref = ('M%08d' % (20000000 + 7919 * _j)) if _app == 'Nequi' else str(948000 + 311 * _j)
        _nom = CLIENTES[_v][_cv][0]
        _tot = sum(_NOM[sku][1] * q for sku, q in _its)
        _desc = ' y '.join(('%d %s' % (q, _NOM[sku][0]) if q > 1 else '1 ' + _NOM[sku][0]) for sku, q in _its)
        _ok = _tot == _mi
        _pag = 'Nequi al 300 416 5923' + (' o DaviPlata' if _v == 'aerolinea' else '')
        PAGOS[_v].append({'conv': _cv, 'items': _its, 'entrega': _ent,
          'a': [('cliente', 'Hola, ' + _pedido[0].lower() + _pedido[1:], None),
                ('eli', '¡Hola %s! Anoto %s. Total %s. Para confirmarlo paga por %s y envíame el comprobante 📸' % (_nom, _desc, _m(_tot), _pag), None)],
          'b': [('cliente', 'Ya pagué, aquí va el comprobante', None),
                ('cliente', '📎 Comprobante de pago ' + _app, 'comprobante'),
                ('eli', 'Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.', None)],
          'comp': {'img': _img, 'monto': _mi, 'destinatario': _dest, 'app': _app, 'ref': _ref,
                   'fecha': _fec, 'hash': 'demo-%s-%d' % (_v, _j)},
          'aprobado': [('eli', '¡Pago confirmado! ✅ Tu pedido #{orden} (%s por %s) %s' % (_desc, _m(_tot), _fin)),
                       ('cliente', 'Muchas gracias'), ('eli', 'Con gusto, %s. ¡Estamos para servirte!' % _nom)],
          'rechazado': ([('eli', '%s, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?' % _nom)] if _ok else
                        [('eli', '%s, el comprobante es por %s y tu pedido es de %s, así que no pudimos validarlo. ¿Me envías el comprobante correcto?' % (_nom, _m(_mi), _m(_tot))),
                         ('cliente', 'Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío'),
                         ('eli', 'Tranquilo, %s 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato.' % _nom)])})
# Orden de llegada: cada cliente en su turno; el comprobante de cada pagador llega unos mensajes después
for _v in CASOS:
    _pc = {p['conv']: k for k, p in enumerate(PAGOS[_v])}
    _seq, _pend = [], []
    for _n in range(20):
        _seq.append(('a', _pc[_n]) if _n in _pc else ('q', _n))
        if _n in _pc: _pend.append((len(_seq) + 4, ('b', _pc[_n])))
        for _pos, _it in list(_pend):
            if len(_seq) >= _pos: _seq.append(_it); _pend.remove((_pos, _it))
    _seq += [_it for _, _it in _pend]
    COLA[_v] = _seq

for _v, _c in CASOS.items():
    _c['contactos'] = [(n, a, '%s%03d' % (PRE[_v], i + 1)) for i, (n, a, _m, _r, _f) in enumerate(CLIENTES[_v])]
    _c['pagos'] = []
    for _k, _p in enumerate(PAGOS[_v]):
        _c['pagos'].append({'conv': _p['conv'], 'items': _p['items'], 'entrega': _p['entrega'], 'comp': _p['comp'],
                            'aprobado': [dict(emisor=e, texto=t) for e, t in _p['aprobado']],
                            'rechazado': [dict(emisor=e, texto=t) for e, t in _p['rechazado']]})
    _g = []
    for _t, _n in COLA[_v]:
        if _t == 'q':
            _, _, m, r, f = CLIENTES[_v][_n]
            _g += [(_n, 'cliente', m, None, None), (_n, 'eli', r, f, None)]
        else:
            _p = PAGOS[_v][_n]
            for e, t, x in _p['a' if _t == 'a' else 'b']:
                _g.append((_p['conv'], e, t, x if isinstance(x, int) else None, _n if x == 'comprobante' else None))
    _c['guion'] = _g

# Efectos que ocurren al entregarse un mensaje de Eli (se buscan por el comienzo de su texto):
#   escalar: Eli pasa el caso a una persona (aparece en Pendientes)
#   reserva: Eli deja una reserva para hoy (aparece en Agenda de hoy); h = hora del día, recurso = nombre del recurso
RECURSOS = {
  'restaurante': [('mesa', 'Terraza 1', 4), ('mesa', 'Mesa 2', 2)],
  'veterinaria': [('consultorio', 'Consultorio 1', 1)],
  'aerolinea': [('otro', 'Vuelo BOG–MDE 6:30 p. m.', 180)],
}
EFECTOS = {
  'restaurante': [
    ('Hola Laura', dict(escalar='Alergia alimentaria: confirmar ingredientes con cocina', resumen='Laura pregunta por opciones sin gluten por una alergia; Eli ofreció la arepa de pollo y pasó el caso al administrador.')),
    ('Lamento la demora', dict(escalar='Reclamo: pedido demorado más de una hora', resumen='Alejandra lleva una hora esperando su pedido; requiere revisar con cocina y domicilio.')),
    ('Claro, Mateo', dict(reserva='mesa', h=19.5, personas=4, recurso='Terraza 1')),
  ],
  'veterinaria': [
    ('Hola Julián', dict(reserva='cita', h=16, personas=1, recurso='Consultorio 1', urgente=True)),
    ('Hola Natalia', dict(escalar='Posible urgencia: cachorro con diarrea de 2 días', resumen='Cachorro con diarrea hace 2 días: riesgo de deshidratación; Eli agendó consulta y pide valoración del veterinario.')),
  ],
  'aerolinea': [
    ('Hola Alejandro', dict(escalar='Reenvío de tiquete: validar documento de identidad', resumen='Alejandro perdió su tiquete; Eli pidió el documento y requiere validación humana antes de reenviarlo.')),
    ('Claro, Mónica', dict(reserva='vuelo', h=18.5, personas=2, recurso='Vuelo BOG–MDE 6:30 p. m.')),
  ],
}
for _v, _c in CASOS.items():
    _c['recursos'] = RECURSOS[_v]
    _e = []
    for _ini, _d in EFECTOS[_v]:
        _i = next(i for i, g in enumerate(_c['guion']) if g[1] == 'eli' and g[2].startswith(_ini))
        _e.append(dict(_d, tras=_i))
    _c['efectos'] = _e

# Reservas ya agendadas (para que el calendario no esté vacío): (días desde hoy, hora, cliente, tipo, personas, recurso, estado, urgente)
AGENDA = {
 'restaurante': [(0,21.5,7,'mesa',12,'Terraza 1','pendiente_pago',False),(1,19.5,4,'mesa',2,'Mesa 2','confirmada',False),(1,20,5,'mesa',6,'Terraza 1','confirmada',False),
                 (2,13,9,'mesa',4,'Mesa 2','confirmada',False),(3,20.5,10,'mesa',2,'Mesa 2','confirmada',False),(4,19,12,'mesa',8,'Terraza 1','confirmada',False),
                 (5,13.5,13,'mesa',4,'Terraza 1','pendiente_pago',False),(6,14,14,'mesa',5,'Terraza 1','confirmada',False),(8,20,15,'mesa',4,'Mesa 2','confirmada',False),
                 (9,19,16,'mesa',10,'Terraza 1','confirmada',False),(11,13,19,'mesa',2,'Mesa 2','confirmada',False)],
 'veterinaria': [(0,17.5,2,'cita',1,'Consultorio 1','confirmada',False),(1,9,5,'cita',1,'Consultorio 1','confirmada',True),(1,15,9,'cita',1,'Consultorio 1','confirmada',False),
                 (2,10,10,'cita',1,'Consultorio 1','confirmada',False),(3,16,12,'cita',1,'Consultorio 1','pendiente_pago',False),(4,11,13,'cita',1,'Consultorio 1','confirmada',False),
                 (6,9.5,15,'cita',1,'Consultorio 1','confirmada',False),(7,14,17,'cita',1,'Consultorio 1','confirmada',False),(9,10,18,'cita',1,'Consultorio 1','confirmada',False),
                 (10,15.5,19,'cita',1,'Consultorio 1','pendiente_pago',False)],
 'aerolinea': [(0,21,3,'vuelo',1,'Vuelo BOG–MDE 6:30 p. m.','confirmada',False),(1,18.5,4,'vuelo',2,'Vuelo BOG–MDE 6:30 p. m.','confirmada',False),(2,7,5,'vuelo',3,'Vuelo BOG–MDE 6:30 p. m.','confirmada',False),
               (3,18.5,8,'vuelo',1,'Vuelo BOG–MDE 6:30 p. m.','pendiente_pago',False),(5,7,9,'vuelo',2,'Vuelo BOG–MDE 6:30 p. m.','confirmada',False),(6,18.5,10,'vuelo',1,'Vuelo BOG–MDE 6:30 p. m.','confirmada',False),
               (8,7,12,'vuelo',4,'Vuelo BOG–MDE 6:30 p. m.','confirmada',False),(10,18.5,13,'vuelo',1,'Vuelo BOG–MDE 6:30 p. m.','pendiente_pago',False)],
}
for _v, _c in CASOS.items():
    _c['agenda'] = AGENDA[_v]

# Colores de cada caso (para logos e ilustraciones)
COLOR = {'restaurante': ('#b45309', '#fde68a'), 'veterinaria': ('#0f766e', '#99f6e4'), 'aerolinea': ('#1d4ed8', '#bfdbfe')}
