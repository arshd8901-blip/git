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
-- v4 upgrade: checklist progress + interview practice notes (safe to run again)
alter table public.user_data add column if not exists checklist jsonb not null default '[]'::jsonb;
alter table public.user_data add column if not exists practice jsonb not null default '{}'::jsonb;
alter table public.user_data drop constraint if exists user_data_v4_limits;
alter table public.user_data add constraint user_data_v4_limits check (
  jsonb_typeof(checklist) = 'array' and jsonb_typeof(practice) = 'object'
  and octet_length(checklist::text) < 2000 and octet_length(practice::text) < 25000);
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
-- v5: TEEN PROFILES + EMPLOYER TALENT SEARCH (safe to run again)
--  * Profiles are private until the teen turns "visible" on. Only VERIFIED employers can see them.
--  * Profiles have no email, phone, school, address or photo. Initials are drawn by the website.
--  * An employer sends a "hire interest" request. The teen's contact email is revealed only after they accept.
--  * Teens can block and report. You (admin) verify employers and can hide any profile.
-- =====================================================================
create table if not exists public.employers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  company text not null check (char_length(company) between 2 and 80),
  website text check (website is null or (website ~* '^https://' and char_length(website) <= 300)),
  note text check (note is null or char_length(note) <= 500),
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 40 and display_name ~ '^[[:alpha:]][[:alpha:] .''-]*$'),
  age_group int not null check (age_group in (16,17,18)),
  area text check (area is null or (char_length(area) <= 60 and area !~ '[0-9@:/]')),
  bio text check (bio is null or (char_length(bio) <= 300
      and bio !~* '(https?://|www\.|[[:alnum:]._-]+@[[:alnum:].-]+|(^|[^0-9])(\(?[0-9]{3}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}|[0-9]{3}[ .-][0-9]{4})([^0-9]|$))')),
  interests jsonb not null default '[]'::jsonb
      check (jsonb_typeof(interests) = 'array' and jsonb_array_length(interests) <= 6
             and interests <@ '["food","retail","kids","rec","office","events"]'::jsonb),
  avail jsonb not null default '[]'::jsonb check (jsonb_typeof(avail) = 'array' and octet_length(avail::text) < 3000),
  visible boolean not null default false,
  share_resume boolean not null default false,
  hidden_by_admin boolean not null default false,
  consented_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();

-- A resume copy the teen chose to share. It never includes their email, phone or links.
create table if not exists public.profile_resumes (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  resume jsonb not null check (jsonb_typeof(resume) = 'object' and octet_length(resume::text) < 20000
      and resume::text !~* '(https?://|www\.|[[:alnum:]._-]+@[[:alnum:].-]+\.[a-z]{2,}|(^|[^0-9])(\(?[0-9]{3}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}|[0-9]{3}[ .-][0-9]{4})([^0-9]|$))'),
  updated_at timestamptz not null default now()
);

