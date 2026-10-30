import assert from 'node:assert/strict';
import { createCoordinatePlaceProvider, createAddressPlaceProvider } from './hocalist-coordinate-place.ts';
import { parsePlacesQuery, PlacesFailure } from './hocalist-places.ts';
const sessionToken = 'b01c240d-a7af-4eab-984c-123456789012';
const geo = {status:'OK',results:[{place_id:'synthetic-place',formatted_address:'Synthetic Street',
  address_components:[{types:['administrative_area_level_1'],long_name:'New York',short_name:'NY'}]}]};
const json = (body: unknown) => new Response(JSON.stringify(body),{headers:{'content-type':'application/json'}});
Deno.test('coordinate input is strict and rejects external URLs and invalid numbers',()=>{
  for(const value of [NaN,Infinity,91,'40']) assert.throws(()=>parsePlacesQuery({operation:'coordinates',latitude:value,longitude:0,sessionToken}));
  assert.throws(()=>parsePlacesQuery({operation:'coordinates',latitude:0,longitude:181,sessionToken}));
  assert.throws(()=>parsePlacesQuery({operation:'coordinates',latitude:0,longitude:0,url:'https://example.com',sessionToken}));
  assert.equal(parsePlacesQuery({operation:'coordinates',latitude:0,longitude:0,sessionToken}).operation,'coordinates');
});
Deno.test('pin address and IANA timezone are resolved from exactly the selected coordinates',async()=>{
  const urls: URL[] = [];
  const provider = createCoordinatePlaceProvider({apiKey:'server-only-test',now:()=>100000,
    fetcher:async(url,init)=>{
      urls.push(new URL(url)); assert.equal(init.redirect,'error');
      return json(url.includes('/geocode/') ? geo : {status:'OK',timeZoneId:'America/New_York'});
    }});
  const result = await provider(40,-74);
  assert.ok('address' in result);
  assert.equal(result.address,'Synthetic Street'); assert.equal(result.latitude,40); assert.equal(result.longitude,-74);
  assert.equal(result.postalAddress?.state,'NY'); assert.equal(result.timezoneId,'America/New_York');
  assert.equal(urls.length,2); assert.equal(urls[0].searchParams.get('latlng'),'40,-74');
  assert.equal(urls[1].searchParams.get('location'),'40,-74'); assert.equal(urls[1].searchParams.get('timestamp'),'100');
});
Deno.test('failed geocoding never bills a timezone call or exposes provider errors',async()=>{
  let calls = 0;
  const provider = createCoordinatePlaceProvider({apiKey:'secret',fetcher:async()=>{calls++;return json({status:'ZERO_RESULTS',error_message:'private'});}});
  await assert.rejects(provider(0,0),(error:unknown)=>error instanceof PlacesFailure && error.message==='maps_unavailable');
  assert.equal(calls,1);
});
Deno.test('invalid timezone, oversized response and quota failures fail closed',async()=>{
  for(const body of [{status:'OK',timeZoneId:'not/a/zone'},{status:'OVER_QUERY_LIMIT'}]) {
    const provider=createCoordinatePlaceProvider({apiKey:'secret',fetcher:async(url)=>json(url.includes('/geocode/')?geo:body)});
    await assert.rejects(provider(40,-74),PlacesFailure);
  }
  const provider=createCoordinatePlaceProvider({apiKey:'secret',fetcher:async()=>new Response('x'.repeat(65537),{headers:{'content-type':'application/json'}})});
  await assert.rejects(provider(40,-74),PlacesFailure);
});
Deno.test('provider exceptions and aborts are sanitized',async()=>{
  const provider=createCoordinatePlaceProvider({apiKey:'secret',fetcher:()=>Promise.reject(new Error('secret url'))});
  await assert.rejects(provider(40,-74),(error:unknown)=>error instanceof PlacesFailure && error.message==='maps_unavailable');
});

Deno.test('completed address resolves only one full street match with its own timezone',async()=>{
  let calls=0;
  const result=await createAddressPlaceProvider({apiKey:'secret',fetcher:async(url)=>{
    calls++;
    if (url.includes('/geocode/')) {
      assert.equal(new URL(url).searchParams.get('address'),'1 Synthetic Street, NY, US');
      return json({...geo,results:[{...geo.results[0],types:['street_address'],geometry:{location:{lat:40,lng:-74}}}]});
    }
    assert.equal(new URL(url).searchParams.get('location'),'40,-74');
    return json({status:'OK',timeZoneId:'America/New_York'});
  }})('1 Synthetic Street, NY, US');
  assert.ok('address' in result); assert.equal(result.timezoneId,'America/New_York'); assert.equal(calls,2);
});
Deno.test('ambiguous, partial and city-only address matches never supply a meeting pin',async()=>{
  for(const results of [[{...geo.results[0],types:['locality']}],
    [{...geo.results[0],types:['street_address'],partial_match:true}],
    [geo.results[0],geo.results[0]]]) {
    let calls=0;
    const provider=createAddressPlaceProvider({apiKey:'secret',fetcher:async()=>{calls++;return json({status:'OK',results});}});
    await assert.rejects(provider('Synthetic'),PlacesFailure); assert.equal(calls,1);
  }
});
