-- User-defined task order: lowest sort_index first. New tasks get a lower value than
-- every existing one so the newest task shows under the timer by default.
alter table public.tasks
  add column sort_index double precision not null default 0;
