-- ============================================================
-- 유유히 — 신청·문의 데이터를 이름 대신 id/코드로 저장
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- (여러 번 실행해도 안전합니다)
--
-- 배경: applications/inquiries가 지점·클래스를 '이름 문자열'로 저장하고 있었다.
-- 정원 계산도 이름으로 맞췄기 때문에, 클래스설정에서 클래스명이나 지점명을 한 글자만
-- 바꿔도 기존 예약이 정원 계산에서 통째로 빠져버리는 구조였다.
--
-- 바꾸는 것:
--   applications.class_id / branch_id   — 우리가 관리하는 목록은 id로 저장(진짜 키)
--   inquiries.branch_id
--   pay_method / pay_status / balance_method — 한글 라벨 → 코드
--   정원 트리거와 uuhee_booked도 id 기준으로
--
-- cls / branch(이름) 컬럼은 지우지 않는다. 그 시점에 고객이 무엇을 보고 신청했는지
-- 남기는 '스냅샷'이자, 카톡 알림톡 템플릿이 그대로 쓰는 값이다. 다만 계산에는 쓰지 않는다.
-- ============================================================

-- ---------- 1. id 컬럼 추가 + 기존 데이터 백필 ----------
alter table applications add column if not exists class_id  bigint references classes(id);
alter table applications add column if not exists branch_id bigint references branches(id);
alter table inquiries    add column if not exists branch_id bigint references branches(id);

update applications a set class_id = c.id
  from classes c where a.class_id is null and a.cls = c.name;
update applications a set branch_id = b.id
  from branches b where a.branch_id is null and a.branch = b.name;
update inquiries i set branch_id = b.id
  from branches b where i.branch_id is null and i.branch = b.name;

create index if not exists idx_applications_cap
  on applications (branch_id, class_id, sdate, stime);

-- ---------- 2. 결제 관련 값 코드화 ----------
-- 이미 코드로 저장된 행(영문 소문자)은 건드리지 않는다 → 재실행해도 안전
update applications set pay_method = case
    when pay_method like '%스토어%' then 'smartstore'
    when pay_method like '%현장%'   then 'onsite'
    when pay_method like '%계좌%'   then 'transfer'
    else pay_method end
  where pay_method is not null and pay_method <> '' and pay_method !~ '^[a-z_]+$';

update applications set pay_status = case pay_status
    when '계좌대기'    then 'transfer_wait'
    when '계좌완'      then 'transfer_done'
    when '예약금대기'  then 'deposit_wait'
    when '예약금 완'   then 'deposit_done'
    when '카드결제'    then 'card'
    when '스토어대기'  then 'store_wait'
    when '스토어'      then 'store'
    when '솜씨당'      then 'somssidang'
    when '주말토리'    then 'jumaltori'
    when '탈잉'        then 'taling'
    when '예약금 환불' then 'deposit_refund'
    else pay_status end
  where pay_status is not null and pay_status <> '' and pay_status !~ '^[a-z_]+$';

update applications set balance_method = case balance_method
    when '계좌완'   then 'transfer_done'
    when '카드결제' then 'card'
    when '스토어'   then 'store'
    else balance_method end
  where balance_method is not null and balance_method <> '' and balance_method !~ '^[a-z_]+$';

-- ---------- 3. 정원 트리거 — id 기준 ----------
create or replace function uuhee_check_application_capacity() returns trigger as $$
declare
  cid bigint;
  bname text;
  eff_cap int;
  is_holiday boolean;
  booked int;
begin
  -- 이름만 들어온 옛 호출도 받아주되(과도기), 저장되는 값은 id가 기준이다.
  cid := new.class_id;
  if cid is null then
    select id into cid from classes where name = new.cls limit 1;
    new.class_id := cid;
  end if;
  if new.branch_id is null then
    select id into new.branch_id from branches where name = new.branch limit 1;
  end if;
  select name into bname from branches where id = new.branch_id;
  bname := coalesce(bname, new.branch);

  select exists(select 1 from holidays where branch = bname and sdate = new.sdate) into is_holiday;
  if is_holiday then
    raise exception '선택하신 날짜는 휴무일로 지정되어 신청할 수 없습니다.';
  end if;

  select cap into eff_cap from schedule
    where branch = bname and sdate = new.sdate and stime = new.stime and class_id = cid
    order by id limit 1;

  if eff_cap is null then
    select cap into eff_cap from slots
      where branch = bname and stime = new.stime and class_id = cid
      order by id limit 1;
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

