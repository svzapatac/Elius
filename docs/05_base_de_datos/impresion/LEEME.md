# Impresión del modelo E-R general

Tamaño carta, horizontal, al 100 % (sin «ajustar a la página»). Misma estructura del diagrama original.

| Archivo | Hojas | Letra aprox. |
| --- | --- | --- |
| `modelo_general_6_hojas.pdf` | 6 + 1 de instrucciones (3×2) | 5 pt |
| `modelo_general_12_hojas.pdf` | 12 + 1 de instrucciones (4×3) | 6 pt |

Armado: corta el margen blanco de la izquierda y de arriba de cada hoja (línea punteada) y pega cada hoja encima de la anterior haciendo coincidir las cruces +.

Regenerar: `python3 database/modelo/imprimir_poster.py <imagen.png> <columnas> <filas> <salida.pdf> "<título>"` (la imagen es el diagrama de `er/00a-modelo-general-completo.png`, o uno con menos separación generado con Graphviz).
