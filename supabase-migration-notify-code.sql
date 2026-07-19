-- ============================================================
-- 유유히 — kakao_notice를 텍스트('접수'/'확정') 대신 코드값(1/2)으로 저장
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- status 컬럼처럼 숫자 코드로 저장하고(1=접수, 2=확정), 화면 표시용 라벨은
-- 코드로만 관리한다(admin.html KNLAB={1:'접수',2:'확정'}). 이미 text로
-- '접수'/'확정' 문자열이 들어간 기존 데이터가 있어도 아래에서 안전하게
-- 숫자로 변환한다.
-- ============================================================

alter table applications
  alter column kakao_notice type smallint
  using (case kakao_notice when '접수' then 1 when '확정' then 2 else null end);
