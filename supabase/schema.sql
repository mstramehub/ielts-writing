-- Ms Trâm English Hub — Web nộp bài IELTS Writing (nhiều lớp)
-- Chạy TOÀN BỘ file này trong Supabase → SQL Editor → New query → Run.
-- Chạy lại nhiều lần vẫn an toàn: không xoá bài, điểm hay file đã có.

-- 1. Bảng dữ liệu ---------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  full_name  text not null default '',
  role       text not null default 'student' check (role in ('student','teacher')),
  created_at timestamptz not null default now()
);

-- Lớp học: mỗi lớp có một mã để học sinh tham gia
create table if not exists public.classes (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 120),
  code       text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6))
             check (code ~ '^[A-Z0-9-]{4,20}$'),
  created_at timestamptz not null default now()
);

-- Học sinh nào thuộc lớp nào (một học sinh có thể học nhiều lớp)
create table if not exists public.class_members (
  class_id  uuid not null references public.classes on delete cascade,
  user_id   uuid not null references public.profiles on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (class_id, user_id)
);

create table if not exists public.essays (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  student_name text not null check (char_length(student_name) between 1 and 80),
  task         smallint not null check (task in (1, 2)),
  prompt       text not null check (char_length(prompt) <= 3000),
  body         text not null default '' check (char_length(body) <= 20000),
  words        integer not null default 0,
  created_at   timestamptz not null default now()
);
alter table public.essays add column if not exists file_path text;
alter table public.essays add column if not exists file_name text;
alter table public.essays add column if not exists file_size bigint;
alter table public.essays add column if not exists class_id  uuid references public.classes on delete cascade;
alter table public.essays alter column body set default '';
create index if not exists essays_class_idx on public.essays (class_id, created_at desc);

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

-- 2. Hồ sơ người dùng -----------------------------------------------------
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

-- Tạo bù hồ sơ cho tài khoản đăng ký trước khi có trigger
insert into public.profiles (id, full_name)
select u.id, coalesce(u.raw_user_meta_data->>'full_name', '') from auth.users u
on conflict (id) do nothing;

-- 3. Hàm kiểm tra quyền ---------------------------------------------------
create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'teacher');
$$;

create or replace function public.is_member(p_class uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.class_members where class_id = p_class and user_id = auth.uid());
$$;

