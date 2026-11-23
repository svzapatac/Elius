// =============================================================================
// Edge Function: factus-crear-recaudo
// Crea un cobro por llave Bre-B y QR en Factus Pay para una orden (DT-18, RN-C22, RN-C23).
//
// La llama Eli (o un Operador) con su propio JWT:
//   POST /functions/v1/factus-crear-recaudo   { "orden_id": "<uuid>", "monto": 34560 }
// - Con el JWT del usuario se lee la orden y se registra el recaudo: RLS aplica.
// - Con service_role solo se leen las credenciales de Factus desde Supabase Vault.
// Documentación de Factus: https://pay-developers.factus.com.co/recaudos/crear/
// =============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const URLS: Record<string, string> = {
  sandbox: "https://pay-api-sandbox.factus.com.co",
  produccion: Deno.env.get("FACTUS_API_URL_PRODUCCION") ?? "",
};

type Credenciales = { email: string; password: string; token?: string };

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Método no permitido", { status: 405 });
  const jwt = req.headers.get("Authorization") ?? "";
  const { orden_id, monto } = await req.json();

  // Cliente con el JWT de quien llama: RLS decide qué puede ver y escribir
  const usuario = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: jwt } },
  });
  // Cliente de servicio: SOLO para leer y rotar secretos de Vault
  const servicio = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // 1. ¿Se cobra por llave o por comprobante? (RN-C23)
  const { data: estrategia, error: e1 } = await usuario.schema("elius").rpc("estrategia_cobro", { p_monto: monto });
  if (e1) return Response.json({ error: e1.message }, { status: 400 });
  if (estrategia !== "llave_breb_factus") return Response.json({ estrategia: "comprobante" });

  // 2. Orden y pasarela del tenant (visibles por RLS)
  const { data: orden } = await usuario.schema("elius").from("ordenes").select("id, numero").eq("id", orden_id).single();
  const { data: pasarela } = await usuario.schema("elius").from("pasarelas_pago")
    .select("id, ambiente, expiracion_segundos, referencia_credenciales")
    .eq("activa", true).eq("proveedor", "factus_pay").single();
  if (!orden || !pasarela) return Response.json({ error: "Orden o pasarela no encontrada" }, { status: 404 });

  // 3. Credenciales desde Vault (nunca en variables del navegador)
  const { data: secreto } = await servicio.schema("elius").rpc("srv_secreto", { p_id: pasarela.referencia_credenciales });
  const cred: Credenciales = JSON.parse(secreto);
  const base = URLS[pasarela.ambiente];

  // Factus: un solo token activo por usuario, sin vencimiento. Se pide de nuevo solo si responde 401.
  const autenticar = async () => {
    const r = await fetch(`${base}/auth`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ email: cred.email, password: cred.password }),
    });
    if (!r.ok) throw new Error(`Factus /auth respondió ${r.status}`);
    cred.token = (await r.json()).token;
    await servicio.schema("elius").rpc("srv_actualizar_secreto", {
      p_id: pasarela.referencia_credenciales, p_valor: JSON.stringify(cred),
    });
  };
  if (!cred.token) await autenticar();

  // 4. Crear el recaudo. La misma referencia y el mismo monto renuevan un QR vencido.
  const referencia = `E-${orden.numero}-${Math.round(monto)}`;
  const crear = () => fetch(`${base}/v1/collections`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json", Authorization: `Bearer ${cred.token}` },
    body: JSON.stringify({ reference_code: referencia, amount: monto, expiration: pasarela.expiracion_segundos }),
  });
  let r = await crear();
  if (r.status === 401) { await autenticar(); r = await crear(); }
  if (!r.ok) return Response.json({ error: `Factus respondió ${r.status}` }, { status: 502 });
  const { data } = await r.json(); // reference_code, amount, status, breb_key, qr_expires_at, qr

  // 5. Guardar el QR en Storage y registrar el recaudo en la base (con el JWT del usuario)
  const png = Uint8Array.from(atob(data.qr.split(",")[1]), (c) => c.charCodeAt(0));
  const ruta = `${orden_id}/${referencia}.png`;
  await servicio.storage.from("qr-recaudos").upload(ruta, png, { contentType: "image/png", upsert: true });
  const { data: firmado } = await servicio.storage.from("qr-recaudos").createSignedUrl(ruta, pasarela.expiracion_segundos);

  const { data: recaudoId, error: e2 } = await usuario.schema("elius").rpc("registrar_recaudo", {
    p_orden: orden_id, p_codigo: referencia, p_monto: monto, p_llave: data.breb_key,
    p_url_qr: firmado?.signedUrl ?? null,
    p_expira: new Date(Date.now() + pasarela.expiracion_segundos * 1000).toISOString(),
  });
  if (e2) return Response.json({ error: e2.message }, { status: 400 });

  // Eli envía al cliente la llave y el QR por WhatsApp
  return Response.json({ estrategia: "llave_breb_factus", recaudo_id: recaudoId, llave: data.breb_key, qr: firmado?.signedUrl });
});
