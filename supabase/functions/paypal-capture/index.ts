import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function getPayPalAccessToken() {
  const clientId = Deno.env.get("PAYPAL_CLIENT_ID");
  const clientSecret = Deno.env.get("PAYPAL_CLIENT_SECRET");
  const mode = Deno.env.get("PAYPAL_MODE") || "sandbox";
  const baseUrl = mode === "live"
    ? "https://api-m.paypal.com"
    : "https://api-m.sandbox.paypal.com";

  if (!clientId || !clientSecret) {
    throw new Error("PayPal non configurato");
  }

  const resp = await fetch(`${baseUrl}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      "Authorization": "Basic " + btoa(`${clientId}:${clientSecret}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });

  if (!resp.ok) {
    throw new Error("Errore autenticazione PayPal");
  }

  const data = await resp.json();
  return { accessToken: data.access_token, baseUrl };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Non autenticato" }, 401);
    }

    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    if (authError || !user) {
      return json({ error: "Non autenticato" }, 401);
    }

    const body = await req.json();
    const orderId = body.orderId;
    if (!orderId) {
      return json({ error: "Order ID mancante" }, 400);
    }

    const { accessToken, baseUrl } = await getPayPalAccessToken();

    // Verifica che l'ordine appartenga all'utente
    const orderResp = await fetch(`${baseUrl}/v2/checkout/orders/${orderId}`, {
      headers: { "Authorization": `Bearer ${accessToken}` },
    });

    if (!orderResp.ok) {
      return json({ error: "Ordine non trovato" }, 404);
    }

    const order = await orderResp.json();
    const referenceId = order.purchase_units?.[0]?.reference_id;

    if (referenceId !== user.id) {
      return json({ error: "Ordine non valido" }, 403);
    }

    // Cattura il pagamento
    const captureResp = await fetch(`${baseUrl}/v2/checkout/orders/${orderId}/capture`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
    });

    if (!captureResp.ok) {
      const errBody = await captureResp.text();
      console.error("PayPal capture error:", errBody);
      return json({ error: "Errore cattura pagamento PayPal" }, 502);
    }

    const capture = await captureResp.json();
    const captureStatus = capture.purchase_units?.[0]?.payments?.captures?.[0]?.status;

    if (captureStatus !== "COMPLETED") {
      return json({ error: "Pagamento non completato" }, 400);
    }

    // Marca l'utente come abbonato
    const { error: updateError } = await supabase
      .from("profiles")
      .update({
        subscription_paid: true,
        subscription_paid_at: new Date().toISOString(),
        paypal_order_id: orderId,
      })
      .eq("id", user.id);

    if (updateError) {
      console.error("Error updating subscription:", updateError);
      return json({ error: "Errore aggiornamento abbonamento" }, 500);
    }

    return json({ success: true, orderId });
  } catch (err) {
    console.error("paypal-capture error:", err);
    return json({ error: "Errore durante la conferma del pagamento" }, 500);
  }
});
