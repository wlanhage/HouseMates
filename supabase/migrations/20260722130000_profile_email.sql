-- Loginväljaren visar de två profilerna och loggar in med e-post.
-- E-posten lagras i profilen så klienten slipper hårdkoda konventioner.
alter table public.profiles add column email text not null default '';
