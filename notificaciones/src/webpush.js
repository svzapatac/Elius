/**
 * Web Push (RFC 8291 aes128gcm + VAPID RFC 8292).
 *
 * Esta criptografia se valido byte a byte contra la libreria `web-push`: lo que
 * cifra aqui, `web-push` lo descifra igual. Al portarla desde el nodo Code de
 * n8n NO se cambio el orden ni los bytes del HKDF, ni el formato del registro,
 * ni las cabeceras. Lo unico distinto es de donde sale `subtle`: aqui es el
 * crypto normal de Node, sin el sandbox que bloqueaba los builtins en n8n.
 *
 * Si alguien toca este archivo: el orden de los HKDF y los bytes de los `info`
 * son parte del protocolo. Cambiar uno hace que el navegador reciba basura y
 * descarte la notificacion en silencio, sin error visible.
 */
import { webcrypto, randomBytes } from 'node:crypto';

const subtle = webcrypto.subtle;

const b64uToBytes = (s) => new Uint8Array(Buffer.from(s, 'base64url'));
const bytesToB64u = (b) => Buffer.from(b).toString('base64url');
const utf8 = (s) => new Uint8Array(Buffer.from(s, 'utf8'));
const cat = (...arrs) => {
  const out = new Uint8Array(arrs.reduce((n, a) => n + a.length, 0));
  let o = 0;
  for (const a of arrs) { out.set(a, o); o += a.length; }
  return out;
};

async function hmacSha256(keyBytes, data) {
  const k = await subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await subtle.sign('HMAC', k, data));
}

async function hkdf(salt, ikm, info, length) {
  const prk = await hmacSha256(salt, ikm);
  const okm = await hmacSha256(prk, cat(info, new Uint8Array([1])));
  return okm.slice(0, length);
}

/** JWT ES256 firmado con la llave privada VAPID, para el header Authorization. */
export async function firmarVapid(endpoint, { publica, privada, subject }) {
  const pub = b64uToBytes(publica);
  if (pub.length !== 65 || pub[0] !== 4) {
    throw new Error('VAPID_PUBLIC_KEY no es un punto P-256 valido');
  }
  const key = await subtle.importKey('jwk', {
    kty: 'EC', crv: 'P-256',
    d: privada,
    x: bytesToB64u(pub.slice(1, 33)),
    y: bytesToB64u(pub.slice(33, 65)),
    ext: true,
  }, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);

  const header = bytesToB64u(utf8(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const payload = bytesToB64u(utf8(JSON.stringify({
    aud: new URL(endpoint).origin,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: subject,
  })));
  const sig = new Uint8Array(await subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key, utf8(`${header}.${payload}`)));
  return `${header}.${payload}.${bytesToB64u(sig)}`;
}

/** Cuerpo cifrado aes128gcm, listo para mandarlo tal cual al endpoint del navegador. */
export async function cifrarPayload(p256dh, auth, mensaje) {
  const uaPublic = b64uToBytes(p256dh);
  const authSecret = b64uToBytes(auth);

  const efimero = await subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPublic = new Uint8Array(await subtle.exportKey('raw', efimero.publicKey));
  const uaKey = await subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdhSecret = new Uint8Array(
    await subtle.deriveBits({ name: 'ECDH', public: uaKey }, efimero.privateKey, 256));

  const salt = new Uint8Array(randomBytes(16));
  const keyInfo = cat(utf8('WebPush: info'), new Uint8Array([0]), uaPublic, asPublic);
  const ikm = await hkdf(authSecret, ecdhSecret, keyInfo, 32);
  const cek = await hkdf(salt, ikm, cat(utf8('Content-Encoding: aes128gcm'), new Uint8Array([0])), 16);
  const nonce = await hkdf(salt, ikm, cat(utf8('Content-Encoding: nonce'), new Uint8Array([0])), 12);

  const aesKey = await subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['encrypt']);
  const registro = cat(utf8(mensaje), new Uint8Array([2]));
  const cipher = new Uint8Array(await subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, registro));

  const rs = new Uint8Array(4);
  new DataView(rs.buffer).setUint32(0, 4096);
  return cat(salt, rs, new Uint8Array([asPublic.length]), asPublic, cipher);
}

/**
 * Descifra un cuerpo aes128gcm. Solo se usa en la prueba de ida y vuelta, para
 * comprobar que lo que ciframos es legible con las llaves del suscriptor.
 * Es el lado del navegador, no se usa en produccion.
 */
export async function descifrarPayload(cuerpo, { p256dh, auth, privadaJwk }) {
  const buf = new Uint8Array(cuerpo);
  const salt = buf.slice(0, 16);
  const idlen = buf[20];
  const asPublic = buf.slice(21, 21 + idlen);
  const cipher = buf.slice(21 + idlen);

  const uaPrivate = await subtle.importKey('jwk', privadaJwk,
    { name: 'ECDH', namedCurve: 'P-256' }, false, ['deriveBits']);
  const asKey = await subtle.importKey('raw', asPublic,
    { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdhSecret = new Uint8Array(
    await subtle.deriveBits({ name: 'ECDH', public: asKey }, uaPrivate, 256));

  const uaPublic = b64uToBytes(p256dh);
  const authSecret = b64uToBytes(auth);
  const keyInfo = cat(utf8('WebPush: info'), new Uint8Array([0]), uaPublic, asPublic);
  const ikm = await hkdf(authSecret, ecdhSecret, keyInfo, 32);
  const cek = await hkdf(salt, ikm, cat(utf8('Content-Encoding: aes128gcm'), new Uint8Array([0])), 16);
  const nonce = await hkdf(salt, ikm, cat(utf8('Content-Encoding: nonce'), new Uint8Array([0])), 12);

  const aesKey = await subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['decrypt']);
  const claro = new Uint8Array(await subtle.decrypt({ name: 'AES-GCM', iv: nonce }, aesKey, cipher));
  // el ultimo byte es el delimitador de registro (0x02)
  return Buffer.from(claro.slice(0, -1)).toString('utf8');
}

/** Manda una notificacion a UN suscriptor. Devuelve el status del servidor push. */
export async function enviarPush(sub, mensaje, vapid) {
  const cuerpo = await cifrarPayload(sub.p256dh, sub.auth, mensaje);
  const jwt = await firmarVapid(sub.endpoint, vapid);

  const res = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      Authorization: `vapid t=${jwt}, k=${vapid.publica}`,
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      TTL: '2419200',
      Urgency: 'high',
    },
    body: Buffer.from(cuerpo),
  });

  if (!res.ok) {
    const detalle = await res.text().catch(() => '');
    const error = new Error(`el servidor push respondio ${res.status}: ${detalle.slice(0, 200)}`);
    error.status = res.status;
    throw error;
  }
  return res.status;
}
