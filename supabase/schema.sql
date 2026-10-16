-- Lớp IELTS Writing | IELTS SPEEDING-UP — Ms Trâm English Hub
-- Chạy toàn bộ file này một lần trong Supabase → SQL Editor → New query → Run.

-- 1. Bảng dữ liệu ---------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  full_name  text not null default '',
  role       text not null default 'student' check (role in ('student','teacher')),
  created_at timestamptz not null default now()
);

create table if not exists public.essays (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  student_name text not null check (char_length(student_name) between 1 and 80),
  task         smallint not null check (task in (1, 2)),
  prompt       text not null check (char_length(prompt) <= 3000),
  body         text not null check (char_length(body) <= 20000),
  words        integer not null default 0,
  created_at   timestamptz not null default now()
);

create table if not exists public.feedback (
  essay_id    uuid primary key references public.essays on delete cascade,
  tr          smallint check (tr between 0 and 9),
  cc          smallint check (cc between 0 and 9),
  lr          smallint check (lr between 0 and 9),
  gra         smallint check (gra between 0 and 9),
  overall     numeric(2,1),
  comment     text not null default '',
  corrections jsonb not null default '[]'::jsonb,
  pdf_path    text,
  pdf_name    text,
  pdf_size    bigint,
  graded_at   timestamptz not null default now()
);

-- 2. Ai là giáo viên ------------------------------------------------------
create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'teacher');
$$;

-- Tự tạo hồ sơ (vai trò học sinh) khi có người đăng ký
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- 3. Quyền truy cập (Row Level Security) ----------------------------------
alter table public.profiles enable row level security;
alter table public.essays   enable row level security;
alter table public.feedback enable row level security;

drop policy if exists "profiles read"   on public.profiles;
drop policy if exists "profiles update" on public.profiles;
create policy "profiles read"   on public.profiles for select to authenticated using (true);
create policy "profiles update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
-- Học sinh chỉ sửa được họ tên, không tự đổi vai trò
revoke update on public.profiles from authenticated, anon;
grant  update (full_name) on public.profiles to authenticated;

drop policy if exists "essays read"   on public.essays;
drop policy if exists "essays insert" on public.essays;
drop policy if exists "essays delete" on public.essays;
create policy "essays read"   on public.essays for select to authenticated using (true);
create policy "essays insert" on public.essays for insert to authenticated with check (user_id = auth.uid());
create policy "essays delete" on public.essays for delete to authenticated using (
  public.is_teacher()
  or (user_id = auth.uid() and not exists (select 1 from public.feedback f where f.essay_id = essays.id))
);

drop policy if exists "feedback read"   on public.feedback;
drop policy if exists "feedback insert" on public.feedback;
drop policy if exists "feedback update" on public.feedback;
drop policy if exists "feedback delete" on public.feedback;
create policy "feedback read"   on public.feedback for select to authenticated using (true);
create policy "feedback insert" on public.feedback for insert to authenticated with check (public.is_teacher());
create policy "feedback update" on public.feedback for update to authenticated using (public.is_teacher()) with check (public.is_teacher());
create policy "feedback delete" on public.feedback for delete to authenticated using (public.is_teacher());

-- 4. Kho file PDF bài chấm ------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('graded', 'graded', false, 20971520, array['application/pdf'])
on conflict (id) do nothing;

drop policy if exists "graded read"   on storage.objects;
drop policy if exists "graded insert" on storage.objects;
drop policy if exists "graded update" on storage.objects;
drop policy if exists "graded delete" on storage.objects;
create policy "graded read"   on storage.objects for select to authenticated using (bucket_id = 'graded');
create policy "graded insert" on storage.objects for insert to authenticated with check (bucket_id = 'graded' and public.is_teacher());
create policy "graded update" on storage.objects for update to authenticated using (bucket_id = 'graded' and public.is_teacher());
create policy "graded delete" on storage.objects for delete to authenticated using (bucket_id = 'graded' and public.is_teacher());

-- 5. Cập nhật trực tiếp (bài mới, nhận xét mới hiện ngay) ------------------
do $$ begin
  alter publication supabase_realtime add table public.essays, public.feedback;
exception when duplicate_object then null; end $$;

-- 6. Đặt tài khoản giáo viên ----------------------------------------------
-- Sau khi bạn ĐĂNG KÝ trên web bằng email của mình, chạy dòng dưới
-- (thay email của bạn vào) để tài khoản đó thành giáo viên:
-- update public.profiles set role = 'teacher'
--   where id = (select id from auth.users where email = 'EMAIL_CUA_BAN@gmail.com');
