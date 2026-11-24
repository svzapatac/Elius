-- =============================================================================
-- 1200 · Casos de prueba por vertical (restaurante, veterinaria, aerolínea)
-- La profesora elige un caso en el panel: se crea su negocio con catálogo (5 ítems con imagen) y llegan
-- 20 clientes de prueba. Tres conversaciones llegan hasta el pago: el cliente envía el comprobante,
-- queda en Comprobantes y, cuando quien revisa lo aprueba o lo rechaza, Eli continúa la conversación.
-- =============================================================================

create or replace function elius.datos_caso_demo(p_vertical text)
returns jsonb language sql immutable set search_path = '' as $$
  select case p_vertical
    when 'restaurante' then '{"negocio": "Restaurante Sabor Criollo", "categorias": ["Platos fuertes", "Bebidas", "Postres"], "contactos": [["Camila", "Rojas", "+573001110001"], ["Andrés", "Pardo", "+573001110002"], ["Laura", "Gómez", "+573001110003"], ["Felipe", "Martínez", "+573001110004"], ["Valentina", "Ortiz", "+573001110005"], ["Daniel", "Herrera", "+573001110006"], ["Sofía", "Vargas", "+573001110007"], ["Juan", "Castillo", "+573001110008"], ["Mariana", "Suárez", "+573001110009"], ["Camilo", "Reyes", "+573001110010"], ["Natalia", "Moreno", "+573001110011"], ["Esteban", "Cárdenas", "+573001110012"], ["Paula", "Jiménez", "+573001110013"], ["Sebastián", "Ruiz", "+573001110014"], ["Isabela", "Pineda", "+573001110015"], ["Tomás", "Aguirre", "+573001110016"], ["Gabriela", "Salazar", "+573001110017"], ["Mateo", "Duarte", "+573001110018"], ["Alejandra", "Rincón", "+573001110019"], ["Nicolás", "Quintero", "+573001110020"]], "items": [{"cat": 0, "tipo": "producto", "sku": "RES-01", "nombre": "Bandeja paisa", "desc": "Frijoles, arroz, carne molida, chicharrón, chorizo, huevo, plátano maduro y arepa.", "precio": 38000, "iva": 0, "dur": null}, {"cat": 0, "tipo": "producto", "sku": "RES-02", "nombre": "Hamburguesa de la casa", "desc": "Carne de res 180 g, queso, tocineta y papas a la francesa.", "precio": 28000, "iva": 0, "dur": null}, {"cat": 0, "tipo": "producto", "sku": "RES-03", "nombre": "Arepa rellena de pollo", "desc": "Arepa de maíz rellena de pollo desmechado con guacamole.", "precio": 16000, "iva": 0, "dur": null}, {"cat": 1, "tipo": "producto", "sku": "RES-04", "nombre": "Limonada de coco", "desc": "Limonada cremada con coco, servida bien fría.", "precio": 12000, "iva": 0, "dur": null}, {"cat": 2, "tipo": "producto", "sku": "RES-05", "nombre": "Tres leches", "desc": "Bizcocho bañado en tres leches con crema y canela.", "precio": 14000, "iva": 0, "dur": null}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, buenas noches. Quiero pedir a domicilio 2 hamburguesas y 2 limonadas de coco", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Camila! 🍔 Anoto 2 Hamburguesas de la casa ($56.000) y 2 Limonadas de coco ($24.000). Total $80.000 con domicilio gratis hoy. ¿A qué dirección las llevamos?", "img": 2, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Carrera 15 # 82-10, apto 301", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Perfecto, Cra 15 #82-10 apto 301 📍 Para confirmar el pedido paga $80.000 por Nequi al 300 416 5923 o con la llave Bre-B @saborcriollo, y envíame la foto del comprobante 📸", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "Buenas, quiero pedir una bandeja paisa y un tres leches para recoger", "img": null, "comp": null}, {"conv": 1, "emisor": "eli", "texto": "¡Hola Andrés! Anoto 1 Bandeja paisa ($38.000) y 1 Tres leches ($14.000): total $52.000 para recoger. Paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": 1, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "Hola, ¿ustedes tienen opciones sin gluten?", "img": null, "comp": null}, {"conv": 2, "emisor": "eli", "texto": "Hola Laura 😊 La Arepa rellena de pollo ($16.000) es de maíz y no lleva gluten. Si tu alergia es severa te paso con el administrador para confirmar con cocina.", "img": 3, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "Hola, quiero pedir a domicilio una bandeja paisa, una hamburguesa y un tres leches", "img": null, "comp": null}, {"conv": 3, "emisor": "eli", "texto": "¡Hola Felipe! Anoto 1 Bandeja paisa y 1 Hamburguesa de la casa y 1 Tres leches. Total $80.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 4, "emisor": "cliente", "texto": "Quiero algo fresco para tomar, ¿qué me recomiendas?", "img": null, "comp": null}, {"conv": 4, "emisor": "eli", "texto": "¡Hola Valentina! Te recomiendo la Limonada de coco ($12.000), cremada y bien fría 🥥", "img": 4, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Listo, ya hice la transferencia por Nequi", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "¡Gracias Camila! Envíame la foto del comprobante para validar el pago.", "img": null, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 0}, {"conv": 0, "emisor": "eli", "texto": "Recibido ✅ Ya lo pasé al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "📎 Ya pagué, aquí está el comprobante", "img": null, "comp": 1}, {"conv": 1, "emisor": "eli", "texto": "Gracias Andrés, lo paso al equipo para validarlo.", "img": null, "comp": null}, {"conv": 5, "emisor": "cliente", "texto": "¿Tienen postres? Es para un cumpleaños", "img": null, "comp": null}, {"conv": 5, "emisor": "eli", "texto": "¡Claro, Daniel! 🎂 Nuestro Tres leches ($14.000) es el favorito para celebrar; podemos llevarlo con una vela.", "img": 5, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 2}, {"conv": 3, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "Hola, ¿a qué hora abren hoy?", "img": null, "comp": null}, {"conv": 6, "emisor": "eli", "texto": "Hola Sofía, hoy atendemos de 12:00 m. a 10:00 p. m. ¿Quieres que te reserve una mesa?", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "Necesito reservar para 12 personas el sábado", "img": null, "comp": null}, {"conv": 7, "emisor": "eli", "texto": "Hola Juan, para grupos grandes aviso de inmediato al administrador para organizar la mesa. ¿Me confirmas la hora y un teléfono de contacto?", "img": null, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "Hola, me gustaría pedir 2 arepas rellenas y una limonada para recoger", "img": null, "comp": null}, {"conv": 8, "emisor": "eli", "texto": "¡Hola Mariana! Anoto 2 Arepa rellena de pollo y 1 Limonada de coco. Total $44.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 9, "emisor": "cliente", "texto": "¿Hacen domicilios a Chapinero?", "img": null, "comp": null}, {"conv": 9, "emisor": "eli", "texto": "Sí, Camilo, llegamos a Chapinero. El domicilio vale $5.000 y tarda unos 40 minutos. ¿Qué te provoca pedir?", "img": null, "comp": null}, {"conv": 10, "emisor": "cliente", "texto": "¿La bandeja paisa alcanza para dos?", "img": null, "comp": null}, {"conv": 10, "emisor": "eli", "texto": "Hola Natalia, la Bandeja paisa es generosa y para dos personas puede alcanzar si piden entradas. Aquí te la muestro 😊", "img": 1, "comp": null}, {"conv": 11, "emisor": "cliente", "texto": "Quiero cancelar mi reserva de mañana", "img": null, "comp": null}, {"conv": 11, "emisor": "eli", "texto": "Listo Esteban, ¿me confirmas a nombre de quién estaba? Cancelo la reserva y te aviso. La consignación se puede reagendar según disponibilidad.", "img": null, "comp": null}, {"conv": 12, "emisor": "cliente", "texto": "¿Cuánto demora el domicilio a Usaquén?", "img": null, "comp": null}, {"conv": 12, "emisor": "eli", "texto": "Hola Paula, a Usaquén llegamos en unos 35 minutos y el domicilio cuesta $5.000. ¿Qué te provoca pedir?", "img": null, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 3}, {"conv": 8, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 13, "emisor": "cliente", "texto": "¿Tienen parqueadero?", "img": null, "comp": null}, {"conv": 13, "emisor": "eli", "texto": "Hola Sebastián, sí, tenemos parqueadero gratuito para clientes con reserva. ¿Quieres que te reserve mesa?", "img": null, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "¿Tienen menú para niños?", "img": null, "comp": null}, {"conv": 14, "emisor": "eli", "texto": "Hola Isabela, tenemos porciones pequeñas: la Hamburguesa de la casa en tamaño infantil. Aquí está la versión normal para que la veas.", "img": 2, "comp": null}, {"conv": 15, "emisor": "cliente", "texto": "Quiero la bandeja paisa y un tres leches", "img": null, "comp": null}, {"conv": 15, "emisor": "eli", "texto": "¡Buena elección, Tomás! 1 Bandeja paisa ($38.000) + 1 Tres leches ($14.000) = $52.000. ¿Lo enviamos a domicilio?", "img": 5, "comp": null}, {"conv": 16, "emisor": "cliente", "texto": "¿Aceptan pago con Nequi?", "img": null, "comp": null}, {"conv": 16, "emisor": "eli", "texto": "Sí, Gabriela: aceptamos Nequi, Bre-B y transferencia. Envíanos el comprobante y confirmamos tu pedido.", "img": null, "comp": null}, {"conv": 17, "emisor": "cliente", "texto": "¿Se puede reservar en la terraza?", "img": null, "comp": null}, {"conv": 17, "emisor": "eli", "texto": "Claro, Mateo 🌿 Te dejé reservada una mesa en la terraza hoy a las 7:30 p. m. para 4 personas. ¡Te esperamos!", "img": null, "comp": null}, {"conv": 18, "emisor": "cliente", "texto": "Mi pedido no ha llegado, llevo una hora esperando", "img": null, "comp": null}, {"conv": 18, "emisor": "eli", "texto": "Lamento la demora, Alejandra. Ya aviso al administrador para que lo revise de inmediato y te escribe una persona del equipo en unos minutos.", "img": null, "comp": null}, {"conv": 19, "emisor": "cliente", "texto": "Gracias, todo estuvo delicioso 😍", "img": null, "comp": null}, {"conv": 19, "emisor": "eli", "texto": "¡Qué alegría, Nicolás! Gracias por visitarnos. Te esperamos pronto en Sabor Criollo 🍽️", "img": null, "comp": null}], "recursos": [["mesa", "Terraza 1", 4], ["mesa", "Mesa 2", 2]], "efectos": [{"escalar": "Alergia alimentaria: confirmar ingredientes con cocina", "resumen": "Laura pregunta por opciones sin gluten por una alergia; Eli ofreció la arepa de pollo y pasó el caso al administrador.", "tras": 7}, {"escalar": "Reclamo: pedido demorado más de una hora", "resumen": "Alejandra lleva una hora esperando su pedido; requiere revisar con cocina y domicilio.", "tras": 51}, {"reserva": "mesa", "h": 19.5, "personas": 4, "recurso": "Terraza 1", "tras": 49}], "agenda": [[0, 21.5, 7, "mesa", 12, "Terraza 1", "pendiente_pago", false], [1, 19.5, 4, "mesa", 2, "Mesa 2", "confirmada", false], [1, 20, 5, "mesa", 6, "Terraza 1", "confirmada", false], [2, 13, 9, "mesa", 4, "Mesa 2", "confirmada", false], [3, 20.5, 10, "mesa", 2, "Mesa 2", "confirmada", false], [4, 19, 12, "mesa", 8, "Terraza 1", "confirmada", false], [5, 13.5, 13, "mesa", 4, "Terraza 1", "pendiente_pago", false], [6, 14, 14, "mesa", 5, "Terraza 1", "confirmada", false], [8, 20, 15, "mesa", 4, "Mesa 2", "confirmada", false], [9, 19, 16, "mesa", 10, "Terraza 1", "confirmada", false], [11, 13, 19, "mesa", 2, "Mesa 2", "confirmada", false]], "pagos": [{"items": [["RES-02", 2], ["RES-04", 2]], "entrega": "domicilio", "comp": {"img": "comprobante-restaurante", "monto": 80000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M25797932", "fecha": "18 de julio de 2026 a las 08:33 p. m.", "hash": "demo-restaurante-1"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} quedó en cocina: 2 Hamburguesas de la casa y 2 Limonadas de coco por $80.000. Llega en unos 40 minutos 🛵"}, {"emisor": "cliente", "texto": "Mil gracias, quedo pendiente"}, {"emisor": "eli", "texto": "Con gusto, Camila. ¡Que lo disfrutes! 🍔 Si necesitas algo más, escríbeme."}], "rechazado": [{"emisor": "eli", "texto": "Camila, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["RES-01", 1], ["RES-05", 1]], "entrega": "recoger", "comp": {"img": "comprobante-restaurante", "monto": 80000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M25797932", "fecha": "18 de julio de 2026 a las 08:33 p. m.", "hash": "demo-restaurante-1"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} estará listo para recoger en 25 minutos."}, {"emisor": "cliente", "texto": "Gracias"}, {"emisor": "eli", "texto": "A ti, Andrés. ¡Buen provecho!"}], "rechazado": [{"emisor": "eli", "texto": "Andrés, el comprobante que enviaste es por $80.000 y tu pedido es de $52.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, perdón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Andrés 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}, {"items": [["RES-01", 1], ["RES-02", 1], ["RES-05", 1]], "entrega": "domicilio", "comp": {"img": "comprobante-restaurante", "monto": 80000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M20023757", "fecha": "18 de julio de 2026 a las 08:33 p. m.", "hash": "demo-restaurante-3"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Bandeja paisa y 1 Hamburguesa de la casa y 1 Tres leches por $80.000) Llega en unos 40 minutos 🛵"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Felipe. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Felipe, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["RES-03", 2], ["RES-04", 1]], "entrega": "recoger", "comp": {"img": "comprobante-restaurante", "monto": 80000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M20031676", "fecha": "18 de julio de 2026 a las 08:33 p. m.", "hash": "demo-restaurante-4"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (2 Arepa rellena de pollo y 1 Limonada de coco por $44.000) Estará listo para recoger en 20 minutos."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Mariana. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Mariana, el comprobante es por $80.000 y tu pedido es de $44.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Mariana 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}]}'::jsonb
    when 'veterinaria' then '{"negocio": "Clínica Veterinaria Huellitas", "categorias": ["Consultas y cirugía", "Prevención", "Estética"], "contactos": [["Mariana", "Ruiz", "+573002220001"], ["Julián", "Castro", "+573002220002"], ["Paola", "Díaz", "+573002220003"], ["Camilo", "Torres", "+573002220004"], ["Lucía", "Ramírez", "+573002220005"], ["Andrés", "Cifuentes", "+573002220006"], ["Diana", "Mejía", "+573002220007"], ["Santiago", "Londoño", "+573002220008"], ["Carolina", "Ospina", "+573002220009"], ["Mauricio", "Gil", "+573002220010"], ["Juliana", "Arango", "+573002220011"], ["Ricardo", "Bermúdez", "+573002220012"], ["Manuela", "Parra", "+573002220013"], ["Felipe", "Osorio", "+573002220014"], ["Angélica", "Mora", "+573002220015"], ["Jorge", "Villa", "+573002220016"], ["Natalia", "Cortés", "+573002220017"], ["Oscar", "Franco", "+573002220018"], ["Daniela", "Peña", "+573002220019"], ["Esteban", "Vega", "+573002220020"]], "items": [{"cat": 0, "tipo": "servicio", "sku": "VET-01", "nombre": "Consulta general", "desc": "Examen clínico completo con orientación de tratamiento.", "precio": 60000, "iva": 0, "dur": 30}, {"cat": 1, "tipo": "servicio", "sku": "VET-02", "nombre": "Vacuna múltiple", "desc": "Esquema anual para perros y gatos, con carné actualizado.", "precio": 75000, "iva": 0, "dur": 20}, {"cat": 2, "tipo": "servicio", "sku": "VET-03", "nombre": "Baño y peluquería", "desc": "Baño medicado, corte de pelo y de uñas, limpieza de oídos.", "precio": 55000, "iva": 0, "dur": 90}, {"cat": 1, "tipo": "servicio", "sku": "VET-04", "nombre": "Desparasitación", "desc": "Desparasitante interno y externo según el peso de la mascota.", "precio": 35000, "iva": 0, "dur": 15}, {"cat": 0, "tipo": "servicio", "sku": "VET-05", "nombre": "Esterilización canina", "desc": "Cirugía con anestesia, exámenes previos y control posoperatorio.", "precio": 320000, "iva": 0, "dur": 120}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, mi perro Max tiene las vacunas atrasadas, ¿puedo sacar cita?", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Mariana! 🐶 Para Max tenemos la Vacuna múltiple ($75.000). Hay cupo el jueves a las 10:00 a. m. o a las 3:00 p. m. ¿Cuál te sirve?", "img": 2, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "El jueves a las 10", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Agendado: jueves 10:00 a. m. Para dejar la cita confirmada se paga la vacuna por adelantado: Nequi al 300 416 5923 por $75.000. Envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "Mi gata Luna lleva dos días sin comer y está decaída", "img": null, "comp": null}, {"conv": 1, "emisor": "eli", "texto": "Hola Julián, lamento que Luna esté así 🐱 Dos días sin comer requiere revisión pronta. Te doy cita de Consulta general ($60.000) hoy a las 4:00 p. m.", "img": 1, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "Tengo un cachorro de 3 meses, ¿qué necesita?", "img": null, "comp": null}, {"conv": 2, "emisor": "eli", "texto": "¡Hola Paola, qué ternura! 🐕 A los 3 meses necesita esquema de vacunas y desparasitación ($35.000). Te muestro cómo es.", "img": 4, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "Hola, quiero el baño y peluquería para mi golden", "img": null, "comp": null}, {"conv": 3, "emisor": "eli", "texto": "¡Hola Camilo! Anoto 1 Baño y peluquería. Total $55.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 4, "emisor": "cliente", "texto": "Quiero esterilizar a mi perra, ¿cuánto vale?", "img": null, "comp": null}, {"conv": 4, "emisor": "eli", "texto": "Hola Lucía, la Esterilización canina cuesta $320.000 con exámenes previos, anestesia y control posoperatorio. Agendamos primero una consulta de valoración.", "img": 5, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Ya pagué por Nequi", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Gracias Mariana, envíame la foto del comprobante para validarlo.", "img": null, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 0}, {"conv": 0, "emisor": "eli", "texto": "Recibido ✅ Lo pasé al equipo para validar el monto y confirmarte la cita.", "img": null, "comp": null}, {"conv": 5, "emisor": "cliente", "texto": "Mi perro se comió un chocolate, ¿qué hago?", "img": null, "comp": null}, {"conv": 5, "emisor": "eli", "texto": "Andrés, es una urgencia: llévalo ya a la clínica. Aviso al veterinario de turno para que lo reciba de inmediato. ¿Cuánto pesa y cuánto comió?", "img": null, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "¿Atienden los sábados?", "img": null, "comp": null}, {"conv": 6, "emisor": "eli", "texto": "Hola Diana, sí, los sábados atendemos de 8:00 a. m. a 1:00 p. m. ¿Quieres que te agende una consulta?", "img": null, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 2}, {"conv": 3, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "Hola, necesito desparasitar a mis dos gatos", "img": null, "comp": null}, {"conv": 7, "emisor": "eli", "texto": "¡Hola Santiago! Anoto 2 Desparasitación. Total $70.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "¿Tienen servicio de peluquería para un schnauzer?", "img": null, "comp": null}, {"conv": 8, "emisor": "eli", "texto": "Claro, Carolina 🐾 El Baño y peluquería ($55.000) incluye corte de raza. Hay cupo mañana a las 9:00 a. m.", "img": 3, "comp": null}, {"conv": 9, "emisor": "cliente", "texto": "Mi perro cojea desde ayer", "img": null, "comp": null}, {"conv": 9, "emisor": "eli", "texto": "Hola Mauricio, conviene que lo vea el veterinario pronto. Te agendo una Consulta general ($60.000) hoy o mañana a primera hora. ¿Cuál prefieres?", "img": 1, "comp": null}, {"conv": 10, "emisor": "cliente", "texto": "¿A qué edad se esteriliza una gata?", "img": null, "comp": null}, {"conv": 10, "emisor": "eli", "texto": "Hola Juliana, normalmente desde los 6 meses, según su peso y salud. Lo ideal es una consulta para valorarla antes de agendar.", "img": null, "comp": null}, {"conv": 11, "emisor": "cliente", "texto": "Quiero cancelar la cita de hoy", "img": null, "comp": null}, {"conv": 11, "emisor": "eli", "texto": "Listo Ricardo, ¿me confirmas el nombre de la mascota? Cancelo la cita y te ofrezco otra fecha cuando quieras.", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 3}, {"conv": 7, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 12, "emisor": "cliente", "texto": "¿Cuánto cuesta la consulta?", "img": null, "comp": null}, {"conv": 12, "emisor": "eli", "texto": "Hola Manuela, la Consulta general cuesta $60.000. Aquí te muestro el servicio.", "img": 1, "comp": null}, {"conv": 13, "emisor": "cliente", "texto": "¿Atienden urgencias en la noche?", "img": null, "comp": null}, {"conv": 13, "emisor": "eli", "texto": "Hola Felipe, las urgencias las atendemos hasta las 10:00 p. m. Pasada esa hora te recomiendo una clínica 24 horas; si quieres te paso la dirección.", "img": null, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "Hola, quiero la vacuna múltiple para mi gata Nina", "img": null, "comp": null}, {"conv": 14, "emisor": "eli", "texto": "¡Hola Angélica! Anoto 1 Vacuna múltiple. Total $75.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 15, "emisor": "cliente", "texto": "¿Tienen guardería para perros?", "img": null, "comp": null}, {"conv": 15, "emisor": "eli", "texto": "Hola Jorge, por ahora no ofrecemos guardería, pero sí consulta, vacunas, baño y cirugías. ¿Te ayudo con alguno?", "img": null, "comp": null}, {"conv": 16, "emisor": "cliente", "texto": "Mi cachorro tiene diarrea hace 2 días", "img": null, "comp": null}, {"conv": 16, "emisor": "eli", "texto": "Hola Natalia, en cachorros la diarrea puede deshidratar rápido. Te agendo una Consulta general ($60.000) hoy mismo y aviso al veterinario.", "img": 1, "comp": null}, {"conv": 17, "emisor": "cliente", "texto": "¿Cómo es el procedimiento de la esterilización?", "img": null, "comp": null}, {"conv": 17, "emisor": "eli", "texto": "Hola Óscar, se hace con anestesia y exámenes previos; la mascota sale el mismo día con indicaciones de cuidado. Te muestro el servicio.", "img": 5, "comp": null}, {"conv": 18, "emisor": "cliente", "texto": "¿Puedo llevar a mi mascota sin cita?", "img": null, "comp": null}, {"conv": 18, "emisor": "eli", "texto": "Hola Daniela, para urgencias sí; para consultas de rutina es mejor agendar y así no esperas. ¿Te busco un cupo?", "img": null, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 1}, {"conv": 14, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 19, "emisor": "cliente", "texto": "Gracias por atender tan rápido a Luna 🐱", "img": null, "comp": null}, {"conv": 19, "emisor": "eli", "texto": "¡Gracias a ti, Esteban! Nos alegra que Luna esté mejor. Cualquier duda, aquí estoy.", "img": null, "comp": null}], "recursos": [["consultorio", "Consultorio 1", 1]], "efectos": [{"reserva": "cita", "h": 16, "personas": 1, "recurso": "Consultorio 1", "urgente": true, "tras": 5}, {"escalar": "Posible urgencia: cachorro con diarrea de 2 días", "resumen": "Cachorro con diarrea hace 2 días: riesgo de deshidratación; Eli agendó consulta y pide valoración del veterinario.", "tras": 45}], "agenda": [[0, 17.5, 2, "cita", 1, "Consultorio 1", "confirmada", false], [1, 9, 5, "cita", 1, "Consultorio 1", "confirmada", true], [1, 15, 9, "cita", 1, "Consultorio 1", "confirmada", false], [2, 10, 10, "cita", 1, "Consultorio 1", "confirmada", false], [3, 16, 12, "cita", 1, "Consultorio 1", "pendiente_pago", false], [4, 11, 13, "cita", 1, "Consultorio 1", "confirmada", false], [6, 9.5, 15, "cita", 1, "Consultorio 1", "confirmada", false], [7, 14, 17, "cita", 1, "Consultorio 1", "confirmada", false], [9, 10, 18, "cita", 1, "Consultorio 1", "confirmada", false], [10, 15.5, 19, "cita", 1, "Consultorio 1", "pendiente_pago", false]], "pagos": [{"items": [["VET-02", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-veterinaria", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M19936704", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-veterinaria-1"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ La cita de Max quedó confirmada para el jueves a las 10:00 a. m. (orden #{orden}). Trae su carné de vacunación."}, {"emisor": "cliente", "texto": "Perfecto, ahí estaremos"}, {"emisor": "eli", "texto": "Los esperamos, Mariana. ¡Un abrazo a Max! 🐾"}], "rechazado": [{"emisor": "eli", "texto": "Mariana, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["VET-02", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-veterinaria", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M20015838", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-veterinaria-2"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Vacuna múltiple por $75.000) Quedó agendada para mañana a las 9:00 a. m. Trae su carné."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Angélica. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Angélica, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["VET-03", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-veterinaria", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M20023757", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-veterinaria-3"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Baño y peluquería por $55.000) Quedó agendado para mañana a las 11:00 a. m."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Camilo. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Camilo, el comprobante es por $75.000 y tu pedido es de $55.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Camilo 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}, {"items": [["VET-04", 2]], "entrega": "no_aplica", "comp": {"img": "comprobante-veterinaria", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M20031676", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-veterinaria-4"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (2 Desparasitación por $70.000) Quedó agendado para mañana a las 2:00 p. m."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Santiago. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Santiago, el comprobante es por $75.000 y tu pedido es de $70.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Santiago 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}]}'::jsonb
    when 'aerolinea' then '{"negocio": "Aerolínea Cóndor Andino", "categorias": ["Tarifas", "Servicios adicionales"], "contactos": [["Sergio", "Molina", "+573003330001"], ["Daniela", "Vargas", "+573003330002"], ["Carlos", "Núñez", "+573003330003"], ["Laura", "Cárdenas", "+573003330004"], ["Andrés", "Rojas", "+573003330005"], ["Paula", "Medina", "+573003330006"], ["Julián", "Pardo", "+573003330007"], ["Camila", "Soto", "+573003330008"], ["Felipe", "Gómez", "+573003330009"], ["Valeria", "Sánchez", "+573003330010"], ["Mateo", "Arias", "+573003330011"], ["Sara", "Londoño", "+573003330012"], ["Nicolás", "Ibarra", "+573003330013"], ["Isabella", "Rey", "+573003330014"], ["David", "Correa", "+573003330015"], ["Luisa", "Bernal", "+573003330016"], ["Diego", "Vásquez", "+573003330017"], ["Mónica", "Pacheco", "+573003330018"], ["Alejandro", "Ríos", "+573003330019"], ["Juliana", "Cano", "+573003330020"]], "items": [{"cat": 0, "tipo": "tarifa", "sku": "AER-01", "nombre": "Bogotá – Medellín (Light)", "desc": "Solo equipaje de mano. Sin cambios ni devolución.", "precio": 189000, "iva": 0, "dur": null}, {"cat": 0, "tipo": "tarifa", "sku": "AER-02", "nombre": "Bogotá – Cartagena (Flex)", "desc": "Maleta de 23 kg incluida y un cambio de fecha sin costo.", "precio": 275000, "iva": 0, "dur": null}, {"cat": 0, "tipo": "tarifa", "sku": "AER-03", "nombre": "Bogotá – San Andrés (Promo)", "desc": "Tarifa promocional con equipaje de mano, cupos limitados.", "precio": 415000, "iva": 0, "dur": null}, {"cat": 1, "tipo": "adicional", "sku": "AER-04", "nombre": "Maleta de bodega 23 kg", "desc": "Equipaje adicional para tu vuelo.", "precio": 85000, "iva": 0, "dur": null}, {"cat": 1, "tipo": "adicional", "sku": "AER-05", "nombre": "Selección de asiento", "desc": "Elige ventana o pasillo antes del check-in.", "precio": 25000, "iva": 0, "dur": null}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, necesito un vuelo Bogotá–Cartagena el 20 de diciembre, con maleta", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Sergio! ✈️ El 20 de diciembre a Cartagena tengo la tarifa Flex en $275.000 (cambio de fecha sin costo). La Maleta de bodega de 23 kg son $85.000. Total $360.000. ¿Te reservo?", "img": 2, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Sí, a nombre de Sergio Molina, cédula 1.020.345.678", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Reservado ✅ Tu reserva se mantiene 24 horas. Paga $360.000 por DaviPlata o Nequi al 300 416 5923 y envíame el comprobante para emitir el tiquete.", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "Hola, quiero el vuelo a Cartagena del 20 de diciembre con maleta", "img": null, "comp": null}, {"conv": 1, "emisor": "eli", "texto": "¡Hola Daniela! Anoto 1 Bogotá – Cartagena (Flex) y 1 Maleta de bodega 23 kg. Total $360.000. Para confirmarlo paga por Nequi al 300 416 5923 o DaviPlata y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "Hola, quiero la tarifa promo a San Andrés en enero", "img": null, "comp": null}, {"conv": 2, "emisor": "eli", "texto": "¡Hola Carlos! Anoto 1 Bogotá – San Andrés (Promo). Total $415.000. Para confirmarlo paga por Nequi al 300 416 5923 o DaviPlata y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "¿Cuánto cuesta agregar una maleta?", "img": null, "comp": null}, {"conv": 3, "emisor": "eli", "texto": "Hola Laura, la Maleta de bodega de 23 kg cuesta $85.000 por trayecto si la agregas antes del viaje.", "img": 4, "comp": null}, {"conv": 4, "emisor": "cliente", "texto": "Quiero elegir asiento de ventana", "img": null, "comp": null}, {"conv": 4, "emisor": "eli", "texto": "Claro, Andrés. La Selección de asiento cuesta $25.000 y puedes elegir ventana o pasillo antes del check-in.", "img": 5, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Ya hice el pago por DaviPlata", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Gracias Sergio, envíame la foto del comprobante para validarlo.", "img": null, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "📎 Comprobante de pago DaviPlata", "img": null, "comp": 0}, {"conv": 0, "emisor": "eli", "texto": "Recibido ✅ Lo pasé al equipo para validar el monto y emitir tu tiquete.", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "📎 Comprobante de pago DaviPlata", "img": null, "comp": 1}, {"conv": 1, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "📎 Comprobante de pago DaviPlata", "img": null, "comp": 3}, {"conv": 2, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 5, "emisor": "cliente", "texto": "¿Puedo cambiar la fecha de mi vuelo?", "img": null, "comp": null}, {"conv": 5, "emisor": "eli", "texto": "Hola Paula, con la tarifa Flex tienes un cambio de fecha sin costo; con Light no hay cambios. ¿Qué tarifa compraste?", "img": 2, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "Hola, necesito 3 tiquetes Bogotá–Medellín para el viernes", "img": null, "comp": null}, {"conv": 6, "emisor": "eli", "texto": "¡Hola Julián! Anoto 3 Bogotá – Medellín (Light). Total $567.000. Para confirmarlo paga por Nequi al 300 416 5923 o DaviPlata y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "¿Cuánto equipaje puedo llevar en la tarifa Light?", "img": null, "comp": null}, {"conv": 7, "emisor": "eli", "texto": "Hola Camila, la tarifa Light incluye solo equipaje de mano. Si necesitas maleta puedes agregarla por $85.000.", "img": 4, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "Mi cédula es 1.020.345.678, ¿ya quedó mi reserva?", "img": null, "comp": null}, {"conv": 8, "emisor": "eli", "texto": "Gracias Felipe. Tu reserva se mantiene por 24 horas mientras envías el comprobante de pago.", "img": null, "comp": null}, {"conv": 9, "emisor": "cliente", "texto": "¿Cómo pago el tiquete?", "img": null, "comp": null}, {"conv": 9, "emisor": "eli", "texto": "Hola Valeria, pagas por consignación o transferencia y envías la foto del comprobante; una persona verifica el monto y emitimos el tiquete.", "img": null, "comp": null}, {"conv": 10, "emisor": "cliente", "texto": "¿Puedo viajar con un menor de edad solo?", "img": null, "comp": null}, {"conv": 10, "emisor": "eli", "texto": "Hola Mateo, los menores de 12 años viajan con un adulto; entre 12 y 17 años se requiere permiso notarial. Si necesitas más detalle te paso con una persona del equipo.", "img": null, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "📎 Comprobante de pago DaviPlata", "img": null, "comp": 2}, {"conv": 6, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 11, "emisor": "cliente", "texto": "¿Hay vuelos a Cartagena en diciembre con maleta incluida?", "img": null, "comp": null}, {"conv": 11, "emisor": "eli", "texto": "Sí, Sara: la tarifa Flex a Cartagena ($275.000) incluye maleta de 23 kg. ¿Qué fechas tienes?", "img": 2, "comp": null}, {"conv": 12, "emisor": "cliente", "texto": "Quiero cancelar mi vuelo", "img": null, "comp": null}, {"conv": 12, "emisor": "eli", "texto": "Hola Nicolás, ¿me confirmas tu código de reserva? Reviso las condiciones de tu tarifa: Light no tiene devolución y Flex permite un cambio de fecha.", "img": null, "comp": null}, {"conv": 13, "emisor": "cliente", "texto": "¿A qué hora sale el vuelo a San Andrés?", "img": null, "comp": null}, {"conv": 13, "emisor": "eli", "texto": "Hola Isabella, el vuelo a San Andrés sale a las 6:30 a. m. y llega a las 8:20 a. m. Aquí te muestro la tarifa Promo.", "img": 3, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "¿Puedo viajar con mi mascota?", "img": null, "comp": null}, {"conv": 14, "emisor": "eli", "texto": "Hola David, aceptamos mascotas pequeñas en cabina con guacal y certificado. Te paso con una persona del equipo para confirmar requisitos.", "img": null, "comp": null}, {"conv": 15, "emisor": "cliente", "texto": "Somos 2 adultos y un niño de 5 años", "img": null, "comp": null}, {"conv": 15, "emisor": "eli", "texto": "Hola Luisa, el niño paga tarifa completa si ocupa asiento. Para 3 pasajeros en Light a Medellín serían $567.000. ¿Fecha de viaje?", "img": 1, "comp": null}, {"conv": 16, "emisor": "cliente", "texto": "¿Cuánto cuesta la maleta de bodega para San Andrés?", "img": null, "comp": null}, {"conv": 16, "emisor": "eli", "texto": "Hola Diego, la Maleta de bodega de 23 kg cuesta $85.000 por trayecto.", "img": 4, "comp": null}, {"conv": 17, "emisor": "cliente", "texto": "Quiero que mi asiento quede junto a mi esposo", "img": null, "comp": null}, {"conv": 17, "emisor": "eli", "texto": "Claro, Mónica. Con la Selección de asiento ($25.000 c/u) eligen asientos contiguos antes del check-in. Tu vuelo de hoy sale a las 6:30 p. m.", "img": 5, "comp": null}, {"conv": 18, "emisor": "cliente", "texto": "Perdí mi tiquete, ¿me lo reenvían?", "img": null, "comp": null}, {"conv": 18, "emisor": "eli", "texto": "Hola Alejandro, claro. Te lo reenvío por este chat; ¿me confirmas tu número de documento para ubicarlo?", "img": null, "comp": null}, {"conv": 19, "emisor": "cliente", "texto": "Gracias, excelente servicio ✈️", "img": null, "comp": null}, {"conv": 19, "emisor": "eli", "texto": "¡Gracias a ti, Juliana! Buen viaje y aquí estamos para lo que necesites.", "img": null, "comp": null}], "recursos": [["otro", "Vuelo BOG–MDE 6:30 p. m.", 180]], "efectos": [{"escalar": "Reenvío de tiquete: validar documento de identidad", "resumen": "Alejandro perdió su tiquete; Eli pidió el documento y requiere validación humana antes de reenviarlo.", "tras": 52}, {"reserva": "vuelo", "h": 18.5, "personas": 2, "recurso": "Vuelo BOG–MDE 6:30 p. m.", "tras": 50}], "agenda": [[0, 21, 3, "vuelo", 1, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [1, 18.5, 4, "vuelo", 2, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [2, 7, 5, "vuelo", 3, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [3, 18.5, 8, "vuelo", 1, "Vuelo BOG–MDE 6:30 p. m.", "pendiente_pago", false], [5, 7, 9, "vuelo", 2, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [6, 18.5, 10, "vuelo", 1, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [8, 7, 12, "vuelo", 4, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [10, 18.5, 13, "vuelo", 1, "Vuelo BOG–MDE 6:30 p. m.", "pendiente_pago", false]], "pagos": [{"items": [["AER-02", 1], ["AER-04", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-aerolinea", "monto": 360000, "destinatario": "Luis Fernando Rodríguez Sandoval", "app": "DaviPlata", "ref": "948312", "fecha": "Julio 09 de 2026 - 05:39 p. m.", "hash": "demo-aerolinea-1"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu tiquete Bogotá–Cartagena del 20 de diciembre quedó emitido (orden #{orden}). Te lo envío por este chat. ¡Buen viaje!"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "A ti, Sergio. ¡Que tengas un excelente vuelo! ✈️"}], "rechazado": [{"emisor": "eli", "texto": "Sergio, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["AER-02", 1], ["AER-04", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-aerolinea", "monto": 360000, "destinatario": "Luis Fernando Rodríguez Sandoval", "app": "DaviPlata", "ref": "948622", "fecha": "Julio 09 de 2026 - 05:39 p. m.", "hash": "demo-aerolinea-2"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Bogotá – Cartagena (Flex) y 1 Maleta de bodega 23 kg por $360.000) Tu tiquete quedó emitido y te lo envío por este chat."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Daniela. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Daniela, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["AER-01", 3]], "entrega": "no_aplica", "comp": {"img": "comprobante-aerolinea", "monto": 360000, "destinatario": "Luis Fernando Rodríguez Sandoval", "app": "DaviPlata", "ref": "948933", "fecha": "Julio 09 de 2026 - 05:39 p. m.", "hash": "demo-aerolinea-3"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (3 Bogotá – Medellín (Light) por $567.000) Tus tiquetes quedaron emitidos."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Julián. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Julián, el comprobante es por $360.000 y tu pedido es de $567.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Julián 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}, {"items": [["AER-03", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-aerolinea", "monto": 360000, "destinatario": "Luis Fernando Rodríguez Sandoval", "app": "DaviPlata", "ref": "949244", "fecha": "Julio 09 de 2026 - 05:39 p. m.", "hash": "demo-aerolinea-4"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Bogotá – San Andrés (Promo) por $415.000) Tu tiquete quedó emitido."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Carlos. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Carlos, el comprobante es por $360.000 y tu pedido es de $415.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Carlos 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}]}'::jsonb
  end;
