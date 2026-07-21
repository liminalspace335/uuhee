-- ============================================================
-- 유유히 — 문의 접수 안내 활성화 토글
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- ============================================================

alter table site add column if not exists notify_inquiry_on boolean not null default true;
