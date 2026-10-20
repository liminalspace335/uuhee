-- ============================================================
-- 유유히 — 공개 사이트의 '잔여 N석'을 실제 예약 인원과 연동
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- (여러 번 실행해도 안전합니다)
--
-- 배경: applications는 RLS 때문에 로그인 안 한 고객이 SELECT할 수 없다.
-- 그래서 신청 모달의 '잔여 N석'은 그 브라우저의 localStorage 기록만 빼고 있었고,
-- 다른 고객의 예약은 전혀 반영되지 않았다(정원이 다 찼는데도 '잔여 12석'으로 보이고,
-- 마지막 결제 단계에서야 서버 정원 트리거가 거부). 개인정보 없이 '시간: 인원'만
-- 돌려주는 함수를 두어, 날짜를 고르는 시점에 실제 잔여석이 보이게 한다.
--
-- 취소(5)·환불완료(7) 제외 기준은 정원 트리거(uuhee_check_application_capacity)와 동일하다.
-- ============================================================

create or replace function uuhee_booked(p_branch text, p_cls text, p_sdate text)
returns table(stime text, booked int)
language sql
security definer
set search_path = public
as $$
  select stime, coalesce(sum(people), 0)::int as booked
  from applications
  where branch = p_branch
    and cls = p_cls
    and sdate = p_sdate
    and coalesce(status, 1) not in (5, 7)
  group by stime;
$$;

grant execute on function uuhee_booked(text,text,text) to anon, authenticated;

notify pgrst, 'reload schema';

-- 확인용: 아래 SELECT가 1줄 나와야 정상(anon_ok = true 여야 공개 사이트에서 호출된다).
-- 0줄이면 위 create가 실제로 실행되지 않은 것이고,
-- anon_ok = false면 grant가 빠진 것이다(둘 다 이 파일을 통째로 다시 돌리면 해결).
select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       has_function_privilege('anon', p.oid, 'execute') as anon_ok
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'uuhee_booked';
