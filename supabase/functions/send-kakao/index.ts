// 유유히 — 카카오 알림톡(솔라피) 발송 전용 Edge Function
//
// 솔라피 API Key/Secret은 절대 브라우저 코드에 넣지 않는다. 이 함수 안에서만
// 환경변수(Supabase 비밀값)로 읽어 서버 쪽에서 솔라피로 발송한다.
//
// kind:
//  - 'app-receipt'     : 클래스 신청 접수 안내(결제수단별 템플릿 자동 선택) — 고객이 결제수단
//                        선택 후 신청을 마치면 index.html에서 인증 없이 호출한다(공개 흐름).
//                        이미 카톡알림이 기록된 건은 중복 발송하지 않고 그대로 성공 처리한다.
//  - 'app-confirm'     : 예약 확정 안내 — 관리자만 호출 가능(로그인 세션 필요).
//  - 'inquiry-receipt' : 단체·기업 문의 접수 안내 — 고객이 문의를 접수하면 index.html에서
//                        인증 없이 호출한다(공개 흐름). app-receipt와 마찬가지로 이미 카톡알림이
//                        기록된 건은 중복 발송하지 않는다.
//  - 'inquiry-confirm' : 문의 확정 안내 — 관리자만 호출 가능(로그인 세션 필요).
//
// 배포: supabase functions deploy send-kakao --project-ref <project-ref>
// 사전 준비(비밀값 등록, 터미널에서 직접 실행):
//   supabase secrets set SOLAPI_API_KEY=... SOLAPI_API_SECRET=... SOLAPI_SENDER_NUMBER=01000000000

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SOLAPI_API_KEY = Deno.env.get("SOLAPI_API_KEY");
const SOLAPI_API_SECRET = Deno.env.get("SOLAPI_API_SECRET");
const SOLAPI_SENDER_NUMBER = Deno.env.get("SOLAPI_SENDER_NUMBER");

const PFID = "KA01PF260721081535097q1VDJEItaUC";
const TEMPLATES: Record<string, string> = {
  "app-receipt-transfer": "KA01TP260721095102897LFlRkehGeC6",
  "app-receipt-onsite": "KA01TP260721095033489mCFW1WiQ2qY",
  "app-receipt-smartstore": "KA01TP260721094950973qcaOpCnJgC2",
  "app-confirm": "KA01TP2607210952438004cm0qtdO03k",
  "inquiry-receipt": "KA01TP260721095352213nbtPJ5jNnXG",
};

function fmtPhone(v: string | null | undefined): string {
  const d = String(v || "").replace(/\D/g, "");
  if (!d) return "-";
  if (/^02/.test(d)) {
    if (d.length === 9) return d.slice(0, 2) + "-" + d.slice(2, 5) + "-" + d.slice(5);
    if (d.length === 10) return d.slice(0, 2) + "-" + d.slice(2, 6) + "-" + d.slice(6);
    return d;
  }
  if (d.length === 10) return d.slice(0, 3) + "-" + d.slice(3, 6) + "-" + d.slice(6);
  if (d.length === 11) return d.slice(0, 3) + "-" + d.slice(3, 7) + "-" + d.slice(7);
  return d;
}

function qtyText(qty: Record<string, unknown> | null | undefined) {
  if (!qty) return "-";
  const parts: string[] = [];
  Object.keys(qty).forEach((k) => {
    const v = qty[k];
    if (v) parts.push(`${k} × ${v}병`);
  });
  return parts.length ? parts.join(", ") : "-";
}

// 솔라피 공식 Node SDK(src/lib/authenticator.ts)의 서명 방식을 그대로 재현한다.
// date는 date-fns formatISO 기본 포맷(밀리초 없음, Z 대신 오프셋 표기)과 동일하게 맞춘다.
function solapiFormatISO(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  const offsetMin = -d.getTimezoneOffset();
  const sign = offsetMin >= 0 ? "+" : "-";
  const absMin = Math.abs(offsetMin);
  const offH = pad(Math.floor(absMin / 60));
  const offM = pad(absMin % 60);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}${sign}${offH}:${offM}`;
}
function solapiSalt(len = 32): string {
  const alphabet = "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const bytes = crypto.getRandomValues(new Uint8Array(len));
  let out = "";
  for (let i = 0; i < len; i++) out += alphabet[bytes[i] % alphabet.length];
  return out;
}
async function solapiAuthHeader(apiKey: string, apiSecret: string) {
  const date = solapiFormatISO(new Date());
  const salt = solapiSalt(32);
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sigBuf = await crypto.subtle.sign("HMAC", key, enc.encode(date + salt));
  const signature = Array.from(new Uint8Array(sigBuf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${signature}`;
}