$$;

-- Los negocios de prueba son borrables en bloque: se permite borrar sus pagos aprobados (RN-C12 sigue vigente en el resto)
create or replace function app.proteger_pago()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.estado = 'aprobado' and not (tg_op = 'DELETE' and exists (
        select 1 from platform.tenants t where t.id = old.tenant_id and t.slug like 'demo-%')) then
    raise exception 'RN-C12: un pago aprobado no se modifica; registre un reverso' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- El revisor ve la foto del comprobante y a qué conversación pertenece
create or replace view elius.v_comprobantes_pendientes with (security_invoker = true) as
select cp.tenant_id, cp.id as comprobante_id, cp.creado_en, cp.monto_leido, cp.monto_esperado, cp.coincide,
       cp.app_origen, cp.referencia, cp.destinatario, cp.motivo,
       coalesce(cp.motivo like 'ALERTA:%', false) as tiene_alerta,
       o.numero as orden_numero, c.nombres as cliente,
       cp.url_archivo, cp.conversacion_id
from elius.comprobantes_pago cp
join elius.conversaciones cv on cv.tenant_id = cp.tenant_id and cv.id = cp.conversacion_id
join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
join elius.contactos c on c.tenant_id = i.tenant_id and c.id = i.contacto_id
left join elius.ordenes o on o.tenant_id = cp.tenant_id and o.id = cp.orden_id
where cp.veredicto = 'pendiente';

