create extension if not exists "pgcrypto";

create type public.care_space_role as enum ('owner', 'admin', 'caregiver', 'viewer');
create type public.batch_status as enum ('observing', 'stable', 'needs_warmth', 'needs_vet', 'ready_for_adoption', 'adopted', 'closed');
create type public.kitten_status as enum ('active', 'watch', 'vet_care', 'ready_for_adoption', 'adopted', 'deceased');
create type public.kitten_size as enum ('small', 'normal', 'large');
create type public.stool_type as enum ('none', 'formed', 'soft', 'watery', 'bloody', 'mucus', 'other');
create type public.medical_log_type as enum ('vet_visit', 'vaccine', 'deworming', 'medication', 'exam', 'other');

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.care_spaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text unique,
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.care_space_members (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  role public.care_space_role not null default 'caregiver',
  created_at timestamptz not null default now(),
  unique (care_space_id, user_id)
);

create or replace function public.is_space_member(target_space_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.care_space_members m
    where m.care_space_id = target_space_id
      and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_space_admin(target_space_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.care_space_members m
    where m.care_space_id = target_space_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'admin')
  );
$$;

create or replace function public.create_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.care_space_members (care_space_id, user_id, display_name, role)
  values (
    new.id,
    new.owner_id,
    coalesce(nullif(auth.jwt() ->> 'email', ''), 'Owner'),
    'owner'
  )
  on conflict (care_space_id, user_id) do nothing;
  return new;
end;
$$;