-- ---------- 4. 잔여석 조회 — id 기준 ----------
drop function if exists uuhee_booked(text, text, text);
create or replace function uuhee_booked(p_branch_id bigint, p_class_id bigint, p_sdate text)
returns table(stime text, booked int)
language sql
security definer
set search_path = public
as $$
  select stime, coalesce(sum(people), 0)::int as booked
  from applications
  where branch_id = p_branch_id
    and class_id = p_class_id
    and sdate = p_sdate
    and coalesce(status, 1) not in (5, 7)
  group by stime;
$$;
grant execute on function uuhee_booked(bigint,bigint,text) to anon, authenticated;

-- ---------- 5. 신청 저장 RPC — id를 함께 받는다 ----------
-- 기존 시그니처를 지우고 id 인자를 default null로 추가한다. 이미 열려 있던(캐시된)
-- 예전 화면이 id 없이 호출해도 트리거가 이름으로 id를 채워주므로 저장은 계속 된다.
drop function if exists uuhee_submit_application(text,text,text,text,text,int,text,text,text,text,numeric,text,int,jsonb);
create or replace function uuhee_submit_application(
  p_branch text, p_cls text, p_size text, p_sdate text, p_stime text, p_people int,
  p_name text, p_phone text, p_email text, p_msg text, p_estimate numeric,
  p_pay_method text, p_status int default 1, p_items jsonb default '[]'::jsonb,
  p_class_id bigint default null, p_branch_id bigint default null
) returns bigint
language plpgsql security definer set search_path = public as $$
declare new_id bigint;
begin
  insert into applications(branch, cls, size, sdate, stime, people, name, phone, email, msg,
                           estimate, pay_method, status, class_id, branch_id)
  values (p_branch, p_cls, p_size, p_sdate, p_stime, p_people, p_name, p_phone, p_email, p_msg,
          p_estimate, p_pay_method, coalesce(p_status, 1), p_class_id, p_branch_id)
  returning id into new_id;

  if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
    insert into application_items(application_id, size, qty)
    select new_id, (elem->>'size'), nullif(elem->>'qty', '')::int
    from jsonb_array_elements(p_items) as elem;
  end if;

  return new_id;
end;
$$;
grant execute on function uuhee_submit_application(text,text,text,text,text,int,text,text,text,text,numeric,text,int,jsonb,bigint,bigint) to anon, authenticated;

-- ---------- 6. 문의 저장 RPC — 지점 id 포함 ----------
-- 기존 시그니처는 (text x9, int) 이므로 그걸 지우고 p_branch_id를 덧붙인다.
drop function if exists uuhee_submit_inquiry(text,text,text,text,text,text,text,text,text,int);
create or replace function uuhee_submit_inquiry(
  p_itype text, p_volume text, p_branch text, p_company text, p_name text,
  p_phone text, p_email text, p_isize text, p_msg text,
  p_status int default 1, p_branch_id bigint default null
) returns bigint
language plpgsql security definer set search_path = public as $$
declare new_id bigint;
begin
  insert into inquiries(itype, volume, branch, company, name, phone, email, isize, msg, status, branch_id)
  values (p_itype, p_volume, p_branch, p_company, p_name, p_phone, p_email, p_isize, p_msg,
          coalesce(p_status, 1),
          coalesce(p_branch_id, (select id from branches where name = p_branch limit 1)))
  returning id into new_id;
  return new_id;
end;
$$;
grant execute on function uuhee_submit_inquiry(text,text,text,text,text,text,text,text,text,int,bigint) to anon, authenticated;

notify pgrst, 'reload schema';

-- 확인용: 이름 매칭에 실패해 id가 안 채워진 행이 있는지 본다(0이어야 정상).
select
  (select count(*) from applications where class_id is null)  as 클래스id_없음,
  (select count(*) from applications where branch_id is null) as 지점id_없음,
  (select count(*) from inquiries    where branch_id is null) as 문의_지점id_없음;
