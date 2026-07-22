-- Loginsidan listar inte längre användare (man skriver användarnamn),
-- så profiler behöver inte vara publikt läsbara. Endast medlemmar.
drop policy if exists profiles_public_read on public.profiles;
create policy profiles_member_read on public.profiles
  for select using (public.is_member());
