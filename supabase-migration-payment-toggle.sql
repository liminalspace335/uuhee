-- ============================================================
-- 유유히 — 결제수단별 활성화 토글
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- ============================================================

alter table site add column if not exists pay_transfer_on boolean not null default true;
alter table site add column if not exists pay_smartstore_on boolean not null default true;
alter table site add column if not exists pay_onsite_on boolean not null default true;
