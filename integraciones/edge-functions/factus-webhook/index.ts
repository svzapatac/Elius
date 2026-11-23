// =============================================================================
// Edge Function: factus-webhook
// Recibe la notificación de Factus Pay cuando un recaudo queda pagado (RN-C24).
//
// URL que se registra en Factus (una por pasarela de cada negocio):
//   https://<proyecto>.supabase.co/functions/v1/factus-webhook?pasarela=<uuid>
// Factus agrega su clave secreta como ?key=... (https://pay-developers.factus.com.co/webhooks/)
//
// Reglas de Factus que se respetan:
// - Comparar la clave en tiempo constante; si no coincide, responder 401.
// - No responder 2xx sin haber guardado la notificación (si no, Factus no reintenta).
// - Responder en menos de 10 segundos; Factus reintenta hasta 6 veces (1 min, 5 min, 15 min, 1 h, 3 h).
// - En montos altos, confirmar con GET /v1/collections/{reference_code}.
// =============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import { timingSafeEqual } from "node:crypto";

const MONTO_ALTO = Number(Deno.env.get("FACTUS_MONTO_CONFIRMAR") ?? "2000000");
const URLS: Record<string, string> = {
  sandbox: "https://pay-api-sandbox.factus.com.co",
  produccion: Deno.env.get("FACTUS_API_URL_PRODUCCION") ?? "",
};

function igualesEnTiempoConstante(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Método no permitido", { status: 405 });
  const url = new URL(req.url);
  const pasarelaId = url.searchParams.get("pasarela") ?? "";
  const claveRecibida = url.searchParams.get("key") ?? "";
  const carga = await req.json().catch(() => null);
  if (!carga) return new Response("Cuerpo inválido", { status: 400 });

  // El webhook no trae usuario: se usa service_role y el tenant sale de la pasarela
  const servicio = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: filas } = await servicio.schema("elius").rpc("srv_pasarela_webhook", { p_pasarela: pasarelaId });
  const pasarela = filas?.[0];
  if (!pasarela?.activa) return new Response("Pasarela desconocida", { status: 404 });

  // 1. Validar la clave secreta en tiempo constante
  const { data: claveEsperada } = await servicio.schema("elius").rpc("srv_secreto", { p_id: pasarela.referencia_clave_webhook });
  const claveValida = igualesEnTiempoConstante(claveRecibida, claveEsperada ?? "");

  // 2. En montos altos, confirmar contra la API antes de aplicar
  let confirmado = true;
  if (claveValida && Number(carga?.data?.amount) >= MONTO_ALTO) {
    const { data: cred } = await servicio.schema("elius").rpc("srv_secreto", { p_id: pasarela.referencia_credenciales });
    const token = JSON.parse(cred ?? "{}").token;
    const r = await fetch(`${URLS[pasarela.ambiente]}/v1/collections/${encodeURIComponent(carga.data.reference_code)}`, {
      headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
    });
    confirmado = r.ok && (await r.json())?.data?.status === "paid";
  }

  // 3. Guardar y aplicar en una sola llamada (la base es idempotente: un repetido devuelve "duplicado")
  const { data: resultado, error } = await servicio.schema("elius").rpc("webhook_factus", {
    p_pasarela: pasarelaId, p_clave_valida: claveValida && confirmado, p_carga: carga,
  });
  if (error) return new Response("No se pudo guardar", { status: 500 }); // Factus reintentará

  if (!claveValida) return new Response("Clave inválida", { status: 401 });
  return Response.json({ resultado }); // 2xx: entregado, Factus no reintenta
});
