/** Små textformat som delas av flera vyer. */

/** Värdnamn utan www., för att visa varifrån ett recept kommer. */
export function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url;
  }
}

export function itemCountLabel(n: number): string {
  return n === 1 ? '1 vara' : `${n} varor`;
}
