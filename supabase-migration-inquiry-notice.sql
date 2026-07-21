-- ============================================================
-- 유유히 — 단체·기업 문의 접수 안내 카톡알림 발송 상태
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- ============================================================

alter table inquiries add column if not exists kakao_notice smallint;
