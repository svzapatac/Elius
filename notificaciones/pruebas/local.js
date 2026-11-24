// Prueba de ida y vuelta: ciframos como el servicio y el "navegador" descifra con sus llaves.
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import http from 'node:http';
import { cifrarPayload, descifrarPayload } from '../src/webpush.js';

const nav = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const jwk = nav.privateKey.export({ format: 'jwk' });
const p256dh = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]).toString('base64url');
const auth = randomBytes(16).toString('base64url');
const claro = JSON.stringify({ titulo: 'Comprobante por revisar', cuerpo: 'Prueba', url: '/#/comprobantes' });
const cuerpo = await cifrarPayload(p256dh, auth, claro);
const vuelta = await descifrarPayload(cuerpo, { p256dh, auth, privadaJwk: jwk });
if (vuelta !== claro) { console.error('FALLA: el mensaje descifrado no coincide'); process.exit(1); }
console.log('OK  cifrado y descifrado coinciden');

// Servicio de punta a punta contra un "servidor push" falso
import { spawn } from 'node:child_process';
const recibidos = [];
const falso = http.createServer((req, res) => { let n = 0; req.on('data', c => n += c.length); req.on('end', () => { recibidos.push({ url: req.url, auth: req.headers.authorization?.startsWith('vapid '), bytes: n }); res.writeHead(req.url === '/muerto' ? 410 : 201); res.end(); }); }).listen(0);
await new Promise(r => falso.on('listening', r));
const base = `http://127.0.0.1:${falso.address().port}`;
const v = JSON.parse((await import('node:fs')).readFileSync(process.env.VAPID_FILE || '/tmp/vapid.json', 'utf8'));
const srv = spawn('node', ['src/index.js'], { env: { ...process.env, PORT: '3999', SERVICE_TOKEN: 'tok', VAPID_PUBLIC_KEY: v.publica, VAPID_PRIVATE_KEY: v.privada }, stdio: 'ignore' });
await new Promise(r => setTimeout(r, 800));
const llamar = (token) => fetch('http://127.0.0.1:3999/enviar', { method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ subs: [{ endpoint: base + '/vivo', p256dh, auth }, { endpoint: base + '/muerto', p256dh, auth }], mensaje: { titulo: 'x', cuerpo: 'y' } }) });
const mala = await llamar('otro');
const buena = await (await llamar('tok')).json();
srv.kill(); falso.close();
if (mala.status !== 401) { console.error('FALLA: aceptó un token incorrecto'); process.exit(1); }
if (buena.enviados !== 1 || buena.fallidos !== 1 || buena.muertos?.length !== 1) { console.error('FALLA', buena); process.exit(1); }
if (!recibidos.every(r => r.auth && r.bytes > 50)) { console.error('FALLA: petición push mal formada'); process.exit(1); }
console.log('OK  el servicio rechaza tokens malos, envía cifrado con VAPID y reporta suscripciones muertas');
