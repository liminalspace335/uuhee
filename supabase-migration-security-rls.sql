-- ============================================================
-- 유유히 — RLS 강화 (관리자 로그인 기반)
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- 배경: 예전 정책(all_X, for all using(true) with check(true))은 site/branches 같은
-- 공개 콘텐츠 테이블뿐 아니라 applications/inquiries(고객 이름·연락처·이메일)까지
-- 누구나 anon key만으로 조회·수정·삭제할 수 있게 열어뒀음. 이 스크립트는 그 정책을
-- 지우고, "조회는 공개 / 쓰기는 로그인한 관리자만"으로 다시 잠근다.
-- (신청/문의 등록은 고객이 로그인 없이 해야 하므로 INSERT만 예외적으로 공개 유지)
--
-- 주의: Postgres RLS는 permissive 정책끼리 OR로 합쳐지므로, 기존 all_X 정책을
-- 반드시 먼저 DROP해야 새 제한 정책이 실제로 효력을 가진다(안 지우면 전체공개가 유지됨).
--
-- 실행 전 준비: Supabase 대시보드 → Authentication → Users 에서 관리자 계정을
-- 먼저 만들어두세요(admin.html의 로그인은 이 계정으로 인증합니다).
-- ============================================================

do $$
declare t text;
begin
  -- 공개 콘텐츠 테이블: 조회는 전체 공개, 쓰기(추가/수정/삭제)는 로그인한 관리자만
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

  -- 거래성 테이블(신청/문의): 등록(INSERT)은 누구나, 조회/수정/삭제는 로그인한 관리자만
  foreach t in array array['applications','application_items','inquiries'] loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists "all_%s" on %I;', t, t);
    execute format('drop policy if exists "%s_insert" on %I;', t, t);
    execute format('drop policy if exists "%s_admin" on %I;', t, t);
    execute format('create policy "%s_insert" on %I for insert to public with check (true);', t, t);
    execute format('create policy "%s_admin" on %I for all to authenticated using (true) with check (true);', t, t);
  end loop;
end $$;

-- ============================================================
-- media 스토리지 버킷: 읽기는 공개, 업로드/수정/삭제는 로그인한 관리자만
-- (예전엔 익명도 업로드/수정/삭제 가능했음 — 관리자만 되도록 제한)
-- ============================================================
drop policy if exists "media_read"   on storage.objects;
drop policy if exists "media_insert" on storage.objects;
drop policy if exists "media_update" on storage.objects;
drop policy if exists "media_delete" on storage.objects;
drop policy if exists "media_write"  on storage.objects;

create policy "media_read"  on storage.objects for select to public using (bucket_id = 'media');
create policy "media_write" on storage.objects for all to authenticated using (bucket_id = 'media') with check (bucket_id = 'media');
