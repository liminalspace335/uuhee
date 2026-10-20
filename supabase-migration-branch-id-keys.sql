-- ============================================================
-- 유유히 — 설정 테이블의 지점 참조를 이름에서 branch_id로
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- (여러 번 실행해도 안전합니다)
--
-- 배경: 신청·문의는 id로 바꿨지만(supabase-migration-id-keys.sql), 설정 쪽은
-- 아직 지점을 '이름 문자열'로 참조한다 — slots.branch, schedule.branch,
-- holidays.branch, details.branch, class_branches.branch_name.
-- 그래서 어드민에서 지점 이름을 한 글자만 바꿔도 그 지점의 운영시간·일자별 정원·
-- 휴무일·가격표·클래스 노출 설정이 통째로 끊어진다(클래스는 이미 class_id로 전환됨).
--
-- 기존 이름 컬럼은 지우지 않는다. 되돌리기 쉽고, 아직 예전 화면이 열려 있는
-- 브라우저가 이름으로 읽어도 동작하도록 어드민이 id와 이름을 함께 저장한다.
-- ============================================================

-- ---------- 1. branch_id 추가 + 이름으로 백필 ----------
alter table slots          add column if not exists branch_id bigint references branches(id);
alter table schedule       add column if not exists branch_id bigint references branches(id);
alter table holidays       add column if not exists branch_id bigint references branches(id);
alter table details        add column if not exists branch_id bigint references branches(id);
alter table class_branches add column if not exists branch_id bigint references branches(id);

update slots    t set branch_id = b.id from branches b where t.branch_id is null and t.branch = b.name;
update schedule t set branch_id = b.id from branches b where t.branch_id is null and t.branch = b.name;
update holidays t set branch_id = b.id from branches b where t.branch_id is null and t.branch = b.name;
update details  t set branch_id = b.id from branches b where t.branch_id is null and t.branch = b.name;
update class_branches t set branch_id = b.id from branches b where t.branch_id is null and t.branch_name = b.name;

create index if not exists idx_schedule_lookup on schedule (branch_id, sdate, stime, class_id);
create index if not exists idx_slots_lookup    on slots    (branch_id, stime, class_id);
create index if not exists idx_holidays_lookup on holidays (branch_id, sdate);

-- ---------- 2. 정원 트리거 — 지점도 id로 조회 ----------
-- branch_id가 없는 옛 행을 위해 이름 조회를 폴백으로만 남긴다.
create or replace function uuhee_check_application_capacity() returns trigger as $$
declare
  cid bigint;
  eff_cap int;
  is_holiday boolean;
  booked int;
begin
  cid := new.class_id;
  if cid is null then
    select id into cid from classes where name = new.cls limit 1;
    new.class_id := cid;
  end if;
  if new.branch_id is null then
    select id into new.branch_id from branches where name = new.branch limit 1;
  end if;

  select exists(
    select 1 from holidays h
    where h.sdate = new.sdate
      and ((new.branch_id is not null and h.branch_id = new.branch_id)
        or (new.branch_id is null and h.branch = new.branch))
  ) into is_holiday;
  if is_holiday then
    raise exception '선택하신 날짜는 휴무일로 지정되어 신청할 수 없습니다.';
  end if;

  select s.cap into eff_cap from schedule s
    where s.sdate = new.sdate and s.stime = new.stime and s.class_id = cid
      and ((new.branch_id is not null and s.branch_id = new.branch_id)
        or (new.branch_id is null and s.branch = new.branch))
    order by s.id limit 1;

  if eff_cap is null then
    select sl.cap into eff_cap from slots sl
      where sl.stime = new.stime and sl.class_id = cid
        and ((new.branch_id is not null and sl.branch_id = new.branch_id)
          or (new.branch_id is null and sl.branch = new.branch))
      order by sl.id limit 1;
  end if;

  if eff_cap is null or eff_cap <= 0 then
    return new; -- 정원 설정 없음(협의/무제한) — 통과
  end if;

  select coalesce(sum(people), 0) into booked
    from applications
    where branch_id = new.branch_id and class_id = cid
      and sdate = new.sdate and stime = new.stime
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

notify pgrst, 'reload schema';

-- 확인용: 이름 매칭에 실패해 branch_id가 안 채워진 행 수(모두 0이어야 정상).
select
  (select count(*) from slots          where branch_id is null) as slots_없음,
  (select count(*) from schedule       where branch_id is null) as schedule_없음,
  (select count(*) from holidays       where branch_id is null) as holidays_없음,
  (select count(*) from details        where branch_id is null) as details_없음,
  (select count(*) from class_branches where branch_id is null) as class_branches_없음;