-- Người xem có được đọc bài này không (giáo viên, hoặc cùng lớp)
create or replace function public.can_read_essay(p_essay uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_teacher() or exists (
    select 1 from public.essays e
    join public.class_members m on m.class_id = e.class_id and m.user_id = auth.uid()
    where e.id = p_essay);
$$;

-- 4. Chuyển dữ liệu cũ sang lớp đầu tiên (chỉ chạy khi cần) ----------------
do $$
declare v_id uuid;
begin
  if not exists (select 1 from public.classes) then
    insert into public.classes (name) values ('LỚP IELTS Writing | IELTS SPEEDING-UP') returning id into v_id;
    -- Học sinh đã đăng ký trước đó được xếp vào lớp này
    insert into public.class_members (class_id, user_id)
      select v_id, p.id from public.profiles p where p.role = 'student'
      on conflict do nothing;
  end if;
  select id into v_id from public.classes order by created_at limit 1;
  update public.essays set class_id = v_id where class_id is null;
  insert into public.class_members (class_id, user_id)
    select distinct e.class_id, e.user_id from public.essays e
    join public.profiles p on p.id = e.user_id
    on conflict do nothing;
end $$;

-- 5. Thao tác qua hàm -----------------------------------------------------
-- Học sinh nhập mã lớp để tham gia
create or replace function public.join_class(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare v_class public.classes;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into v_class from public.classes where code = upper(trim(p_code));
  if not found then raise exception 'invalid_code'; end if;
  insert into public.profiles (id, full_name)
    select auth.uid(), coalesce((select raw_user_meta_data->>'full_name' from auth.users where id = auth.uid()), '')
    on conflict (id) do nothing;
  insert into public.class_members (class_id, user_id) values (v_class.id, auth.uid())
    on conflict do nothing;
  return json_build_object('id', v_class.id, 'name', v_class.name);
end $$;

-- Danh sách học sinh của một lớp (chỉ giáo viên)
create or replace function public.class_roster(p_class uuid)
returns table (user_id uuid, full_name text, email text, joined_at timestamptz, essays bigint)
language sql stable security definer set search_path = public as $$
  select m.user_id, p.full_name, u.email::text, m.joined_at,
         (select count(*) from public.essays e where e.class_id = m.class_id and e.user_id = m.user_id)
  from public.class_members m
  join public.profiles p on p.id = m.user_id
  join auth.users u on u.id = m.user_id
  where m.class_id = p_class and public.is_teacher()
  order by p.full_name;
$$;

-- Số liệu từng lớp (chỉ giáo viên)
create or replace function public.class_stats()
returns table (class_id uuid, students bigint, essays bigint, pending bigint)
language sql stable security definer set search_path = public as $$
  select c.id,
    (select count(*) from public.class_members m where m.class_id = c.id),
    (select count(*) from public.essays e where e.class_id = c.id),
    (select count(*) from public.essays e where e.class_id = c.id
       and not exists (select 1 from public.feedback f where f.essay_id = e.id))
  from public.classes c
  where public.is_teacher();
$$;

revoke execute on function public.join_class(text)    from anon;
revoke execute on function public.class_roster(uuid)  from anon;
revoke execute on function public.class_stats()       from anon;
grant  execute on function public.join_class(text)    to authenticated;
grant  execute on function public.class_roster(uuid)  to authenticated;
grant  execute on function public.class_stats()       to authenticated;

-- 6. Quyền truy cập (Row Level Security) ----------------------------------
alter table public.profiles      enable row level security;
alter table public.classes       enable row level security;
alter table public.class_members enable row level security;
alter table public.essays        enable row level security;
alter table public.feedback      enable row level security;

drop policy if exists "profiles read"   on public.profiles;
drop policy if exists "profiles update" on public.profiles;
create policy "profiles read"   on public.profiles for select to authenticated using (true);
create policy "profiles update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
-- Học sinh chỉ sửa được họ tên, không tự đổi vai trò
revoke update on public.profiles from authenticated, anon;
grant  update (full_name) on public.profiles to authenticated;

drop policy if exists "classes read"   on public.classes;
drop policy if exists "classes insert" on public.classes;
drop policy if exists "classes update" on public.classes;
drop policy if exists "classes delete" on public.classes;
create policy "classes read"   on public.classes for select to authenticated using (public.is_teacher() or public.is_member(id));
create policy "classes insert" on public.classes for insert to authenticated with check (public.is_teacher());
create policy "classes update" on public.classes for update to authenticated using (public.is_teacher()) with check (public.is_teacher());
create policy "classes delete" on public.classes for delete to authenticated using (public.is_teacher());

drop policy if exists "members read"   on public.class_members;
drop policy if exists "members delete" on public.class_members;
create policy "members read"   on public.class_members for select to authenticated using (public.is_teacher() or user_id = auth.uid());
create policy "members delete" on public.class_members for delete to authenticated using (public.is_teacher() or user_id = auth.uid());
-- Thêm thành viên chỉ qua hàm join_class (nhập mã lớp)

drop policy if exists "essays read"   on public.essays;
drop policy if exists "essays insert" on public.essays;
drop policy if exists "essays delete" on public.essays;
create policy "essays read"   on public.essays for select to authenticated
  using (public.is_teacher() or public.is_member(class_id));
create policy "essays insert" on public.essays for insert to authenticated
  with check (user_id = auth.uid() and (public.is_member(class_id) or public.is_teacher()));
create policy "essays delete" on public.essays for delete to authenticated using (
  public.is_teacher()
  or (user_id = auth.uid() and not exists (select 1 from public.feedback f where f.essay_id = essays.id))
);

drop policy if exists "feedback read"   on public.feedback;
drop policy if exists "feedback insert" on public.feedback;
drop policy if exists "feedback update" on public.feedback;
drop policy if exists "feedback delete" on public.feedback;
create policy "feedback read"   on public.feedback for select to authenticated using (public.can_read_essay(essay_id));
create policy "feedback insert" on public.feedback for insert to authenticated with check (public.is_teacher());
create policy "feedback update" on public.feedback for update to authenticated using (public.is_teacher()) with check (public.is_teacher());
create policy "feedback delete" on public.feedback for delete to authenticated using (public.is_teacher());

-- 7. Kho file PDF bài chấm (thư mục = mã bài) ------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('graded', 'graded', false, 20971520, array['application/pdf'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "graded read"   on storage.objects;
drop policy if exists "graded insert" on storage.objects;
drop policy if exists "graded update" on storage.objects;
drop policy if exists "graded delete" on storage.objects;
create policy "graded read" on storage.objects for select to authenticated
  using (bucket_id = 'graded' and (public.is_teacher() or exists (
    select 1 from public.essays e
    where e.id::text = (storage.foldername(name))[1] and public.is_member(e.class_id))));
create policy "graded insert" on storage.objects for insert to authenticated with check (bucket_id = 'graded' and public.is_teacher());
create policy "graded update" on storage.objects for update to authenticated using (bucket_id = 'graded' and public.is_teacher());
create policy "graded delete" on storage.objects for delete to authenticated using (bucket_id = 'graded' and public.is_teacher());

-- 8. Kho file bài nộp của học sinh (thư mục = mã tài khoản) ----------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('submissions', 'submissions', false, 20971520, array[
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'image/jpeg', 'image/png'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "submissions read"   on storage.objects;
drop policy if exists "submissions insert" on storage.objects;
drop policy if exists "submissions delete" on storage.objects;
create policy "submissions read" on storage.objects for select to authenticated
  using (bucket_id = 'submissions' and (
    public.is_teacher()
    or (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.essays e where e.file_path = storage.objects.name and public.is_member(e.class_id))));
create policy "submissions insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'submissions' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "submissions delete" on storage.objects for delete to authenticated
  using (bucket_id = 'submissions' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_teacher()));

-- 9. Cập nhật trực tiếp (bài mới, nhận xét mới hiện ngay) ------------------
do $$ begin
  alter publication supabase_realtime add table public.essays;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.feedback;
exception when duplicate_object then null; end $$;

-- 10. Đặt tài khoản giáo viên ---------------------------------------------
-- Sau khi ĐĂNG KÝ trên web bằng email của bạn, chạy dòng dưới (thay email):
-- update public.profiles set role = 'teacher'
--   where id = (select id from auth.users where email = 'EMAIL_CUA_BAN@gmail.com');
--
-- Xem ai đang là giáo viên:
-- select u.email, p.full_name, p.role from public.profiles p join auth.users u on u.id = p.id order by p.role desc;
