-- ============================================================
-- 유유히 — 신청 저장을 위한 전용 함수(RPC) 추가 + 정원 트리거 재설치
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- 배경: supabase-migration-security-rls.sql 적용 이후, applications 테이블은
-- 로그인 안 한 사용자의 SELECT(조회)를 막았다. 그런데 기존 신청 저장 코드는
-- insert(...).select('id').single() 방식 — "저장하고 방금 만든 행을 즉시
-- 돌려받는" 패턴을 쓰는데, 이 패턴은 내부적으로 SELECT 권한이 필요해서
-- SELECT가 막힌 뒤로는 저장 자체가 거부되고 있었다(고객 예약이 실제로
-- 저장되지 않는 심각한 회귀). 이 함수는 관리자 권한(SECURITY DEFINER)으로
-- 실행되어 SELECT 제한과 무관하게 안전하게 저장하고 새 id를 돌려준다.
--
-- 정원·휴무 검증 트리거(uuhee_check_application_capacity)가 이전 실행에서
-- 적용되지 않은 것으로 확인되어, 이 파일에서 함께(재)생성한다. 여러 번
-- 실행해도 안전하다(create or replace / drop if exists 사용).
-- ============================================================

create or replace function uuhee_check_application_capacity() returns trigger as $$
declare
  cid bigint;
  eff_cap int;
  is_holiday boolean;
  booked int;
begin
  select exists(
    select 1 from holidays where branch = new.branch and sdate = new.sdate
  ) into is_holiday;
  if is_holiday then
    raise exception '선택하신 날짜는 휴무일로 지정되어 신청할 수 없습니다.';
  end if;

  select id into cid from classes where name = new.cls limit 1;

  select cap into eff_cap from schedule
    where branch = new.branch and sdate = new.sdate and stime = new.stime and class_id = cid
    order by id limit 1;

  if eff_cap is null then
    select cap into eff_cap from slots
      where branch = new.branch and stime = new.stime and class_id = cid
      order by id limit 1;
  end if;

  if eff_cap is null or eff_cap <= 0 then
    return new; -- 정원 설정 없음(협의/무제한) — 통과
  end if;

  select coalesce(sum(people), 0) into booked
    from applications
    where branch = new.branch and cls = new.cls and sdate = new.sdate and stime = new.stime
      and coalesce(status, 1) not in (5, 7); -- 취소·환불완료는 정원에서 제외

  if booked + coalesce(new.people, 0) > eff_cap then
    raise exception '선택하신 시간은 방금 정원이 마감되었습니다(잔여 %석). 다른 시간을 선택해 주세요.', greatest(eff_cap - booked, 0);
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_uuhee_check_application_capacity on applications;
create trigger trg_uuhee_check_application_capacity
  before insert on applications
  for each row execute function uuhee_check_application_capacity();

-- ============================================================
-- 신청 저장 전용 함수 — applications + application_items를 한 번에 저장하고 새 id 반환
-- ============================================================
create or replace function uuhee_submit_application(
  p_branch text,
  p_cls text,
  p_size text,
  p_sdate text,
  p_stime text,
  p_people int,
  p_name text,
  p_phone text,
  p_email text,
  p_msg text,
  p_estimate numeric,
  p_pay_method text,
  p_status int default 1,
  p_items jsonb default '[]'::jsonb
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id bigint;
begin
  insert into applications(branch, cls, size, sdate, stime, people, name, phone, email, msg, estimate, pay_method, status)
  values (p_branch, p_cls, p_size, p_sdate, p_stime, p_people, p_name, p_phone, p_email, p_msg, p_estimate, p_pay_method, coalesce(p_status, 1))
  returning id into new_id;

  if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
    insert into application_items(application_id, size, qty)
    select new_id, (elem->>'size'), nullif(elem->>'qty', '')::int
    from jsonb_array_elements(p_items) as elem;
  end if;

  return new_id;
end;
$$;

grant execute on function uuhee_submit_application(text,text,text,text,text,int,text,text,text,text,numeric,text,int,jsonb) to anon, authenticated;
