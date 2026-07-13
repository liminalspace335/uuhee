-- ============================================================
-- 유유히 — 신청 정원(잔여석) 서버측 검증
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- 배경: 잔여석 체크가 브라우저에 저장된 로컬 스냅샷 기준이라, 여러 고객이
-- 거의 동시에 같은 지점·클래스·날짜·시간을 신청하면 둘 다 클라이언트 체크는
-- 통과하고 실제로는 정원을 넘는 예약이 DB에 그대로 쌓일 수 있었음.
-- applications INSERT 시점에 DB에서 한 번 더 정원을 검증해 확실히 막는다.
--
-- UPDATE에는 적용하지 않음(관리자가 상태를 바꾸는 등 기존 행을 수정할 때
-- 자기 자신을 이중으로 카운트하는 문제, 관리자의 의도적 정원 조정을 막는
-- 문제가 생기므로) — 동시접속 정원 초과는 신규 INSERT 시점의 경쟁 상태이므로
-- INSERT 검증만으로 충분함.
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