-- Borra lo sembrado (clientes, chats, órdenes y comprobantes) y deja el caso listo desde cero
create or replace function elius.limpiar_caso_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from elius.pagos where tenant_id = p_tenant;
  delete from elius.comprobantes_pago where tenant_id = p_tenant;
  delete from elius.entregas where tenant_id = p_tenant;
  delete from elius.ordenes where tenant_id = p_tenant;
  delete from elius.asignaciones_recurso where tenant_id = p_tenant;
  delete from elius.reservas where tenant_id = p_tenant;
  delete from elius.escalamientos where tenant_id = p_tenant;
  delete from elius.consumos_llm where tenant_id = p_tenant;
  delete from elius.asignaciones_recurso where tenant_id = p_tenant;
  delete from elius.reservas where tenant_id = p_tenant;
  delete from elius.escalamientos where tenant_id = p_tenant;
  delete from elius.consumos_llm where tenant_id = p_tenant;
  delete from elius.contactos where tenant_id = p_tenant;   -- cascada: identidades, conversaciones y mensajes
  delete from elius.parametros_negocio where tenant_id = p_tenant and clave like 'demo\_%';
end $$;

-- Crea los clientes del caso (uno por conversación) y deja el catálogo con los datos actuales
create or replace function elius.sembrar_clientes_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_canal uuid; v_contacto uuid; v_ident uuid; r jsonb; v_ini timestamptz; v_res uuid;
begin
  select id into v_canal from elius.canales where tenant_id = p_tenant order by creado_en limit 1;
  perform elius.limpiar_caso_demo(p_tenant);
  for r in select * from jsonb_array_elements(v_d->'items') loop
    update elius.items_catalogo set nombre = r->>'nombre', descripcion = r->>'desc', precio = (r->>'precio')::numeric,
           impuesto_pct = (r->>'iva')::numeric, disponible = true
    where tenant_id = p_tenant and sku = r->>'sku';
  end loop;
  for r in select * from jsonb_array_elements(v_d->'recursos') loop
    insert into elius.recursos (tenant_id, tipo, nombre, capacidad)
    select p_tenant, r->>0, r->>1, (r->>2)::int
    where not exists (select 1 from elius.recursos where tenant_id = p_tenant and nombre = r->>1);
  end loop;
  for r in select * from jsonb_array_elements(v_d->'contactos') loop
    insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen)
    values (p_tenant, r->>0, r->>1, r->>2, 'whatsapp') returning id into v_contacto;
    insert into elius.identidades_contacto (tenant_id, contacto_id, canal_id, id_externo, nombre_en_canal)
    values (p_tenant, v_contacto, v_canal, r->>2, (r->>0) || ' ' || (r->>1)) returning id into v_ident;
    insert into elius.conversaciones (tenant_id, identidad_id, flujo) values (p_tenant, v_ident, 'general');
  end loop;
  for r in select * from jsonb_array_elements(v_d->'agenda') loop
    select c.id into v_contacto from elius.contactos c where c.tenant_id = p_tenant
    order by c.telefono offset (r->>2)::int limit 1;
    v_ini := greatest(((date_trunc('day', now() at time zone 'America/Bogota') + (r->>0)::int * interval '1 day' + ((r->>1)::numeric * interval '1 hour')) at time zone 'America/Bogota'), now() + interval '10 minutes');
    insert into elius.reservas (tenant_id, contacto_id, codigo, tipo, estado, inicio, fin, personas, urgente, creada_por_eli)
    values (p_tenant, v_contacto, 'R-' || upper(substr(md5(random()::text), 1, 5)), r->>3, r->>6, v_ini, v_ini + interval '1 hour',
            (r->>4)::int, (r->>7)::boolean, true) returning id into v_res;
    begin
      insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
      select p_tenant, v_res, rc.id, v_ini, v_ini + interval '1 hour' from elius.recursos rc where rc.tenant_id = p_tenant and rc.nombre = r->>5;
    exception when exclusion_violation then null;
    end;
  end loop;
  insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion) values
    (p_tenant, 'demo_indice', '0', 'numero', 'Mensajes de prueba ya entregados (caso de demostración)'),
    (p_tenant, 'demo_version', '5', 'texto', 'Versión del guion sembrado');
