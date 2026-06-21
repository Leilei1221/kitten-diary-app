create or replace function public.join_care_space_by_code(space_invite_code text, member_display_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_space_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select id
  into target_space_id
  from public.care_spaces
  where invite_code = space_invite_code;

  if target_space_id is null then
    raise exception 'Care space not found';
  end if;

  insert into public.care_space_members (care_space_id, user_id, display_name, role)
  values (
    target_space_id,
    auth.uid(),
    coalesce(nullif(member_display_name, ''), coalesce(auth.jwt() ->> 'email', 'Caregiver')),
    'caregiver'
  )
  on conflict (care_space_id, user_id) do update set
    display_name = excluded.display_name;

  return target_space_id;
end;
$$;
