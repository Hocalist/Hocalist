import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { seedUsbQaCatalogue } from './usb_qa_catalogue.mjs';

const foundation = await readFile(new URL('../marketplace/020_marketplace_foundation.sql', import.meta.url), 'utf8');
const ddl = foundation.slice(foundation.indexOf('CREATE TABLE hocalist.catalogue_categories'), foundation.indexOf('-- Dynamic locations.'));
const migration = await readFile(new URL('../../supabase/migrations/20261126170000_marketplace_reviewed_catalogue.sql', import.meta.url), 'utf8');
async function catalogue(db) {
  return (await db.query(`SELECT c.slug,c.label,c.scope,c.sort_order,p.slug AS parent,
    g.label AS question,g.selection_mode,g.is_required,g.sort_order AS question_order,
    o.label AS choice,o.sort_order AS choice_order
    FROM hocalist.catalogue_categories c
    LEFT JOIN hocalist.catalogue_categories p ON p.id=c.parent_id
    LEFT JOIN hocalist.catalogue_option_groups g ON g.category_id=c.id
    LEFT JOIN hocalist.catalogue_options o ON o.group_id=g.id
    ORDER BY c.slug,g.sort_order,g.label,o.sort_order,o.label`)).rows;
}

test('reviewed catalogue matches the owner fixture and preserves existing records', async () => {
  const db = new PGlite(), reference = new PGlite();
  try {
    for (const instance of [db, reference]) await instance.exec('CREATE SCHEMA hocalist;'+ddl);
    await seedUsbQaCatalogue(reference);
    const old = [
      ['electronics','Electronics','product'],['home-furniture','Home & furniture','product'],
      ['clothing-accessories','Clothing & accessories','product'],['sports-outdoors','Sports & outdoors','product'],
      ['tools-equipment','Tools & equipment','product'],['cleaning','Cleaning','service'],
      ['home-repairs','Home repairs','service'],['lawn-garden-care','Lawn & garden care','service'],
      ['moving-delivery','Moving & delivery','service'],['tech-support','Tech support','service'],
    ];
    for (const [slug,label,scope] of old) await db.query(
      'INSERT INTO hocalist.catalogue_categories(slug,label,scope) VALUES($1,$2,$3)',[slug,label,scope]);
    const before=(await db.query('SELECT id,slug FROM hocalist.catalogue_categories ORDER BY slug')).rows;
    await db.exec(`CREATE TABLE existing_request(category_id uuid REFERENCES hocalist.catalogue_categories(id));
      INSERT INTO existing_request SELECT id FROM hocalist.catalogue_categories WHERE slug='electronics';`);
    await db.exec(migration);
    assert.deepEqual(await catalogue(db),await catalogue(reference));
    for (const row of before) assert.equal((await db.query('SELECT id FROM hocalist.catalogue_categories WHERE slug=$1',[row.slug])).rows[0].id,row.id);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM existing_request')).rows[0].n,1);
    const snapshot=await catalogue(db);
    await db.exec(migration);
    assert.deepEqual(await catalogue(db),snapshot,'reapplying must not duplicate categories, questions or answers');
    await db.exec(`UPDATE hocalist.catalogue_categories SET status='retired',label='Admin custom title' WHERE slug='home-furniture';
      UPDATE hocalist.catalogue_option_groups SET status='retired' WHERE id=(SELECT id FROM hocalist.catalogue_option_groups LIMIT 1);
      UPDATE hocalist.catalogue_options SET status='retired' WHERE id=(SELECT id FROM hocalist.catalogue_options LIMIT 1);`);
    await db.exec(migration);
    assert.deepEqual((await db.query("SELECT status,label FROM hocalist.catalogue_categories WHERE slug='home-furniture'")).rows,[{status:'retired',label:'Admin custom title'}]);
    for (const table of ['catalogue_option_groups','catalogue_options']) assert.equal(
      (await db.query(`SELECT count(*)::int AS n FROM hocalist.${table} WHERE status='retired'`)).rows[0].n,1);
  } finally { await db.close(); await reference.close(); }
});
