-- ============================================================
-- 유유히 — schedule(클래스설정/캘린더) 중복 데이터 정리
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣고 Run
--
-- 원인: admin.html의 저장 함수(repl)가 "기존 id 조회 → 새 데이터 insert → 기존 id delete"
-- 순서로 동작하는데, 예전 코드는 id 조회에 페이지네이션이 없어 행이 많아지면(기본 응답 제한 1000행)
-- 일부 id만 가져와 그만큼만 삭제되고, 게다가 delete 실패 여부도 검사하지 않아 실패가 조용히 무시됐습니다.
-- 그 결과 저장할 때마다 예전 스케줄 데이터가 지워지지 않고 계속 쌓여, 캘린더를 조회할 때마다
-- 같은 (지점·날짜·시간) 슬롯이 여러 번(최대 10번) 중복돼서 다르게 보이는 원인이 됐습니다.
-- 저장 로직 자체는 admin.html에서 이미 수정했고, 이 스크립트는 지금까지 쌓인 중복만 정리합니다.
-- ============================================================

-- 1) 정리 전 확인: 중복 그룹 개수와 전체 행 수를 먼저 확인해보세요.
-- select count(*) as total_rows from schedule;
-- select branch, sdate, stime, class_id, count(*) from schedule
--   group by branch, sdate, stime, class_id having count(*) > 1
--   order by count(*) desc;

-- 2) 중복 제거: 같은 (branch, sdate, stime, class_id) 조합 중 가장 최근에 만들어진(id가 가장 큰) 행만 남기고 나머지는 삭제
delete from schedule a using schedule b
where a.branch = b.branch
  and a.sdate = b.sdate
  and a.stime = b.stime
  and coalesce(a.class_id, -1) = coalesce(b.class_id, -1)
  and a.id < b.id;

-- 3) 정리 후 확인 (중복이 남아있지 않아야 정상)
-- select branch, sdate, stime, class_id, count(*) from schedule
--   group by branch, sdate, stime, class_id having count(*) > 1;
-- select count(*) as total_rows_after from schedule;
