-- ============================================================
-- 유유히 — 결제수단 3종 개편(계좌이체 / 스마트스토어 카드결제 / 현장 카드결제)
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- 지점별 결제 링크(계좌이체·예약금 안내용, 스마트스토어)와 예약금 금액을
-- 저장할 컬럼을 추가한다. 기존 site.pay_bank 등 계좌 관련 컬럼은 더 이상
-- 어느 코드에서도 쓰지 않지만, 안전을 위해 삭제하지 않고 그대로 둔다.
-- ============================================================

alter table branches add column if not exists transfer_link text;
alter table branches add column if not exists smartstore_link text;
alter table site add column if not exists deposit_amount numeric;
