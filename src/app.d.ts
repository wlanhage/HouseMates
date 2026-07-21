// Typer för SvelteKit locals m.m. Byggs ut i M1 (auth).
declare global {
  namespace App {
    interface Locals {
      user: { id: string; name: string; color: string } | null;
    }
  }
}

export {};
