-- ============================================================
-- 유유히 — 문의 저장을 위한 전용 함수(RPC) 추가
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- 배경: applications와 마찬가지로, inquiries도 로그인 안 한 고객은 SELECT가
-- 막혀있어(supabase-migration-security-rls.sql) 저장 직후 새로 생긴 행의
-- id를 돌려받을 방법이 없었다. 문의 접수 시 자동으로 카카오 알림톡을 보내려면
-- 그 id가 필요하므로, 관리자 권한(SECURITY DEFINER)으로 저장하고 새 id를
-- 돌려주는 함수를 추가한다.
-- ============================================================

create or replace function uuhee_submit_inquiry(
  p_itype text,
  p_volume text,
  p_branch text,
  p_company text,
  p_name text,
  p_phone text,
  p_email text,
  p_isize text,
  p_msg text,
  p_status int default 1
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id bigint;
begin
  insert into inquiries(itype, volume, branch, company, name, phone, email, isize, msg, status)
  values (p_itype, p_volume, p_branch, p_company, p_name, p_phone, p_email, p_isize, p_msg, coalesce(p_status, 1))
  returning id into new_id;

  return new_id;
end;
$$;

grant execute on function uuhee_submit_inquiry(text,text,text,text,text,text,text,text,text,int) to anon, authenticated;
