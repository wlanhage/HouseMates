-- Radera konto inifrån appen (App Review 5.1.1(v)). Att ta bort raden i auth.users tar med sig
-- profil, medlemskap, push-token, egen aktivitet och väntande notiser (on delete cascade).
-- Varor man lagt till finns kvar för partnern utan koppling till personen (on delete set null).
-- Den sista i ett hushåll tar hela hushållet med sig, inklusive inköpslistan.
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  household uuid := my_household_id();
begin
  if me is null then raise exception 'Du är inte inloggad'; end if;
  -- Låset gör att två samtidiga raderingar i samma hushåll inte lämnar ett tomt hushåll kvar.
  perform 1 from households where id = household for update;
  delete from auth.users where id = me;
  delete from households h
  where h.id = household
    and not exists (select 1 from household_members m where m.household_id = h.id);
end $$;
