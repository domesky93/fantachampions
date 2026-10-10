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

    // Controlla se già pagato
    const { data: profile } = await supabase
      .from("profiles")
      .select("subscription_paid")
      .eq("id", user.id)
      .single();

    if (profile?.subscription_paid) {
      return json({ error: "Già abbonato" }, 400);
    }

    // Prezzo da settings
    const { data: settings } = await supabase
      .from("settings")
      .select("subscription_price, subscription_label")
      .eq("id", 1)
      .single();

    const price = Number(settings?.subscription_price || 25);
    const label = settings?.subscription_label || "Abbonamento Champions 2026/27";

    const { accessToken, baseUrl } = await getPayPalAccessToken();

    const origin = req.headers.get("origin") || "https://example.com";

    const orderResp = await fetch(`${baseUrl}/v2/checkout/orders`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        intent: "CAPTURE",
        purchase_units: [{
          reference_id: user.id,
          description: label,
          amount: {
            currency_code: "EUR",
            value: price.toFixed(2),
          },
        }],
        application_context: {
          brand_name: "Fanta Champions",
          user_action: "PAY_NOW",
          return_url: `${origin}/#/profilo?paypal=ok`,
          cancel_url: `${origin}/#/profilo?paypal=cancel`,
        },
      }),
    });

    if (!orderResp.ok) {
      const errBody = await orderResp.text();
      console.error("PayPal create order error:", errBody);
      return json({ error: "Errore creazione ordine PayPal" }, 502);
    }

    const order = await orderResp.json();

    const approveLink = order.links?.find((l) => l.rel === "approve");
    if (!approveLink) {
      return json({ error: "Errore link PayPal" }, 502);
    }

    return json({
      orderId: order.id,
      approveUrl: approveLink.href,
    });
  } catch (err) {
    console.error("paypal-create-order error:", err);
    return json({ error: "Errore durante la creazione dell'ordine" }, 500);
  }
});