async function sendAlimtalk(to: string, templateId: string, variables: Record<string, string>) {
  const authHeader = await solapiAuthHeader(SOLAPI_API_KEY!, SOLAPI_API_SECRET!);
  const res = await fetch("https://api.solapi.com/messages/v4/send-many/detail", {
    method: "POST",
    headers: { Authorization: authHeader, "Content-Type": "application/json" },
    body: JSON.stringify({
      messages: [
        {
          to,
          from: SOLAPI_SENDER_NUMBER,
          kakaoOptions: { pfId: PFID, templateId, variables },
        },
      ],
    }),
  });
  const resBody = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(resBody?.errorMessage || resBody?.message || `솔라피 응답 오류(${res.status})`);
  }
  return resBody;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST만 허용됩니다." }, 405);

  try {
    if (!SOLAPI_API_KEY || !SOLAPI_API_SECRET || !SOLAPI_SENDER_NUMBER) {
      return json({ error: "솔라피 발신 정보(API Key/Secret/발신번호)가 서버에 설정되지 않았습니다." }, 500);
    }

    const body = await req.json().catch(() => ({}));
    const kind = body?.kind as string;
    const id = body?.id;
    if (!kind || id == null) return json({ error: "kind, id가 필요합니다." }, 400);

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 관리자 전용 트리거는 로그인 세션 + admin_accounts 권한을 확인한다.
    if (kind === "app-confirm" || kind === "inquiry-confirm") {
      const authHeader = req.headers.get("Authorization") || "";
      if (!authHeader) return json({ error: "인증 정보가 없습니다." }, 401);
      const caller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: userData, error: userErr } = await caller.auth.getUser();
      if (userErr || !userData?.user?.email) return json({ error: "인증에 실패했습니다." }, 401);
      const { data: acct } = await admin
        .from("admin_accounts")
        .select("perms,is_master")
        .eq("email", userData.user.email)
        .maybeSingle();
      const canUpdate = acct?.is_master || !!acct?.perms?.list?.update;
      if (!canUpdate) return json({ error: "이 작업을 수행할 권한이 없습니다." }, 403);
    }

    if (kind === "app-receipt" || kind === "app-confirm") {
      const { data: a, error: aerr } = await admin
        .from("applications")
        .select("*")
        .eq("id", id)
        .maybeSingle();
      if (aerr || !a) return json({ error: "신청 건을 찾을 수 없습니다." }, 404);
      const to = String(a.phone || "").replace(/[^0-9]/g, "");
      if (!to) return json({ error: "수신자 연락처가 없습니다." }, 400);

      if (kind === "app-receipt") {
        if (a.kakao_notice) return json({ ok: true, alreadySent: true });
        const pm = String(a.pay_method || "");
        const variant = /스마트스토어/.test(pm) ? "smartstore" : /현장/.test(pm) ? "onsite" : "transfer";
        const { data: items } = await admin
          .from("application_items")
          .select("size,qty")
          .eq("application_id", id);
        const qty: Record<string, unknown> = {};
        (items || []).forEach((it: { size: string; qty: unknown }) => {
          qty[it.size] = it.qty;
        });
        const amt = a.estimate == null ? 0 : Math.round(Number(a.estimate));
        const variables = {
          "#{이름}": a.name || "-",
          "#{연락처}": fmtPhone(a.phone),
          "#{지점명}": a.branch || "-",
          "#{일자}": a.sdate || "-",
          "#{시간}": a.stime || "-",
          "#{클래스명}": a.cls || "-",
          "#{인원}": String(a.people ?? "-"),
          "#{신청내용}": qtyText(qty),
          "#{결제금액}": amt.toLocaleString(),
        };
        await sendAlimtalk(to, TEMPLATES["app-receipt-" + variant], variables);
        const { error: updErr } = await admin.from("applications").update({ kakao_notice: 1 }).eq("id", id);
        if (updErr) return json({ error: "발송은 성공했지만 기록 저장에 실패했습니다: " + updErr.message }, 500);
        return json({ ok: true });
      }

      // app-confirm
      await sendAlimtalk(to, TEMPLATES["app-confirm"], {});
      const { error: updErr } = await admin
        .from("applications")
        .update({ kakao_notice: 2, status: 3 })
        .eq("id", id);
      if (updErr) return json({ error: "발송은 성공했지만 기록 저장에 실패했습니다: " + updErr.message }, 500);
      return json({ ok: true });
    }

    if (kind === "inquiry-receipt" || kind === "inquiry-confirm") {
      const { data: g, error: gerr } = await admin.from("inquiries").select("*").eq("id", id).maybeSingle();
      if (gerr || !g) return json({ error: "문의 건을 찾을 수 없습니다." }, 404);
      const to = String(g.phone || "").replace(/[^0-9]/g, "");
      if (!to) return json({ error: "수신자 연락처가 없습니다." }, 400);

      if (kind === "inquiry-receipt") {
        if (g.kakao_notice) return json({ ok: true, alreadySent: true });
        const variables = {
          "#{회사단체명}": g.company || "-",
          "#{담당자명}": g.name || "-",
          "#{연락처}": fmtPhone(g.phone),
          "#{지점명}": g.branch || "-",
          "#{인원}": g.isize || "-",
          "#{문의내용}": g.msg || "-",
        };
        await sendAlimtalk(to, TEMPLATES["inquiry-receipt"], variables);
        const { error: updErr } = await admin.from("inquiries").update({ kakao_notice: 1 }).eq("id", id);
        if (updErr) return json({ error: "발송은 성공했지만 기록 저장에 실패했습니다: " + updErr.message }, 500);
        return json({ ok: true });
      }

      // inquiry-confirm
      await sendAlimtalk(to, TEMPLATES["app-confirm"], {});
      const { error: updErr } = await admin
        .from("inquiries")
        .update({ kakao_notice: 2, status: 3 })
        .eq("id", id);
      if (updErr) return json({ error: "발송은 성공했지만 기록 저장에 실패했습니다: " + updErr.message }, 500);
      return json({ ok: true });
    }

    return json({ error: "알 수 없는 kind입니다." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