create table public.care_batches (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  name text not null,
  found_date date,
  found_location text,
  status public.batch_status not null default 'observing',
  initial_medical_check text,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.kittens (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  batch_id uuid references public.care_batches(id) on delete set null,
  name text not null,
  days_old integer check (days_old is null or days_old between 0 and 180),
  size public.kitten_size not null default 'normal',
  status public.kitten_status not null default 'active',
  sex text check (sex is null or sex in ('unknown', 'female', 'male')),
  markings text,
  icon_index integer not null default 0 check (icon_index between 0 and 11),
  cover_photo_path text,
  google_album_url text,
  fixed_notes text,
  adopted_at date,
  adopter_name text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.care_logs (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  kitten_id uuid not null references public.kittens(id) on delete cascade,
  batch_id uuid references public.care_batches(id) on delete set null,
  recorded_at timestamptz not null default now(),
  caregiver_id uuid references auth.users(id) on delete set null default auth.uid(),
  caregiver_name text,
  milk_amount_ml numeric(6, 2) check (milk_amount_ml is null or milk_amount_ml >= 0),
  weight_g numeric(7, 2) check (weight_g is null or weight_g > 0),
  peed boolean not null default false,
  pooped boolean not null default false,
  stool public.stool_type not null default 'none',
  appetite text,
  energy text,
  temperature_note text,
  notes text,
  created_at timestamptz not null default now()
);

create table public.weight_logs (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  kitten_id uuid not null references public.kittens(id) on delete cascade,
  measured_at timestamptz not null default now(),
  weight_g numeric(7, 2) not null check (weight_g > 0),
  caregiver_id uuid references auth.users(id) on delete set null default auth.uid(),
  notes text,
  created_at timestamptz not null default now()
);

create table public.medical_logs (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  kitten_id uuid references public.kittens(id) on delete cascade,
  batch_id uuid references public.care_batches(id) on delete set null,
  log_date date not null default current_date,
  type public.medical_log_type not null,
  item text,
  clinic_name text,
  next_due_date date,
  dosage text,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (kitten_id is not null or batch_id is not null)
);

create table public.formula_logs (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  kitten_id uuid references public.kittens(id) on delete cascade,
  batch_id uuid references public.care_batches(id) on delete set null,
  brand text not null,
  product_name text,
  opened_on date,
  mixing_ratio text,
  is_active boolean not null default true,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (kitten_id is not null or batch_id is not null)
);

create table public.handoff_notes (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  batch_id uuid references public.care_batches(id) on delete set null,
  title text,
  summary text not null,
  shift_from text,
  shift_to text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.kitten_photos (
  id uuid primary key default gen_random_uuid(),
  care_space_id uuid not null references public.care_spaces(id) on delete cascade,
  kitten_id uuid not null references public.kittens(id) on delete cascade,
  batch_id uuid references public.care_batches(id) on delete set null,
  taken_on date not null default current_date,
  storage_bucket text not null default 'kitten-photos',
  storage_path text not null,
  caption text,
  is_cover boolean not null default false,
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (storage_bucket, storage_path)
);

create index care_space_members_user_id_idx on public.care_space_members (user_id);
create index care_batches_space_idx on public.care_batches (care_space_id, found_date desc);
create index kittens_space_batch_idx on public.kittens (care_space_id, batch_id, status);
create index care_logs_kitten_time_idx on public.care_logs (kitten_id, recorded_at desc);
create index weight_logs_kitten_time_idx on public.weight_logs (kitten_id, measured_at desc);
create index medical_logs_kitten_date_idx on public.medical_logs (kitten_id, log_date desc);
create index formula_logs_kitten_active_idx on public.formula_logs (kitten_id, is_active);
create index handoff_notes_space_time_idx on public.handoff_notes (care_space_id, created_at desc);
create index kitten_photos_kitten_date_idx on public.kitten_photos (kitten_id, taken_on desc);

create trigger set_care_spaces_updated_at
before update on public.care_spaces
for each row execute function public.set_updated_at();

create trigger create_care_space_owner_membership
after insert on public.care_spaces
for each row execute function public.create_owner_membership();

create trigger set_care_batches_updated_at
before update on public.care_batches
for each row execute function public.set_updated_at();

create trigger set_kittens_updated_at
before update on public.kittens
for each row execute function public.set_updated_at();

create trigger set_medical_logs_updated_at
before update on public.medical_logs
for each row execute function public.set_updated_at();

create trigger set_formula_logs_updated_at
before update on public.formula_logs
for each row execute function public.set_updated_at();

alter table public.care_spaces enable row level security;
alter table public.care_space_members enable row level security;
alter table public.care_batches enable row level security;
alter table public.kittens enable row level security;
alter table public.care_logs enable row level security;
alter table public.weight_logs enable row level security;
alter table public.medical_logs enable row level security;
alter table public.formula_logs enable row level security;
alter table public.handoff_notes enable row level security;
alter table public.kitten_photos enable row level security;

create policy "members can read care spaces"
on public.care_spaces for select
to authenticated
using (public.is_space_member(id));

create policy "authenticated users can create care spaces"
on public.care_spaces for insert
to authenticated
with check (owner_id = auth.uid());

create policy "admins can update care spaces"
on public.care_spaces for update
to authenticated
using (public.is_space_admin(id))
with check (public.is_space_admin(id));

create policy "members can read memberships"
on public.care_space_members for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "admins can manage memberships"
on public.care_space_members for all
to authenticated
using (public.is_space_admin(care_space_id))
with check (public.is_space_admin(care_space_id));

create policy "members can read batches"
on public.care_batches for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "members can insert batches"
on public.care_batches for insert
to authenticated
with check (public.is_space_member(care_space_id));

create policy "members can update batches"
on public.care_batches for update
to authenticated
using (public.is_space_member(care_space_id))
with check (public.is_space_member(care_space_id));

create policy "admins can delete batches"
on public.care_batches for delete
to authenticated
using (public.is_space_admin(care_space_id));

create policy "members can read kittens"
on public.kittens for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "members can insert kittens"
on public.kittens for insert
to authenticated
with check (public.is_space_member(care_space_id));

create policy "members can update kittens"
on public.kittens for update
to authenticated
using (public.is_space_member(care_space_id))
with check (public.is_space_member(care_space_id));

create policy "admins can delete kittens"
on public.kittens for delete
to authenticated
using (public.is_space_admin(care_space_id));

create policy "members can read care logs"
on public.care_logs for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "members can insert care logs"
on public.care_logs for insert
to authenticated
with check (public.is_space_member(care_space_id));

create policy "members can update care logs"
on public.care_logs for update
to authenticated
using (public.is_space_member(care_space_id))
with check (public.is_space_member(care_space_id));

create policy "admins can delete care logs"
on public.care_logs for delete
to authenticated
using (public.is_space_admin(care_space_id));

create policy "members can read weight logs"
on public.weight_logs for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "members can insert weight logs"
on public.weight_logs for insert
to authenticated
with check (public.is_space_member(care_space_id));

create policy "members can update weight logs"
on public.weight_logs for update
to authenticated
using (public.is_space_member(care_space_id))
with check (public.is_space_member(care_space_id));

create policy "admins can delete weight logs"
on public.weight_logs for delete
to authenticated
using (public.is_space_admin(care_space_id));

create policy "members can read medical logs"
on public.medical_logs for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "members can insert medical logs"
on public.medical_logs for insert
to authenticated
with check (public.is_space_member(care_space_id));

create policy "members can update medical logs"
on public.medical_logs for update
to authenticated
using (public.is_space_member(care_space_id))
with check (public.is_space_member(care_space_id));

create policy "admins can delete medical logs"
on public.medical_logs for delete
to authenticated
using (public.is_space_admin(care_space_id));

create policy "members can read formula logs"
on public.formula_logs for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "members can insert formula logs"
on public.formula_logs for insert
to authenticated
with check (public.is_space_member(care_space_id));

create policy "members can update formula logs"
on public.formula_logs for update
to authenticated
using (public.is_space_member(care_space_id))
with check (public.is_space_member(care_space_id));

create policy "admins can delete formula logs"
on public.formula_logs for delete
to authenticated
using (public.is_space_admin(care_space_id));

create policy "members can read handoff notes"
on public.handoff_notes for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "members can insert handoff notes"
on public.handoff_notes for insert
to authenticated
with check (public.is_space_member(care_space_id));

create policy "admins can delete handoff notes"
on public.handoff_notes for delete
to authenticated
using (public.is_space_admin(care_space_id));

create policy "members can read kitten photos"
on public.kitten_photos for select
to authenticated
using (public.is_space_member(care_space_id));

create policy "members can insert kitten photos"
on public.kitten_photos for insert
to authenticated
with check (public.is_space_member(care_space_id));

create policy "members can update kitten photos"
on public.kitten_photos for update
to authenticated
using (public.is_space_member(care_space_id))
with check (public.is_space_member(care_space_id));

create policy "admins can delete kitten photos"
on public.kitten_photos for delete
to authenticated
using (public.is_space_admin(care_space_id));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'kitten-photos',
  'kitten-photos',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "members can read kitten photo objects"
on storage.objects for select
to authenticated
using (
  bucket_id = 'kitten-photos'
  and name ~ '^[0-9a-fA-F-]{36}/'
  and public.is_space_member(((storage.foldername(name))[1])::uuid)
);

create policy "members can upload kitten photo objects"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'kitten-photos'
  and name ~ '^[0-9a-fA-F-]{36}/'
  and public.is_space_member(((storage.foldername(name))[1])::uuid)
);

create policy "members can update kitten photo objects"
on storage.objects for update
to authenticated
using (
  bucket_id = 'kitten-photos'
  and name ~ '^[0-9a-fA-F-]{36}/'
  and public.is_space_member(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'kitten-photos'
  and name ~ '^[0-9a-fA-F-]{36}/'
  and public.is_space_member(((storage.foldername(name))[1])::uuid)
);

create policy "admins can delete kitten photo objects"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'kitten-photos'
  and name ~ '^[0-9a-fA-F-]{36}/'
  and public.is_space_admin(((storage.foldername(name))[1])::uuid)
);