-- Email the teen is willing to give an employer AFTER they accept a request.
create table if not exists public.profile_contact (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  email text not null check (char_length(email) <= 120 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

create table if not exists public.interest_requests (
  id uuid primary key default gen_random_uuid(),
  employer_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  teen_id uuid not null references public.profiles(user_id) on delete cascade,
  company text,
  website text,
  message text not null check (char_length(message) between 10 and 300
      and message !~* '(https?://|www\.|[[:alnum:]._-]+@[[:alnum:].-]+|(^|[^0-9])(\(?[0-9]{3}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}|[0-9]{3}[ .-][0-9]{4})([^0-9]|$))'),
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  unique (employer_id, teen_id)
);
create index if not exists interest_teen_idx on public.interest_requests(teen_id);

create table if not exists public.blocks (
  teen_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  employer_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (teen_id, employer_id)
);

create table if not exists public.profile_reports (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null,
  reason text not null check (reason in ('Looks fake or inappropriate','Shares contact details','Seems under 16','Other')),
  details text check (details is null or char_length(details) <= 1000),
  reporter uuid default auth.uid(),
  created_at timestamptz not null default now()
);

-- ---------- helper functions (they run with extra rights so the rules can check tables the caller can't read) ----------
create or replace function public.is_verified_employer() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.employers where user_id = auth.uid() and status = 'verified')
$$;
create or replace function public.employer_can_view(teen uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select public.is_verified_employer()
     and exists (select 1 from public.profiles p where p.user_id = teen and p.visible and not p.hidden_by_admin)
     and not exists (select 1 from public.blocks b where b.teen_id = teen and b.employer_id = auth.uid())
$$;
create or replace function public.employer_can_view_resume(teen uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select public.employer_can_view(teen) and exists (select 1 from public.profiles p where p.user_id = teen and p.share_resume)
$$;
create or replace function public.employer_can_view_contact(teen uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select public.is_verified_employer()
     and exists (select 1 from public.interest_requests r where r.employer_id = auth.uid() and r.teen_id = teen and r.status = 'accepted')
     and not exists (select 1 from public.blocks b where b.teen_id = teen and b.employer_id = auth.uid())
$$;
create or replace function public.my_requests_today() returns int
language sql security definer stable set search_path = public as $$
  select count(*)::int from public.interest_requests where employer_id = auth.uid() and created_at > now() - interval '1 day'
$$;
create or replace function public.stamp_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select e.company, e.website into new.company, new.website from public.employers e where e.user_id = new.employer_id;
  return new;
end $$;
drop trigger if exists interest_stamp on public.interest_requests;
create trigger interest_stamp before insert on public.interest_requests for each row execute function public.stamp_request();
revoke all on function public.is_verified_employer(), public.employer_can_view(uuid), public.employer_can_view_resume(uuid),
  public.employer_can_view_contact(uuid), public.my_requests_today() from public;
grant execute on function public.is_verified_employer(), public.employer_can_view(uuid), public.employer_can_view_resume(uuid),
  public.employer_can_view_contact(uuid), public.my_requests_today() to authenticated;

-- ---------- ROW LEVEL SECURITY ----------
alter table public.employers enable row level security;
alter table public.profiles enable row level security;
alter table public.profile_resumes enable row level security;
alter table public.profile_contact enable row level security;
alter table public.interest_requests enable row level security;
alter table public.blocks enable row level security;
alter table public.profile_reports enable row level security;

drop policy if exists "employers read own" on public.employers;
create policy "employers read own" on public.employers for select to authenticated using (user_id = auth.uid());
drop policy if exists "employers apply" on public.employers;
create policy "employers apply" on public.employers for insert to authenticated with check (user_id = auth.uid() and status = 'pending');
drop policy if exists "employers withdraw" on public.employers;
create policy "employers withdraw" on public.employers for delete to authenticated using (user_id = auth.uid());

drop policy if exists "profiles owner reads" on public.profiles;
create policy "profiles owner reads" on public.profiles for select to authenticated using (user_id = auth.uid());
drop policy if exists "profiles employers read" on public.profiles;
create policy "profiles employers read" on public.profiles for select to authenticated using (public.employer_can_view(user_id));
drop policy if exists "profiles owner writes" on public.profiles;
create policy "profiles owner writes" on public.profiles for insert to authenticated with check (user_id = auth.uid() and hidden_by_admin = false);
drop policy if exists "profiles owner updates" on public.profiles;
create policy "profiles owner updates" on public.profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "profiles owner deletes" on public.profiles;
create policy "profiles owner deletes" on public.profiles for delete to authenticated using (user_id = auth.uid());

drop policy if exists "resume owner" on public.profile_resumes;
create policy "resume owner" on public.profile_resumes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "resume employers read" on public.profile_resumes;
create policy "resume employers read" on public.profile_resumes for select to authenticated using (public.employer_can_view_resume(user_id));

drop policy if exists "contact owner" on public.profile_contact;
create policy "contact owner" on public.profile_contact for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "contact after accept" on public.profile_contact;
create policy "contact after accept" on public.profile_contact for select to authenticated using (public.employer_can_view_contact(user_id));

drop policy if exists "requests read own" on public.interest_requests;
create policy "requests read own" on public.interest_requests for select to authenticated using (employer_id = auth.uid() or teen_id = auth.uid());
drop policy if exists "verified employers send" on public.interest_requests;
create policy "verified employers send" on public.interest_requests for insert to authenticated
  with check (employer_id = auth.uid() and status = 'pending' and public.employer_can_view(teen_id) and public.my_requests_today() < 20);
drop policy if exists "teens answer" on public.interest_requests;
create policy "teens answer" on public.interest_requests for update to authenticated using (teen_id = auth.uid()) with check (teen_id = auth.uid() and status in ('accepted','declined'));
drop policy if exists "employers withdraw request" on public.interest_requests;
create policy "employers withdraw request" on public.interest_requests for delete to authenticated using (employer_id = auth.uid());

drop policy if exists "teens manage blocks" on public.blocks;
create policy "teens manage blocks" on public.blocks for all to authenticated using (teen_id = auth.uid()) with check (teen_id = auth.uid());

drop policy if exists "signed-in users report profiles" on public.profile_reports;
create policy "signed-in users report profiles" on public.profile_reports for insert to authenticated with check (true);

-- ---------- PERMISSIONS (column-level where it matters) ----------
revoke all on public.employers, public.profiles, public.profile_resumes, public.profile_contact,
  public.interest_requests, public.blocks, public.profile_reports from anon, authenticated;
grant select, delete on public.employers to authenticated;
grant insert (user_id, company, website, note) on public.employers to authenticated;
grant select, delete on public.profiles to authenticated;
grant insert (user_id, display_name, age_group, area, bio, interests, avail, visible, share_resume, consented_at) on public.profiles to authenticated;
grant update (display_name, age_group, area, bio, interests, avail, visible, share_resume) on public.profiles to authenticated;
grant select, insert, update, delete on public.profile_resumes to authenticated;
grant select, insert, update, delete on public.profile_contact to authenticated;
grant select, delete on public.interest_requests to authenticated;
grant insert (teen_id, message) on public.interest_requests to authenticated;
grant update (status) on public.interest_requests to authenticated;
grant select, insert, delete on public.blocks to authenticated;
grant insert on public.profile_reports to authenticated;

-- =====================================================================
-- HOW YOU (THE ADMIN) USE IT
--  * Table Editor -> jobs: new employer submissions have status = pending.
--    Check the employer, then change status to approved (and tick employer_verified
--    once you've confirmed the business is real). Set "rejected" to hide.
--  * Table Editor -> job_private: the employer's contact email for each job.
--  * Table Editor -> reports / contact_messages: read what people sent.
--  * Table Editor -> employers: people who asked to browse teen profiles have status = pending.
--    Check their company/website, then set status to verified (or rejected). Only verified can browse.
--  * Table Editor -> profile_reports: reports about teen profiles. In profiles, tick hidden_by_admin to hide one.
-- You can add your own listings by inserting a row in jobs with status = approved.
-- =====================================================================
