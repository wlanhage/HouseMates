-- Anteckningar på uppgifter, som i webbappen ("Anteckningar (valfritt)").
alter table public.todos add column notes text check (char_length(notes) <= 1000);
