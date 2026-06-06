// supabase/functions/send-attendance-notification/index.ts
/// <reference path="./deno.d.ts" />
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encode as base64url } from "https://deno.land/std@0.177.0/encoding/base64url.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL")!;
const FCM_PRIVATE_KEY = Deno.env.get("FCM_PRIVATE_KEY")!;

// ── JWT oluştur (Google OAuth2 için) ──
async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: FCM_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = new TextEncoder();
  const headerB64 = base64url(enc.encode(JSON.stringify(header)));
  const payloadB64 = base64url(enc.encode(JSON.stringify(payload)));
  const signInput = `${headerB64}.${payloadB64}`;

  // Private key'i import et
  const pemBody = FCM_PRIVATE_KEY.replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\n/g, "")
    .trim();

  const binaryKey = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    enc.encode(signInput)
  );
  const sigB64 = base64url(new Uint8Array(signature));
  const jwt = `${signInput}.${sigB64}`;

  // Token al
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenRes.json();
  return tokenData.access_token;
}

// ── FCM bildirim gönder ──
async function sendFCM(
  token: string,
  title: string,
  body: string,
  accessToken: string
): Promise<boolean> {
  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: token,
            notification: { title, body },
            android: {
              priority: "high",
              notification: { channel_id: "yoklama_channel" },
            },
          },
        }),
      }
    );
    const data = await res.json();
    if (!res.ok) {
      console.error("FCM hata:", JSON.stringify(data));
      return false;
    }
    return true;
  } catch (e) {
    console.error("FCM gönderim hatası:", e);
    return false;
  }
}

serve(async (req: Request) => {
  try {
    const { session_id, course_name, course_code, course_type, session_number } = await req.json();

    console.log(`📤 Bildirim tetiklendi: session=${session_id} ders=${course_name}`);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const today = new Date().toLocaleDateString("tr-TR");
    const absenceLimit = course_type === "uygulamali" ? 3 : 4;

    // 1. Bu derse kayıtlı öğrencileri getir
    const { data: students } = await supabase
      .from("enrollments")
      .select("student_tc_no, full_name, email, devam_muaf")
      .eq("course_name", course_name);

    if (!students || students.length === 0) {
      return new Response(JSON.stringify({ message: "Kayıtlı öğrenci yok" }), { status: 200 });
    }

    // 2. Bu oturuma katılanları getir
    const { data: attendees } = await supabase
      .from("attendance")
      .select("student_id")
      .eq("session_id", session_id);

    const attendedIds = new Set((attendees || []).map((a: any) => a.student_id));

    // 3. FCM access token al
    const accessToken = await getAccessToken();

    let sent = 0;
    let errors = 0;

    for (const student of students) {
      if (student.devam_muaf) continue;

      // FCM token al
      const { data: tokenData } = await supabase
        .from("fcm_tokens")
        .select("fcm_token")
        .eq("student_tc_no", student.student_tc_no)
        .order("updated_at", { ascending: false })
        .limit(1);

      if (!tokenData || tokenData.length === 0) continue;
      const fcmToken = tokenData[0].fcm_token;

      const attended = attendedIds.has(student.student_tc_no);

      // ── Ders sonrası bildirim ──
      let title: string;
      let body: string;

      if (attended) {
        title = "✅ Katılım Sağlandı";
        body = `${course_name} dersinin ${today} tarihli ${session_number}. oturumuna başarıyla katılım sağladınız.`;
      } else {
        title = "❌ Katılım Sağlanamadı";
        body = `${course_name} dersinin ${today} tarihli ${session_number}. oturumuna katılım sağlanamadı.`;
      }

      const ok = await sendFCM(fcmToken, title, body, accessToken);
      if (ok) sent++;
      else errors++;

      // Bildirimi logla
      await supabase.from("notification_history").insert({
        student_tc_no: student.student_tc_no,
        course_code: course_code || course_name,
        session_id: session_id,
        notification_type: attended ? "katilim" : "devamsizlik",
        title: title,
        body: body,
        week_number: session_number,
      });

      // ── Devamsızlık limiti kontrolü ──
      if (!attended) {
        // Toplam kapatılmış oturum sayısı
        const { count: totalSessions } = await supabase
          .from("sessions")
          .select("*", { count: "exact", head: true })
          .eq("course_name", course_name)
          .eq("is_closed", true);

        // Bu öğrencinin katıldığı oturum sayısı
        const { data: attData } = await supabase
          .from("attendance")
          .select("session_id, sessions!inner(course_name)")
          .eq("student_id", student.student_tc_no)
          .eq("sessions.course_name", course_name);

        const attendedCount = attData ? attData.length : 0;
        const missedCount = (totalSessions || 0) - attendedCount;

        // Limit tam doldu mu? (tam eşitlikte bir kez bildirim at)
        if (missedCount === absenceLimit) {
          // Daha önce limit bildirimi gönderilmiş mi?
          const { data: prevNotif } = await supabase
            .from("notification_history")
            .select("id")
            .eq("student_tc_no", student.student_tc_no)
            .eq("course_code", course_code || course_name)
            .eq("notification_type", "limit_doldu")
            .limit(1);

          if (!prevNotif || prevNotif.length === 0) {
            const limitTitle = "⚠️ Devamsızlık Limitiniz Doldu!";
            const limitBody = `${course_name} (${course_type === "uygulamali" ? "Uygulamalı" : "Teorik"}) dersinde ${absenceLimit} devamsızlık hakkınızın tamamını kullandınız. Dersten kalma durumunuz oluşmuştur.`;

            await sendFCM(fcmToken, limitTitle, limitBody, accessToken);

            await supabase.from("notification_history").insert({
              student_tc_no: student.student_tc_no,
              course_code: course_code || course_name,
              session_id: session_id,
              notification_type: "limit_doldu",
              title: limitTitle,
              body: limitBody,
              week_number: session_number,
            });
          }
        }
      }
    }

    return new Response(
      JSON.stringify({ success: true, sent, errors, total: students.length }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("Edge function hatası:", e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});