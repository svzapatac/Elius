// Servicio de notificaciones push de Elius. Sin dependencias (solo Node 20+).
//   GET  /salud   -> {ok:true}
//   POST /enviar  (Authorization: Bearer SERVICE_TOKEN)
//        {subs:[{endpoint,p256dh,auth}], mensaje:{titulo,cuerpo,url,tag}} -> {enviados, fallidos, muertos:[endpoint]}
// Lo llama la base de datos (trigger + pg_net) cuando llega un comprobante. No guarda nada ni toca la base:
// las suscripciones vienen en la petición. Variables: SERVICE_TOKEN, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT, PORT.
import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { enviarPush } from './webpush.js';

const env = process.env;
const faltan = ['SERVICE_TOKEN', 'VAPID_PUBLIC_KEY', 'VAPID_PRIVATE_KEY'].filter(k => !env[k]);
if (faltan.length) { console.error(JSON.stringify({ nivel: 'error', mensaje: 'faltan variables', faltan })); process.exit(1); }
const vapid = { publica: env.VAPID_PUBLIC_KEY, privada: env.VAPID_PRIVATE_KEY, subject: env.VAPID_SUBJECT || 'mailto:soporte@elius.co' };
const log = (nivel, mensaje, extra = {}) => console.log(JSON.stringify({ hora: new Date().toISOString(), nivel, mensaje, ...extra }));

const igual = (a, b) => { const x = Buffer.from(a), y = Buffer.from(b); return x.length === y.length && timingSafeEqual(x, y); };
const leer = (req) => new Promise((ok, mal) => { let d = ''; req.on('data', c => { d += c; if (d.length > 1e6) { mal(new Error('muy grande')); req.destroy(); } }); req.on('end', () => ok(d)); req.on('error', mal); });
const responder = (res, codigo, obj) => { res.writeHead(codigo, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };

const servidor = http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/salud') return responder(res, 200, { ok: true });
    if (req.method === 'POST' && req.url === '/enviar') {
      const auth = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
      if (!auth || !igual(auth, env.SERVICE_TOKEN)) return responder(res, 401, { error: 'no autorizado' });
      const { subs, mensaje } = JSON.parse(await leer(req) || '{}');
      if (!Array.isArray(subs) || !mensaje) return responder(res, 400, { error: 'faltan subs o mensaje' });
      const texto = JSON.stringify(mensaje);
      const resultados = await Promise.allSettled(subs.map(s => enviarPush(s, texto, vapid)));
      const muertos = [];
      resultados.forEach((r, i) => { if (r.status === 'rejected' && [404, 410].includes(r.reason?.status)) muertos.push(subs[i].endpoint); });
      const enviados = resultados.filter(r => r.status === 'fulfilled').length;
      resultados.forEach(r => { if (r.status === 'rejected') log('warn', 'push fallido', { error: String(r.reason?.message || r.reason) }); });
      log('info', 'push enviado', { suscripciones: subs.length, enviados, fallidos: subs.length - enviados });
      return responder(res, 200, { enviados, fallidos: subs.length - enviados, muertos });
    }
    responder(res, 404, { error: 'no existe' });
  } catch (e) { log('error', 'fallo', { error: String(e.message) }); responder(res, 500, { error: 'error interno' }); }
});
const puerto = Number(env.PORT || 3000);
servidor.listen(puerto, '0.0.0.0', () => log('info', 'servicio arriba', { puerto }));
for (const s of ['SIGTERM', 'SIGINT']) process.on(s, () => { servidor.close(() => process.exit(0)); setTimeout(() => process.exit(0), 10000).unref(); });
