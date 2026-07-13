-- ============================================================
-- 유유히 — Supabase 정규화(컬럼) 스키마
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
-- 여러 번 다시 실행해도 안전합니다(테이블/컬럼이 이미 있으면 건너뛰거나 컬럼만 추가 — 기존 데이터를 지우지 않음)
-- ============================================================

-- 단일 설정
create table if not exists site (
  id text primary key default 'uuhee',
  brand text, est text, copy_year text, hero_img text, concept_img text,
  pay_bank text, pay_account text, pay_holder text, pay_portone_store text, pay_portone_channel text
);
-- 이미 site 테이블이 있던 경우 컬럼 보강
alter table site add column if not exists pay_bank text;
alter table site add column if not exists pay_account text;
alter table site add column if not exists pay_holder text;
alter table site add column if not exists pay_portone_store text;
alter table site add column if not exists pay_portone_channel text;

-- 소개 미디어 (최대 5개, 순서 있음)
create table if not exists concept_media (
  id bigint generated always as identity primary key,
  ord int, url text
);

create table if not exists legal (
  id text primary key default 'uuhee',
  company text, ceo text, bizno text, mailorder text, privacy text,
  addr text, tel text, email text, kakao text, hosting text,
  terms_url text, privacy_url text, refund_url text
);

-- 지점
create table if not exists branches (
  id bigint generated always as identity primary key,
  ord int, name text, phone text, addr text, map text, hours text, ig text, fb text, lt text,
  space_desc text
);
alter table branches add column if not exists space_desc text;

-- 클래스
create table if not exists classes (
  id bigint generated always as identity primary key,
  ord int, tag text, name text, descr text, active boolean, inquiry_only boolean
);

-- 클래스별 운영 지점 (다대다)
create table if not exists class_branches (
  id bigint generated always as identity primary key,
  class_id bigint references classes(id) on delete cascade,
  branch_name text
);

-- 상세설정 (용량·가격·할인)
-- class_id로 classes를 참조합니다(클래스 이름을 바꿔도 연결이 끊기지 않도록). cls는 참고용 텍스트일 뿐 매칭에 쓰이지 않습니다.
create table if not exists details (
  id bigint generated always as identity primary key,
  branch text, cls text, size text, price numeric, discount_type text, discount_val numeric, descr text
);
alter table details add column if not exists class_id bigint references classes(id) on delete set null;

-- 신청관리 기본값 시간대 — class_id로 classes를 참조
create table if not exists slots (
  id bigint generated always as identity primary key,
  branch text, cls text, stime text, cap int
);
alter table slots add column if not exists class_id bigint references classes(id) on delete set null;

-- 협업 로고
create table if not exists partners (
  id bigint generated always as identity primary key,
  ord int, name text, logo text, cover boolean, link text
);

-- 사진
create table if not exists photos (
  id bigint generated always as identity primary key,
  ord int, img text, category text, folder text, title text, descr text, cover boolean, link text
);

-- 사진 폴더
create table if not exists photo_folders (
  id bigint generated always as identity primary key,
  ord int, category text, name text
);

-- 클래스 설정(날짜별 운영) — class_id로 classes를 참조
create table if not exists schedule (
  id bigint generated always as identity primary key,
  branch text, sdate text, cls text, stime text, cap int
);
alter table schedule add column if not exists class_id bigint references classes(id) on delete set null;

-- ============================================================
-- 1회성 데이터 이관: cls(텍스트)로 저장돼있던 기존 details/slots/schedule 행을 class_id로 연결
--  1) 클래스 이름이 현재와 정확히 일치하는 행은 이름으로 매칭
--  2) 예전 이름("유유히 시그니처 담금주 클래스")으로 남아있던 고아 데이터를 현재 클래스로 연결
--     (클래스 이름 변경으로 스케줄 전체가 미매칭 상태가 됐던 사고를 복구하기 위함 — 필요 없으면 이 블록은 지워도 됩니다)
-- ============================================================
update details d set class_id = c.id from classes c where d.class_id is null and d.cls = c.name;
update slots s set class_id = c.id from classes c where s.class_id is null and s.cls = c.name;
update schedule sc set class_id = c.id from classes c where sc.class_id is null and sc.cls = c.name;

