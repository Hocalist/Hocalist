import {createRoutesHandler} from './handler.ts';
const id = '10000000-0000-4000-8000-000000000001';
function assert(value: unknown) {if (!value) throw Error('assertion_failed');}
function fixture() {
  const calls: string[] = [];
  let payload: unknown;
  const deps = {
    authenticate: async (_auth: string) => {calls.push('auth'); return {userId:id};},
    meeting: async (_auth: string, _id: string): Promise<Record<string, unknown>|null> => {calls.push('meeting'); return {
      status:'accepted',accepted_schedule:{place_id:'confirmed-provider-place',place_address:'public TEST address'},
    };},
    gate: async (_user: string) => {calls.push('gate'); return {decision:'allowed',user_id:id};},
    compute: async (body: Record<string,unknown>) => {calls.push('compute'); payload = body; return {routes:[{
      distanceMeters:1000,duration:'120s',polyline:{encodedPolyline:'_p~iF~ps|U_ulLnnqC'},
      legs:[{startLocation:{latLng:{latitude:38.5,longitude:-120.2}},endLocation:{latLng:{latitude:40.7,longitude:-120.95}},
        steps:[{navigationInstruction:{instructions:'Head north'}}]}],
    }]};},
  };
  return {deps,calls,payload:()=>payload};
}
const request = (extra = {}) => new Request('https://endpoint.test', {method:'POST',
  headers:{Authorization:'Bearer synthetic','Content-Type':'application/json'},
  body:JSON.stringify({meetingId:id,origin:'Public TEST origin',mode:'WALK',...extra})});
Deno.test('confirmed moved pin overrides the original provider place for directions', async () => {
  const f = fixture();
  f.deps.meeting = async () => ({status:'accepted',accepted_schedule:{
    place_id:'original-place',place_address:'original address',place_latitude:41.8765,place_longitude:-87.629}});
  assert((await createRoutesHandler(f.deps)(request())).status === 200);
  const body = f.payload() as Record<string, unknown>;
  assert(JSON.stringify(body.destination) === JSON.stringify({location:{latLng:{latitude:41.8765,longitude:-87.629}}}));
});
Deno.test('malformed stored pins fail closed instead of silently routing elsewhere', async () => {
  for (const pin of [{place_latitude:91,place_longitude:0},{place_latitude:41.8},
    {place_latitude:'41.8',place_longitude:-87.6}]) {
    const f = fixture(); f.deps.meeting = async () => ({status:'accepted',accepted_schedule:{place_id:'original',...pin}});
    assert((await createRoutesHandler(f.deps)(request())).status === 502);
    assert(!f.calls.includes('compute'));
  }
});
Deno.test('routes are authorized and bounded before provider; destination comes only from meeting', async () => {
  const f = fixture(); const response = await createRoutesHandler(f.deps)(request());
  assert(response.status === 200);
  assert(f.calls.join(',') === 'auth,meeting,gate,compute');
  assert(JSON.stringify(f.payload()).includes('confirmed-provider-place'));
  const body = await response.json(); assert(body.steps[0] === 'Head north' && body.meetingId === id);
});
Deno.test('outsider and cancelled meeting never reach rate/provider', async () => {
  for (const meeting of [null,{status:'cancelled',accepted_schedule:{place_id:'x'}}]) {
    const f = fixture(); f.deps.meeting = async () => meeting;
    assert((await createRoutesHandler(f.deps)(request())).status === 403);
    assert(!f.calls.includes('compute') && !f.calls.includes('gate'));
  }
});
Deno.test('rate exhaustion and mismatched gate identity refuse provider', async () => {
  for (const gate of [{decision:'rate_limited',user_id:id},{decision:'allowed',user_id:'other'}]) {
    const f = fixture(); f.deps.gate = async () => gate;
    const response = await createRoutesHandler(f.deps)(request());
    assert([403,429].includes(response.status)); assert(!f.calls.includes('compute'));
  }
});
Deno.test('client cannot supply destination or invalid travel mode', async () => {
  for (const extra of [{destination:'forged'},{mode:'TRANSIT'},{origin:'x'.repeat(201)}]) {
    const f = fixture(); assert((await createRoutesHandler(f.deps)(request(extra))).status === 400);
    assert(!f.calls.includes('meeting') && !f.calls.includes('compute'));
  }
});
Deno.test('malformed and oversized bodies never call provider', async () => {
  const f = fixture();
  const response = await createRoutesHandler(f.deps)(new Request('https://endpoint.test',{method:'POST',
    headers:{Authorization:'Bearer synthetic','Content-Type':'application/json'},body:'x'.repeat(3000)}));
  assert(response.status === 413); assert(!f.calls.includes('compute'));
});
