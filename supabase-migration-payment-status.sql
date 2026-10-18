-- ============================================================
-- 유유히 — 신청 건의 결제 금액·방법 분리 저장
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- (여러 번 실행해도 안전합니다)
--
-- 배경: 그동안 예약금/잔액/실제 받은 방법은 memo 칸에 "예약금 5만완, 차액 2만 계좌완"
-- 처럼 손으로 적고 있었다. 이걸 컬럼으로 분리해 신청관리에서 바로 보이게 한다.
--
--   deposit        예약 시 받은 금액(예약금). 비어 있으면 어드민이 자동 계산해 보여준다
--                  — 현장결제는 설정된 예약금, 계좌이체·스토어는 전액 선결제라 총액.
--   pay_status     예약 시 지불한 방법(계좌완/예약금 완/카드결제/스토어/솜씨당/주말토리/
--                  탈잉/예약금 환불). 비어 있으면 고객이 고른 결제수단으로 '…대기'를 보여주고,
--                  입금 확인 후 관리자가 '완' 값으로 바꾼다.
--   balance_method 잔액을 실제로 받은 방법(계좌완/카드결제/스토어).
--
-- 잔액(= 결제금액 - 예약금)과 최종결제상태(= 잔액결제방법 또는 결제상태)는 계산해서
-- 보여주기만 하므로 컬럼으로 저장하지 않는다.
-- ============================================================

alter table applications add column if not exists deposit numeric;
alter table applications add column if not exists pay_status text;
alter table applications add column if not exists balance_method text;
