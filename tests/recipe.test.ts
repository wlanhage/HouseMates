import { describe, it, expect } from 'vitest';
import {
  parseRecipeHtml,
  decodeEntities,
  stripSiteSuffix,
  coopRecipeId,
  parseCoopRecipe
} from '../src/lib/server/recipe-parse';

const page = (jsonLd: string, extraHead = '') =>
  `<!doctype html><html><head><title>Sidtitel | Sajten</title>${extraHead}
  <script type="application/ld+json">${jsonLd}</script></head><body>…</body></html>`;

describe('recipe-parse – schema.org/Recipe', () => {
  it('läser namn, bild och ingredienser ur ett Recipe-objekt', () => {
    const r = parseRecipeHtml(
      page(
        JSON.stringify({
          '@context': 'https://schema.org',
          '@type': 'Recipe',
          name: 'Kycklinggryta med curry',
          image: ['https://img.example/kyckling.jpg'],
          recipeIngredient: ['500 g kycklingfilé', '2 msk  curry ', '', '500 g kycklingfilé']
        })
      )
    );
    expect(r.name).toBe('Kycklinggryta med curry');
    expect(r.imageUrl).toBe('https://img.example/kyckling.jpg');
    expect(r.ingredients).toEqual(['500 g kycklingfilé', '2 msk curry']);
  });

  it('hittar receptet i @graph och tar bild ur ImageObject', () => {
    const r = parseRecipeHtml(
      page(
        JSON.stringify({
          '@context': 'https://schema.org',
          '@graph': [
            { '@type': 'WebPage', name: 'Sida' },
            {
              '@type': ['Recipe', 'Thing'],
              name: 'Tacos &amp; salsa',
              image: { '@type': 'ImageObject', url: 'https://img.example/tacos.jpg' },
              recipeIngredient: ['400 g köttfärs']
            }
          ]
        })
      )
    );
    expect(r.name).toBe('Tacos & salsa');
    expect(r.imageUrl).toBe('https://img.example/tacos.jpg');
    expect(r.ingredients).toEqual(['400 g köttfärs']);
  });

  it('hoppar över trasig JSON-LD och tar nästa block', () => {
    const html = `<html><head>
      <script type="application/ld+json">{ trasig json</script>
      <script type="application/ld+json">{"@type":"Recipe","name":"Pannkakor","recipeIngredient":["3 ägg"]}</script>
      </head></html>`;
    expect(parseRecipeHtml(html)).toEqual({ name: 'Pannkakor', imageUrl: null, ingredients: ['3 ägg'] });
  });

  it('utan receptdata: og:title/og:image, inga ingredienser', () => {
    const html = `<html><head><title>Fallback</title>
      <meta property="og:title" content="Mormors köttbullar" />
      <meta content="https://img.example/kb.jpg" property="og:image">
      </head></html>`;
    expect(parseRecipeHtml(html)).toEqual({
      name: 'Mormors köttbullar',
      imageUrl: 'https://img.example/kb.jpg',
      ingredients: []
    });
  });

  it('utan JSON-LD men med recipeIngredient i ett state-blob (t.ex. Arla)', () => {
    const html = `<html><head><meta property="og:title" content="Pannkakor"></head><body>
      <script>window.__STATE__={"recipe":{"recipeIngredient":["3 dl vetemjöl","6 dl mjölk","3 ägg","½ tsk salt [fint]"],"recipeInstructions":[]}}</script>
      </body></html>`;
    expect(parseRecipeHtml(html)).toEqual({
      name: 'Pannkakor',
      imageUrl: null,
      ingredients: ['3 dl vetemjöl', '6 dl mjölk', '3 ägg', '½ tsk salt [fint]']
    });
  });

  it('helt utan metadata: <title>', () => {
    expect(parseRecipeHtml('<html><head><title> Bara titel </title></head></html>')).toEqual({
      name: 'Bara titel',
      imageUrl: null,
      ingredients: []
    });
  });

  it('fallback-titel rensas från sajtsuffix', () => {
    expect(stripSiteSuffix('Getostsallad med körsbär | Recept - Coop')).toBe('Getostsallad med körsbär');
    expect(stripSiteSuffix('Pannkakor - Recept - Arla')).toBe('Pannkakor');
    expect(stripSiteSuffix('Pasta – snabb variant')).toBe('Pasta – snabb variant');
    const html = '<html><head><title>Getostsallad med k&#xF6;rsb&#xE4;r | Recept - Coop</title></head></html>';
    expect(parseRecipeHtml(html).name).toBe('Getostsallad med körsbär');
  });

  it('decodeEntities hanterar namngivna och numeriska entiteter', () => {
    expect(decodeEntities('Fisk &amp; skaldjur &#8211; gr&#xE4;dde&nbsp;')).toBe('Fisk & skaldjur – grädde ');
  });
});

describe('recipe-parse – Coop (klientrenderad sida + öppet API)', () => {
  it('hittar recept-id i dataLayer', () => {
    const html = '<script>window.dataLayer.push({"recipeName":"Getostsallad","recipeId":"5400883","page_type":"Receptsida"});</script>';
    expect(coopRecipeId(html)).toBe('5400883');
    expect(coopRecipeId('<html></html>')).toBeNull();
  });

  it('bygger ingrediensrader med svenskt decimalkomma och https-bild', () => {
    const r = parseCoopRecipe({
      name: 'Getostsallad med körsbär',
      imageUrl: 'http://res.cloudinary.com/coopsverige/image/upload/281377.jpg',
      recipePart: [
        {
          ingredients: [
            { name: 'körsbär', quantity: '300.0', unit: 'g', prePreparation: '', postPreparation: '' },
            { name: 'gurka', quantity: '0.5', unit: '', prePreparation: '', postPreparation: '' },
            { name: 'gul lök', quantity: '1.0', unit: '', prePreparation: 'finhackad', postPreparation: '' }
          ]
        },
        {
          ingredients: [
            { name: 'torkad timjan', quantity: '0.5', unit: 'tsk', prePreparation: '', postPreparation: '/rosmarin' },
            { name: 'salt', quantity: null, unit: '', prePreparation: '', postPreparation: '' }
          ]
        }
      ]
    });
    expect(r.name).toBe('Getostsallad med körsbär');
    expect(r.imageUrl).toBe('https://res.cloudinary.com/coopsverige/image/upload/281377.jpg');
    expect(r.ingredients).toEqual([
      '300 g körsbär',
      '0,5 gurka',
      '1 finhackad gul lök',
      '0,5 tsk torkad timjan /rosmarin',
      'salt'
    ]);
  });
});