end $$;

-- Crea (o reutiliza) el negocio de prueba del caso para el usuario que llama y lo deja activo
create or replace function platform.cargar_caso_demo(p_vertical text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_slug text;
  v_tenant uuid; v_agente uuid; v_canal uuid;
  v_cats uuid[] := '{}'; v_cat uuid; v_item uuid;
  r jsonb; k int;
begin
  if v_uid is null then raise exception 'Debe iniciar sesión' using errcode = '42501'; end if;
  if v_d is null then raise exception 'Caso desconocido: %', p_vertical; end if;
  v_slug := 'demo-' || p_vertical || '-' || substr(replace(v_uid::text, '-', ''), 1, 6);

  select id into v_tenant from platform.tenants where slug = v_slug;
  if v_tenant is not null then
    -- si quedó de una versión anterior del caso, se vuelve a sembrar
    if coalesce((select valor from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_version'), '') <> '5' then
      perform elius.sembrar_clientes_demo(v_tenant, p_vertical);
    end if;
    perform platform.cambiar_tenant(v_tenant);
    return v_tenant;
  end if;

  v_tenant := platform.crear_tenant(v_d->>'negocio', v_slug, p_vertical);
  select id into v_agente from elius.agentes where tenant_id = v_tenant limit 1;
  insert into elius.canales (tenant_id, agente_id, tipo, nombre, identificador_externo)
  values (v_tenant, v_agente, 'whatsapp', 'WhatsApp de prueba', 'demo-' || v_slug) returning id into v_canal;

  for r in select * from jsonb_array_elements(v_d->'categorias') loop
    insert into elius.categorias_catalogo (tenant_id, nombre, orden)
    values (v_tenant, r #>> '{}', coalesce(array_length(v_cats, 1), 0)) returning id into v_cat;
    v_cats := v_cats || v_cat;
  end loop;

  k := 0;
  for r in select * from jsonb_array_elements(v_d->'items') loop
    k := k + 1;
    insert into elius.items_catalogo (tenant_id, categoria_id, tipo, sku, nombre, descripcion, precio, impuesto_pct, duracion_min)
    values (v_tenant, v_cats[(r->>'cat')::int + 1], r->>'tipo', r->>'sku', r->>'nombre', r->>'desc',
            (r->>'precio')::numeric, (r->>'iva')::numeric, nullif(r->>'dur', '')::int)
    returning id into v_item;
    insert into elius.medios_item (tenant_id, item_id, tipo_archivo, url, descripcion, orden)
    values (v_tenant, v_item, 'foto', '/demo/' || p_vertical || '-' || k || '.svg', r->>'nombre', 0);
  end loop;

  perform elius.sembrar_clientes_demo(v_tenant, p_vertical);
  perform platform.cambiar_tenant(v_tenant);
  return v_tenant;
end $$;

-- Lo que Eli deja registrado al responder: consumo de IA y, según el guion, un caso pendiente o una reserva de hoy
create or replace function elius.efectos_demo(p_tenant uuid, p_conv uuid, p_msg uuid, p_texto text, p_efectos jsonb, p_tras int)
returns void language plpgsql security definer set search_path = '' as $$
declare e jsonb; v_contacto uuid; v_reserva uuid; v_recurso uuid; v_ini timestamptz;
begin
  insert into elius.consumos_llm (tenant_id, conversacion_id, mensaje_id, proveedor, modelo, tokens_entrada, tokens_salida, tokens_cache, costo_usd, latencia_ms)
  values (p_tenant, p_conv, p_msg, 'anthropic', 'claude-sonnet-5-5', 900 + length(p_texto) * 2, 40 + length(p_texto) / 3, 600,
          round((0.0009 + length(p_texto) * 0.000004)::numeric, 6), 900 + (length(p_texto) * 7) % 1400);
  for e in select * from jsonb_array_elements(coalesce(p_efectos, '[]'::jsonb)) where (value->>'tras')::int = p_tras loop
    if e ? 'escalar' then
      insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
      values (p_tenant, p_conv, e->>'escalar',
              (select m.contenido from elius.mensajes m where m.tenant_id = p_tenant and m.conversacion_id = p_conv and m.emisor = 'cliente' order by m.creado_en desc limit 1),
              e->>'resumen');
    elsif e ? 'reserva' then
      select i.contacto_id into v_contacto from elius.conversaciones c
      join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
      where c.tenant_id = p_tenant and c.id = p_conv;
      v_ini := greatest(((date_trunc('day', now() at time zone 'America/Bogota') + ((e->>'h')::numeric * interval '1 hour')) at time zone 'America/Bogota'), now() + interval '10 minutes');
      insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, urgente, creada_por_eli)
      values (p_tenant, v_contacto, p_conv, 'R-' || upper(substr(md5(random()::text), 1, 5)), e->>'reserva', 'confirmada',
              v_ini, v_ini + interval '1 hour', coalesce((e->>'personas')::int, 1), coalesce((e->>'urgente')::boolean, false), true)
      returning id into v_reserva;
      select id into v_recurso from elius.recursos where tenant_id = p_tenant and nombre = e->>'recurso';
      if v_recurso is not null then
        begin
          insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
          values (p_tenant, v_reserva, v_recurso, v_ini, v_ini + interval '1 hour');
        exception when exclusion_violation then null;   -- el recurso ya estaba ocupado a esa hora: la reserva queda sin recurso
        end;
      end if;
    end if;
  end loop;
end $$;

-- Cuántos comprobantes de la prueba esperan decisión y cuántos mensajes posteriores faltan por entregar
create or replace function elius.estado_demo(p_tenant uuid, p_d jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_pidx int; v_esperando int := 0; v_post int := 0; v_ver text; v_k int; v_p jsonb;
begin
  for v_pidx in 0 .. coalesce(jsonb_array_length(p_d->'pagos'), 0) - 1 loop
    v_p := p_d->'pagos'->v_pidx;
    select cp.veredicto into v_ver from elius.comprobantes_pago cp
    where cp.tenant_id = p_tenant and cp.media_id = 'demo-' || v_pidx order by cp.creado_en desc limit 1;
    if v_ver = 'pendiente' then
      v_esperando := v_esperando + 1;
    elsif v_ver in ('aprobado', 'rechazado') then
      select coalesce(valor::int, 0) into v_k from elius.parametros_negocio where tenant_id = p_tenant and clave = 'demo_post_' || v_pidx;
      if coalesce(v_k, 0) < jsonb_array_length(v_p->v_ver) then v_post := v_post + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('esperando', v_esperando, 'post', v_post);
end $$;

-- Entrega el siguiente mensaje del guion. El panel lo llama cada pocos segundos.
-- 1) Si quien revisa ya decidió un comprobante, Eli continúa esa conversación (antes que lo demás).
-- 2) Si no, llega el siguiente mensaje de la cola; el comprobante se registra al enviarlo el cliente.
-- Si una persona tomó la conversación, Eli no responde en ella (RN-C19) y se salta ese mensaje.
create or replace function elius.siguiente_mensaje_demo()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_vertical text; v_slug text; v_d jsonb; v_guion jsonb; v_pagos jsonb; v_i int; v_total int;
  v_g jsonb; v_conv uuid; v_estado text; v_texto text; v_k int; v_p jsonb; v_pidx int;
  v_ver text; v_orden uuid; v_contacto uuid; v_esperado numeric; v_url text; v_it jsonb; v_emisor text;
  v_est jsonb; v_clientes int; v_fin boolean; v_tipo text; v_dir uuid; v_mid uuid;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  select slug, vertical into v_slug, v_vertical from platform.tenants where id = v_tenant;
  if v_slug not like 'demo-%' then raise exception 'Este negocio no es un caso de prueba'; end if;
  v_d := elius.datos_caso_demo(v_vertical);
  v_guion := v_d->'guion'; v_pagos := coalesce(v_d->'pagos', '[]'::jsonb); v_total := jsonb_array_length(v_guion);
  select valor::int into v_i from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_indice';

  -- 1) continuar las conversaciones cuyo comprobante ya fue decidido
  for v_pidx in 0 .. jsonb_array_length(v_pagos) - 1 loop
    v_p := v_pagos->v_pidx;
    select cp.veredicto, cp.conversacion_id, cp.orden_id into v_ver, v_conv, v_orden
    from elius.comprobantes_pago cp where cp.tenant_id = v_tenant and cp.media_id = 'demo-' || v_pidx
    order by cp.creado_en desc limit 1;
    continue when v_ver is null or v_ver = 'pendiente';
    select coalesce(valor::int, 0) into v_k from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_post_' || v_pidx;
    v_k := coalesce(v_k, 0);
    if v_k < jsonb_array_length(v_p->v_ver) then
      v_g := (v_p->v_ver)->v_k;
      v_emisor := v_g->>'emisor';
      v_texto := replace(v_g->>'texto', '{orden}', coalesce((select numero::text from elius.ordenes where tenant_id = v_tenant and id = v_orden), ''));
      select estado into v_estado from elius.conversaciones where tenant_id = v_tenant and id = v_conv;
      if not (v_emisor = 'eli' and v_estado in ('humano', 'pausa')) then
        insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, estado_entrega, procesado)
        values (v_tenant, v_conv, v_emisor, 'texto', v_texto, case when v_emisor = 'cliente' then 'recibido' else 'entregado' end, true)
        returning id into v_mid;
        if v_emisor = 'eli' then perform elius.efectos_demo(v_tenant, v_conv, v_mid, v_texto, null, -1); end if;
      end if;
      insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion)
      values (v_tenant, 'demo_post_' || v_pidx, (v_k + 1)::text, 'numero', 'Mensajes posteriores a la decisión ya entregados')
      on conflict (tenant_id, clave) do update set valor = (v_k + 1)::text;
      v_est := elius.estado_demo(v_tenant, v_d);
      select count(distinct conversacion_id) into v_clientes from elius.mensajes where tenant_id = v_tenant and emisor = 'cliente';
      return jsonb_build_object('terminado', v_i >= v_total and (v_est->>'esperando')::int = 0 and (v_est->>'post')::int = 0,
        'indice', v_i, 'total', v_total, 'emisor', v_emisor, 'conversacion_id', v_conv, 'clientes', v_clientes,
        'esperando', (v_est->>'esperando')::int, 'decision', v_ver);
    end if;
  end loop;

  -- 2) siguiente mensaje de la cola principal
  loop
    exit when v_i >= v_total;
    v_g := v_guion -> v_i;
    select c.id, c.estado into v_conv, v_estado
    from elius.conversaciones c
    join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
    where c.tenant_id = v_tenant order by i.id_externo offset (v_g->>'conv')::int limit 1;
    exit when not (v_g->>'emisor' = 'eli' and v_estado in ('humano', 'pausa'));
    v_i := v_i + 1;
  end loop;

  if v_i < v_total then
    v_texto := v_g->>'texto';
    v_url := case when (v_g->>'img') is not null then '/demo/' || v_vertical || '-' || (v_g->>'img') || '.svg' end;
    v_tipo := case when v_texto like '📎%' or v_url is not null then 'imagen' else 'texto' end;

    if (v_g->>'comp') is not null then
      -- el cliente envía el comprobante: se crea su orden y el comprobante queda pendiente de revisión
      v_pidx := (v_g->>'comp')::int; v_p := v_pagos->v_pidx;
      v_url := '/demo/' || (v_p->'comp'->>'img') || '.jpg';
      select i.contacto_id into v_contacto from elius.conversaciones c
      join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
      where c.tenant_id = v_tenant and c.id = v_conv;
      if v_p->>'entrega' = 'domicilio' then
        insert into elius.direcciones (tenant_id, contacto_id, etiqueta, direccion, ciudad, es_principal)
        values (v_tenant, v_contacto, 'Casa', 'Calle 45 # 12-30', 'Bogotá', true) returning id into v_dir;
      else v_dir := null; end if;
      insert into elius.ordenes (tenant_id, contacto_id, conversacion_id, canal_venta, tipo_entrega, direccion_entrega_id)
      values (v_tenant, v_contacto, v_conv, 'whatsapp', v_p->>'entrega', v_dir) returning id into v_orden;
      for v_it in select * from jsonb_array_elements(v_p->'items') loop
        insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad)
        select v_tenant, v_orden, it.id, (v_it->>1)::numeric from elius.items_catalogo it
        where it.tenant_id = v_tenant and it.sku = (v_it->>0);
      end loop;
      update elius.ordenes set estado = 'esperando_pago' where tenant_id = v_tenant and id = v_orden;
      select saldo_pendiente into v_esperado from elius.v_saldo_ordenes where tenant_id = v_tenant and orden_id = v_orden;
      insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, destinatario,
                                           app_origen, referencia, fecha_texto, hash_archivo, url_archivo, media_id)
      values (v_tenant, v_orden, v_conv, (v_p->'comp'->>'monto')::numeric, v_esperado, v_p->'comp'->>'destinatario',
              v_p->'comp'->>'app', v_p->'comp'->>'ref', v_p->'comp'->>'fecha', v_p->'comp'->>'hash', v_url, 'demo-' || v_pidx);
      v_tipo := 'imagen';
    end if;

    insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, url_adjunto, estado_entrega, procesado)
    values (v_tenant, v_conv, v_g->>'emisor', v_tipo, v_texto, v_url,
            case when v_g->>'emisor' = 'cliente' then 'recibido' else 'entregado' end, true)
    returning id into v_mid;
    if v_g->>'emisor' = 'eli' then perform elius.efectos_demo(v_tenant, v_conv, v_mid, v_texto, v_d->'efectos', v_i); end if;
    v_i := v_i + 1;
    update elius.parametros_negocio set valor = v_i::text where tenant_id = v_tenant and clave = 'demo_indice';
    v_emisor := v_g->>'emisor';
  else
    update elius.parametros_negocio set valor = v_i::text where tenant_id = v_tenant and clave = 'demo_indice';
    v_emisor := null; v_conv := null;
  end if;

  v_est := elius.estado_demo(v_tenant, v_d);
  select count(distinct conversacion_id) into v_clientes from elius.mensajes where tenant_id = v_tenant and emisor = 'cliente';
  v_fin := v_i >= v_total and (v_est->>'esperando')::int = 0 and (v_est->>'post')::int = 0;
  return jsonb_build_object('terminado', v_fin, 'indice', v_i, 'total', v_total, 'emisor', v_emisor, 'conversacion_id', v_conv,
                            'clientes', v_clientes, 'esperando', (v_est->>'esperando')::int);
end $$;

-- Vuelve a empezar la demostración del negocio de prueba actual
create or replace function elius.reiniciar_demo()
returns void language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id(); v_vertical text;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  select vertical into v_vertical from platform.tenants where id = v_tenant and slug like 'demo-%';
  if v_vertical is null then raise exception 'Este negocio no es un caso de prueba'; end if;
  perform elius.sembrar_clientes_demo(v_tenant, v_vertical);
end $$;

revoke execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() from public, anon;
revoke execute on function elius.efectos_demo(uuid, uuid, uuid, text, jsonb, int), elius.sembrar_clientes_demo(uuid, text), elius.limpiar_caso_demo(uuid), elius.estado_demo(uuid, jsonb) from public, anon, authenticated;
grant execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() to authenticated;
comment on function platform.cargar_caso_demo(text) is 'Crea el negocio de prueba de un caso (restaurante/veterinaria/aerolinea) con catálogo e imágenes';
comment on function elius.siguiente_mensaje_demo() is 'Entrega el siguiente mensaje del guion del caso de prueba; tras aprobar o rechazar un comprobante, Eli continúa esa conversación';
