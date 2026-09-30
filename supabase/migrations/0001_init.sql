-- Focus timer: per-user tasks and completed focus/break sessions.
-- Every row belongs to auth.uid(); RLS limits each user (including anonymous users) to their own rows.

create table public.tasks (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 500),
  is_done     boolean not null default false,
  is_active   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create index tasks_user_updated_idx on public.tasks (user_id, updated_at);

alter table public.tasks enable row level security;

create policy "tasks: select own" on public.tasks
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "tasks: insert own" on public.tasks
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "tasks: update own" on public.tasks
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "tasks: delete own" on public.tasks
  for delete to authenticated using ((select auth.uid()) = user_id);

-- task_id is intentionally not a foreign key: sessions and tasks sync independently,
-- so a session can arrive before (or outlive) the task it referenced.
create table public.focus_sessions (
  id            uuid primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  task_id       uuid,
  mode          text not null check (mode in ('focus', 'rest')),
  started_at    timestamptz not null,
  ended_at      timestamptz not null,
  duration_sec  integer not null check (duration_sec > 0),
  created_at    timestamptz not null default now()
);

create index focus_sessions_user_ended_idx on public.focus_sessions (user_id, ended_at desc);

alter table public.focus_sessions enable row level security;

create policy "focus_sessions: select own" on public.focus_sessions
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "focus_sessions: insert own" on public.focus_sessions
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "focus_sessions: delete own" on public.focus_sessions
  for delete to authenticated using ((select auth.uid()) = user_id);
