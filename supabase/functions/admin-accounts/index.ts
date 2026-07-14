// 유유히 어드민 — 계정 관리 전용 Edge Function
//
// 브라우저 코드에는 절대 service_role 키(관리자 전능 키)를 넣지 않는다. 그런데
// "새 로그인 계정 생성/삭제"는 Supabase Admin API(auth.admin.*)가 필요하고 이건
// service_role 키가 있어야만 호출 가능하다. 그래서 이 부분만 이 함수 안에서만
// service_role 키(환경변수로 자동 주입됨, 아래 어디에도 직접 적지 않음)를 쓰고,
// 브라우저는 이 함수를 호출하기만 한다.
//
// 요청마다: (1) Authorization 헤더의 로그인 토큰으로 호출자가 누군지 다시 확인하고,
// (2) 그 이메일이 admin_accounts.is_master에서 실제로 true인지 DB에서 다시 조회해
// 검증한 다음에만 실제 작업을 수행한다 — "마스터만 계정을 만들 수 있다"는 규칙은
// 화면에서 숨기는 게 아니라 여기(서버)가 강제한다.
//
// 배포: supabase functions deploy admin-accounts --project-ref <project-ref>

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST만 허용됩니다." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader) return json({ error: "인증 정보가 없습니다." }, 401);

    // 호출자 신원 확인 — 이 요청을 보낸 사람이 실제로 로그인한 사용자인지
    // Supabase Auth 서버에 다시 물어본다(클라이언트가 보낸 값을 그대로 믿지 않음).
    const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user?.email) return json({ error: "인증에 실패했습니다." }, 401);
    const callerEmail = userData.user.email;

    // service_role로만 admin_accounts에 쓰기/Auth 사용자 관리가 가능하다.
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 호출자가 실제로 마스터인지 DB에서 재확인(클라이언트가 보낸 is_master 값은 절대 신뢰하지 않음).
    const { data: callerRow, error: callerErr } = await admin
      .from("admin_accounts")
      .select("is_master")
      .eq("email", callerEmail)
      .maybeSingle();
    if (callerErr) return json({ error: callerErr.message }, 500);
    if (!callerRow?.is_master) return json({ error: "마스터 계정만 사용할 수 있는 기능입니다." }, 403);

    const body = await req.json().catch(() => ({}));
    const action = body?.action;

    if (action === "create") {
      const email = String(body.email || "").trim().toLowerCase();
      const password = String(body.password || "");
      const label = String(body.label || email);
      const perms = body.perms && typeof body.perms === "object" ? body.perms : {};
      if (!email || !password) return json({ error: "이메일과 비밀번호를 입력해 주세요." }, 400);
      if (password.length < 6) return json({ error: "비밀번호는 6자 이상이어야 합니다." }, 400);

      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      if (createErr) return json({ error: createErr.message }, 400);

      const { error: insertErr } = await admin.from("admin_accounts").insert({
        email,
        label,
        perms,
        is_master: false,
      });
      if (insertErr) {
        // 계정 행 저장에 실패하면 방금 만든 Auth 계정도 되돌려서 고아 계정이 남지 않도록 한다.
        if (created?.user?.id) await admin.auth.admin.deleteUser(created.user.id).catch(() => {});
        return json({ error: insertErr.message }, 400);
      }
      return json({ ok: true });
    }

    if (action === "updatePerms") {
      const email = String(body.email || "").trim().toLowerCase();
      if (!email) return json({ error: "대상 이메일이 없습니다." }, 400);
      const label = body.label != null ? String(body.label) : undefined;

      const { data: target, error: targetErr } = await admin
        .from("admin_accounts")
        .select("is_master")
        .eq("email", email)
        .maybeSingle();
      if (targetErr) return json({ error: targetErr.message }, 500);
      if (!target) return json({ error: "계정을 찾을 수 없습니다." }, 404);

      const patch = {};
      if (label !== undefined) patch.label = label;
      // 마스터 계정은 스스로(또는 다른 마스터가) 실수로 권한을 줄여 잠기는 사고를 막기 위해
      // 권한 필드는 항상 무시하고 라벨만 반영한다.
      if (!target.is_master && body.perms && typeof body.perms === "object") {
        patch.perms = body.perms;
      }
      const { error: updErr } = await admin.from("admin_accounts").update(patch).eq("email", email);
      if (updErr) return json({ error: updErr.message }, 400);
      return json({ ok: true });
    }

    if (action === "remove") {
      const email = String(body.email || "").trim().toLowerCase();
      if (!email) return json({ error: "대상 이메일이 없습니다." }, 400);
      if (email === callerEmail) return json({ error: "본인 계정은 삭제할 수 없습니다." }, 400);

      const { data: target, error: targetErr } = await admin
        .from("admin_accounts")
        .select("is_master")
        .eq("email", email)
        .maybeSingle();
      if (targetErr) return json({ error: targetErr.message }, 500);
      if (!target) return json({ error: "계정을 찾을 수 없습니다." }, 404);
      if (target.is_master) return json({ error: "마스터 계정은 삭제할 수 없습니다." }, 400);

      const { data: list, error: listErr } = await admin.auth.admin.listUsers();
      if (listErr) return json({ error: listErr.message }, 500);
      const authUser = (list?.users || []).find((u) => (u.email || "").toLowerCase() === email);
      if (authUser) {
        const { error: delErr } = await admin.auth.admin.deleteUser(authUser.id);
        if (delErr) return json({ error: delErr.message }, 400);
      }
      const { error: rowDelErr } = await admin.from("admin_accounts").delete().eq("email", email);
      if (rowDelErr) return json({ error: rowDelErr.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "알 수 없는 action입니다." }, 400);
  } catch (e) {
    return json({ error: String(e?.message || e) }, 500);
  }
});
