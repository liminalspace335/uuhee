-- ============================================================
-- 유유히 — 결제수단 활성화 토글을 지점별로 분리
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- 배경: 기존 site.pay_transfer_on/pay_smartstore_on/pay_onsite_on은 전체
-- 지점 공통(전역) 값이었는데, 실제로는 지점별로 다르게 켜고 꺼야 했다.
-- 이 스크립트는 branches 테이블에 지점별 컬럼을 추가하고, 기존 site의
-- 전역 값을 초기값으로 복사한다(기존 설정이 갑자기 바뀌지 않도록).
-- ============================================================

alter table branches add column if not exists pay_transfer_on boolean not null default true;
alter table branches add column if not exists pay_smartstore_on boolean not null default true;
alter table branches add column if not exists pay_onsite_on boolean not null default true;

update branches set
  pay_transfer_on = coalesce((select pay_transfer_on from site where id = 'uuhee'), true),
  pay_smartstore_on = coalesce((select pay_smartstore_on from site where id = 'uuhee'), true),
  pay_onsite_on = coalesce((select pay_onsite_on from site where id = 'uuhee'), true);
