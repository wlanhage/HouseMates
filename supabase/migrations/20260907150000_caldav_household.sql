-- Kalendern kopplas via ETT Apple-ID per hushåll (användarbeslut 2026-09-07).
-- En delad iCloud-kalender har olika sökväg hos ägaren och hos den som fått
-- den delad; två kopplade konton skulle synka samma händelser om varandra och
-- skrivningar kunde hamna på fel konto. Partnern ser kalendern ändå: cachen
-- är hushållets, och skrivningar går via det kopplade kontot.

-- Vem har kopplat kalendern? (lösenordet lämnar aldrig servern)
create or replace function public.caldav_linked_by() returns text
language sql security definer set search_path = public stable as $$
  select username from caldav_accounts
  where public.is_member()
  order by updated_at limit 1
$$;

-- Koppla från: tar bort mitt konto, nollställer synkstatus och tömmer cachen
-- (den byggs om från kalendern vid nästa koppling).
create or replace function public.caldav_unlink() returns void
language plpgsql security definer set search_path = public as $$
declare me text := my_username();
begin
  if me is null then raise exception 'not a member'; end if;
  delete from caldav_accounts where username = me;
  update sync_state set last_synced_at = null, last_error = null, failing_since = null
    where username = me;
  if not exists (select 1 from caldav_accounts) then
    delete from events where true; -- pg-safeupdate kräver where
  end if;
end $$;