update details set class_id = (select id from classes where name = '유유히 시그니처 클래스' limit 1) where class_id is null and cls = '유유히 시그니처 담금주 클래스';
update slots set class_id = (select id from classes where name = '유유히 시그니처 클래스' limit 1) where class_id is null and cls = '유유히 시그니처 담금주 클래스';
update schedule set class_id = (select id from classes where name = '유유히 시그니처 클래스' limit 1) where class_id is null and cls = '유유히 시그니처 담금주 클래스';

-- 휴무일
create table if not exists holidays (
  id bigint generated always as identity primary key,
  branch text, sdate text
);

-- 클래스 신청 (컬럼화)
-- 주의: 예전엔 이 스크립트를 다시 돌릴 때마다 applications/inquiries를 drop cascade 로
-- 지우고 새로 만들었음 → 재실행할 때마다 신청/문의 데이터가 통째로 사라지고, status/pay_method/memo처럼
-- 나중에 수동으로 추가한 컬럼도 같이 사라지는 사고가 있었음. 이제는 데이터를 지우지 않고
-- 없는 컬럼만 추가하는 방식으로 바꿔서, 몇 번을 재실행해도 안전합니다.
create table if not exists applications (
  id bigint generated always as identity primary key,
  branch text, cls text, size text, sdate text, stime text, people int,
  name text, phone text, email text, msg text, estimate numeric,
  created_at timestamptz default now()
);
alter table applications add column if not exists status int default 1;
alter table applications add column if not exists pay_method text;
alter table applications add column if not exists memo text;

-- 신청건의 용량별 수량 (일대다)
create table if not exists application_items (
  id bigint generated always as identity primary key,
  application_id bigint references applications(id) on delete cascade,
  size text, qty int
);

-- 단체·기업·출강·특강 문의 (컬럼화)
create table if not exists inquiries (
  id bigint generated always as identity primary key,
  itype text, volume text, branch text, company text, name text, phone text,
  email text, isize text, msg text, created_at timestamptz default now()
);
alter table inquiries add column if not exists status int default 1;
alter table inquiries add column if not exists memo text;

-- ============================================================
-- RLS (접근 정책)
--   공개 콘텐츠 테이블: 조회는 전체 공개, 쓰기(추가/수정/삭제)는 로그인한 관리자만.
--   거래성 테이블(신청/문의): 등록(INSERT)은 누구나, 조회/수정/삭제는 로그인한 관리자만.
--   (자세한 내용과 media 스토리지 정책은 supabase-migration-security-rls.sql 참고)
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array[
    'site','legal','branches','classes','class_branches','details','slots','partners',
    'photos','photo_folders','schedule','holidays','concept_media'
  ] loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists "all_%s" on %I;', t, t);
    execute format('drop policy if exists "%s_select" on %I;', t, t);
    execute format('drop policy if exists "%s_write" on %I;', t, t);
    execute format('create policy "%s_select" on %I for select to public using (true);', t, t);
    execute format('create policy "%s_write" on %I for all to authenticated using (true) with check (true);', t, t);
  end loop;

  foreach t in array array['applications','application_items','inquiries'] loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists "all_%s" on %I;', t, t);
    execute format('drop policy if exists "%s_insert" on %I;', t, t);
    execute format('drop policy if exists "%s_admin" on %I;', t, t);
    execute format('create policy "%s_insert" on %I for insert to public with check (true);', t, t);
    execute format('create policy "%s_admin" on %I for all to authenticated using (true) with check (true);', t, t);
  end loop;
end $$;
