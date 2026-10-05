-- Lämna hushållet. Den sista medlemmen tar hushållet med inköpslistan med sig; annars blir
-- listan kvar för partnern och inbjudningskoden byts, så att den som lämnade inte kan gå
-- med igen med den gamla. Notiser som väntar till den som lämnar slängs.
create or replace function public.leave_household() returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  household uuid := my_household_id();
begin
  if me is null then raise exception 'Du är inte inloggad'; end if;
  if household is null then return; end if;
  -- Låset gör att två som lämnar samtidigt inte lämnar ett tomt hushåll kvar.
  perform 1 from households where id = household for update;
  delete from household_members where household_id = household and user_id = me;
  delete from notification_queue q using activity_log a
  where q.activity_id = a.id and q.recipient = me and a.household_id = household;
  delete from households h
  where h.id = household
    and not exists (select 1 from household_members m where m.household_id = h.id);
  update households set invite_code = new_invite_code() where id = household;
end $$;

-- Radera konto = lämna hushållet och ta bort inloggningen. Profil, push-token, egen aktivitet
-- och återstående notiser följer med via on delete cascade.
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Du är inte inloggad'; end if;
  perform leave_household();
  delete from auth.users where id = auth.uid();
end $$;
