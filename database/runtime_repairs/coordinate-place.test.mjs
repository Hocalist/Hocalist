import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createDisposableDb,applySignupSeed,applyAccountDrafts,seedSyntheticIdentities,asRole,SYNTHETIC} from '../tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('coordinate lookup gate is private, membership-bound and rate-limited',async()=>{
  const db=await createDisposableDb();
  try {
    await applySignupSeed(db); await applyAccountDrafts(db); await seedSyntheticIdentities(db);
    await db.exec(await read('../maps/050_places_gateway.sql'));
    await db.exec(await read('./244_coordinate_place_gate.sql'));
    await asRole(db,'authenticated',SYNTHETIC.a,async()=>{
      await assert.rejects(db.query('SELECT hocalist.places_coordinates_gate($1)',[SYNTHETIC.a]),/permission denied/);
    });
    const gate=async(user)=>(await db.query('SELECT hocalist.places_coordinates_gate($1) AS d',[user])).rows[0].d;
    assert.equal((await gate(SYNTHETIC.outsider)).decision,'membership_required');
    for(let i=0;i<10;i++) assert.equal((await gate(SYNTHETIC.a)).decision,'allowed');
    assert.equal((await gate(SYNTHETIC.a)).decision,'rate_limited');
    for(let i=0;i<5;i++) assert.equal((await gate(SYNTHETIC.b)).decision,'allowed');
    assert.equal((await gate(SYNTHETIC.b)).decision,'rate_limited');
    await db.exec("UPDATE hocalist.memberships SET status='restricted' WHERE role='seller' AND status='active'");
    assert.equal((await gate(SYNTHETIC.b)).decision,'membership_required');
    assert.equal((await db.query("SELECT count(*) AS n FROM hocalist.places_rate_counters WHERE operation='coordinates'")).rows[0].n>0,true);
  } finally {await db.close();}
});
