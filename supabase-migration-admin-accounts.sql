-- ============================================================
-- 유유히 — 계정별 메뉴/CRUD 권한 시스템: admin_accounts 테이블
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- perms 구조: { "메뉴키": { "view":bool, "create":bool, "update":bool, "delete":bool } }
-- 메뉴키는 admin.html의 nav data-p 값과 맞춘다: list, schedule, settings
-- (overview는 권한 없이 항상 조회 가능, accounts는 is_master로만 노출되므로 perms에 없음)
--
-- 보안 설계: 이 테이블은 SELECT 정책만 만든다(로그인한 사람이면 누구나 자기 권한을
-- 조회할 수 있어야 하므로). INSERT/UPDATE/DELETE 정책은 의도적으로 만들지 않는다 —
-- 그래서 이 테이블에 대한 쓰기는 REST API로는 원천 불가능하고, 오직 별도 배포하는
-- admin-accounts Edge Function(service_role 키 사용)을 통해서만 가능하다.
-- ============================================================

create table if not exists admin_accounts (
  email text primary key,
  label text,
  perms jsonb not null default '{}'::jsonb,
  is_master boolean not null default false,
  created_at timestamptz default now()
);

alter table admin_accounts enable row level security;
drop policy if exists "admin_accounts_select" on admin_accounts;
create policy "admin_accounts_select" on admin_accounts for select to authenticated using (true);

-- 기존 로그인 계정을 마스터로 등록(없으면 생성, 있으면 마스터로 승격) —
-- 마스터가 하나도 없으면 계정관리 화면에 아무도 못 들어가므로 반드시 필요.
insert into admin_accounts (email, label, perms, is_master)
values (
  'liminalspace335@gmail.com',
  '마스터',
  '{"list":{"view":true,"create":true,"update":true,"delete":true},"schedule":{"view":true,"create":true,"update":true,"delete":true},"settings":{"view":true,"create":true,"update":true,"delete":true}}'::jsonb,
  true
)
on conflict (email) do update set is_master = true;
