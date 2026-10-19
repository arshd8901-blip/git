-- =====================================================================
-- JOBLY DATABASE SETUP (run ONCE in Supabase: SQL Editor -> New query -> paste -> Run)
-- Safe to re-run: it uses "if not exists" / "drop policy if exists".
-- Security model: Row Level Security (RLS) is ON for every table.
--   * Anyone can read APPROVED jobs only.
--   * Signed-in users can submit jobs, but only as 'pending' and never 'verified'.
--   * Each user can read/write only their own saved data.
--   * Reports and contact messages can be WRITTEN by the site but never READ by it.
--   * You (project owner) review and approve everything in the Table Editor.
-- =====================================================================

-- ---------- JOBS ----------
create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 80),
  company text not null check (char_length(company) between 2 and 80),
  city text not null check (char_length(city) between 2 and 60),
  zip text check (zip is null or zip ~ '^[0-9]{5}$'),
  lat double precision check (lat is null or lat between -90 and 90),
  lon double precision check (lon is null or lon between -180 and 180),
  job_type text not null check (job_type in ('Part-time','Full-time','Seasonal','Internship','Contract')),
  work_style text not null check (work_style in ('On-site','Remote','Hybrid')),
  min_pay numeric(6,2) not null check (min_pay > 0),
  max_pay numeric(6,2) not null check (max_pay >= min_pay and max_pay < 200),
  hrs_min int not null check (hrs_min between 1 and 40),
  hrs_max int not null check (hrs_max between 1 and 40 and hrs_max >= hrs_min),
  min_age int not null check (min_age in (16,17,18)),
  no_experience boolean not null default false,
  training boolean not null default false,
  transit boolean not null default false,
  season text check (season is null or season in ('summer','holiday')),
  is_flexible boolean not null default false,
  shifts text[] not null default '{}' check (cardinality(shifts) <= 21 and char_length(array_to_string(shifts, ',')) <= 250),
  tasks text[] not null default '{}' check (cardinality(tasks) <= 8 and char_length(array_to_string(tasks, ' ')) <= 800),
  description text not null check (char_length(description) between 10 and 600),
  restrictions text check (restrictions is null or char_length(restrictions) <= 300),
  apply_url text check (apply_url is null or (apply_url ~* '^https://[^[:space:]]+$' and char_length(apply_url) <= 500)),
  employer_verified boolean not null default false,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  submitted_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists jobs_status_idx on public.jobs (status, created_at desc);
create index if not exists jobs_submitter_idx on public.jobs (submitted_by);

-- Private employer contact details (never shown on the site)
create table if not exists public.job_private (
  job_id uuid primary key references public.jobs(id) on delete cascade,
  contact_email text not null check (contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' and char_length(contact_email) <= 254),
  contact_name text check (contact_name is null or char_length(contact_name) <= 80),
  created_at timestamptz not null default now()
);

-- Counts a user's waiting submissions (used to stop spam submissions)
create or replace function public.my_pending_jobs()
returns int language sql security definer stable set search_path = public as $$
  select count(*)::int from public.jobs where submitted_by = auth.uid() and status = 'pending'
$$;
revoke all on function public.my_pending_jobs() from public;
grant execute on function public.my_pending_jobs() to authenticated;

-- ---------- PER-USER SAVED DATA (availability, resume, tracker, saved searches) ----------
create table if not exists public.user_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  age int check (age is null or age in (16,17,18)),
  hours int check (hours is null or hours between 1 and 40),
  avail jsonb not null default '[]'::jsonb,
  resume jsonb not null default '{}'::jsonb,
  tracker jsonb not null default '[]'::jsonb,
  searches jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  check (octet_length(avail::text) < 3000 and octet_length(resume::text) < 20000
     and octet_length(tracker::text) < 100000 and octet_length(searches::text) < 12000)
);
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists user_data_touch on public.user_data;
create trigger user_data_touch before update on public.user_data for each row execute function public.touch_updated_at();

-- ---------- REPORTS & CONTACT (write-only from the website) ----------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  job_ref text not null check (char_length(job_ref) between 1 and 64),
  is_sample boolean not null default false,
  reason text not null check (reason in ('Asks for money or fees','Looks like a scam','Wrong pay or age information','Inappropriate or unsafe','Other')),
  details text check (details is null or char_length(details) <= 1000),
  reporter uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  email text not null check (char_length(email) between 3 and 254),
  topic text not null check (char_length(topic) between 1 and 60),
  message text not null check (char_length(message) between 3 and 2000),
  created_at timestamptz not null default now()
);

-- ---------- ROW LEVEL SECURITY ----------
alter table public.jobs enable row level security;
alter table public.job_private enable row level security;
alter table public.user_data enable row level security;
alter table public.reports enable row level security;
alter table public.contact_messages enable row level security;

drop policy if exists "anyone reads approved jobs" on public.jobs;
create policy "anyone reads approved jobs" on public.jobs for select to anon, authenticated using (status = 'approved');

drop policy if exists "owners read own jobs" on public.jobs;
create policy "owners read own jobs" on public.jobs for select to authenticated using (submitted_by = auth.uid());

drop policy if exists "signed-in users submit pending jobs" on public.jobs;
create policy "signed-in users submit pending jobs" on public.jobs for insert to authenticated
  with check (submitted_by = auth.uid() and status = 'pending' and employer_verified = false and public.my_pending_jobs() < 10);

drop policy if exists "owners insert private contact" on public.job_private;
create policy "owners insert private contact" on public.job_private for insert to authenticated
  with check (exists (select 1 from public.jobs j where j.id = job_id and j.submitted_by = auth.uid()));
drop policy if exists "owners read private contact" on public.job_private;
create policy "owners read private contact" on public.job_private for select to authenticated
  using (exists (select 1 from public.jobs j where j.id = job_id and j.submitted_by = auth.uid()));

drop policy if exists "users manage own data" on public.user_data;
create policy "users manage own data" on public.user_data for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "anyone can file a report" on public.reports;
create policy "anyone can file a report" on public.reports for insert to anon, authenticated with check (true);

drop policy if exists "anyone can send a message" on public.contact_messages;
create policy "anyone can send a message" on public.contact_messages for insert to anon, authenticated with check (true);

-- ---------- PERMISSIONS (RLS above still applies on top of these) ----------
grant usage on schema public to anon, authenticated;
grant select on public.jobs to anon, authenticated;
grant insert on public.jobs to authenticated;
grant select, insert on public.job_private to authenticated;
grant select, insert, update, delete on public.user_data to authenticated;
grant insert on public.reports to anon, authenticated;
grant insert on public.contact_messages to anon, authenticated;

-- =====================================================================
-- HOW YOU (THE ADMIN) USE IT
--  * Table Editor -> jobs: new employer submissions have status = pending.
--    Check the employer, then change status to approved (and tick employer_verified
--    once you've confirmed the business is real). Set "rejected" to hide.
--  * Table Editor -> job_private: the employer's contact email for each job.
--  * Table Editor -> reports / contact_messages: read what people sent.
-- You can add your own listings by inserting a row in jobs with status = approved.
-- =====================================================================
