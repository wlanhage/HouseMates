-- Våra middagar: favoriträtter vars ingredienser läggs på inköpslistan med ett tryck.
-- Samma modell som webbappen: ingredienserna sparas som råa rader ("500 g köttfärs") och delas
-- i vara och mängd först när de läggs på listan, så att handskrivna och importerade rätter
-- fungerar likadant. Ingen aktivitet: notisen kommer när varorna läggs på listan.

-- ── Mängd på inköpslistan ("Köttfärs · 500 g") ──────────────
alter table public.shopping_items add column qty text
  check (qty is null or char_length(qty) between 1 and 40);

-- ── Våra middagar ────────────────────────────────────────────
create table public.favorites (
  id           uuid primary key,             -- klientgenererat (offline-idempotens)
  household_id uuid not null default public.my_household_id()
               references public.households(id) on delete cascade,
  name         text not null check (char_length(trim(name)) between 1 and 120),
  items        text[] not null default '{}' check (cardinality(items) <= 100),
  image_url    text check (image_url ~ '^https://'),
  source_url   text check (source_url ~ '^https?://'),
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index favorites_by_household on public.favorites (household_id) where deleted_at is null;

create or replace function public.tg_favorites_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.name := trim(new.name);
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
  end if;
  return new;
end $$;
create trigger favorites_before before insert or update on public.favorites
  for each row execute function public.tg_favorites_before();

alter table public.favorites enable row level security;
create policy favorites_member on public.favorites for all
  using (household_id = public.my_household_id())
  with check (household_id = public.my_household_id());

alter publication supabase_realtime add table public.favorites;
