-- ============================================================
-- 유유히 — 알림 발송 문구 활성화 토글 + 신청 건별 카톡알림 발송 상태
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- ============================================================

alter table site add column if not exists notify_receipt_on boolean not null default true;
alter table site add column if not exists notify_confirm_on boolean not null default true;
alter table applications add column if not exists kakao_notice text;
