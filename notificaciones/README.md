# Servicio de notificaciones push de Elius

Envía una notificación al celular o computador de cada **Administrador** cuando llega un comprobante de pago
(aunque el panel esté cerrado). Es el mismo mecanismo (Web Push + VAPID) que usa el panel de Potrillos, pero
**sin dependencias y sin acceso a la base**: la base de datos le manda en cada llamada las suscripciones y el mensaje.

```
Cliente envía comprobante → trigger en Supabase → pg_net → POST /enviar (este servicio) → push al navegador/celular
```

## Desplegar en Easypanel
1. Servicio nuevo tipo **App**, nombre `notificaciones-elius`, en el mismo proyecto.
   - Origen **GitHub**: `svzapatac/Elius`, rama `main`, **ruta de build `notificaciones/`** (usa el `Dockerfile`).
   - Puerto interno **3000**.
2. **Entorno** (los secretos solo se escriben aquí, nunca en el repositorio):
   ```
   SERVICE_TOKEN=<el valor de platform.ajustes_globales, clave push_service_token>
   VAPID_PUBLIC_KEY=<la llave pública, la misma de platform.ajustes_globales, clave vapid_public>
   VAPID_PRIVATE_KEY=<la llave privada VAPID>
   VAPID_SUBJECT=mailto:tu-correo@ejemplo.com
   ```
3. **Dominio**: agrega un dominio al servicio (HTTPS). Comprueba `https://<dominio>/salud` → `{"ok":true}`.
4. En el SQL Editor de Supabase, dile a la base dónde está el servicio:
   ```sql
   update platform.ajustes_globales set valor = 'https://<dominio>' where clave = 'push_service_url';  -- sin barra final
   ```
5. En el panel, como Administrador: **Comprobantes → Activar notificaciones en este dispositivo**, y luego
   **Enviar notificación de prueba**.

## Notas
- En **iPhone** las notificaciones solo funcionan si el panel se agrega a la pantalla de inicio (Safari → Compartir → Agregar a pantalla de inicio) y se abre desde ese ícono.
- La llave **privada** VAPID no se guarda en la base ni en el repositorio. Si se pierde, se genera un par nuevo, se cambia `vapid_public` y cada dispositivo debe volver a activar sus notificaciones.
- Prueba local: `npm run prueba` (cifrado de ida y vuelta + servicio contra un servidor push falso).
