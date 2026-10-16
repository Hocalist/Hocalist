import {createRoutesHandler} from './handler.ts';
import {createPlacesAuthVerifier} from '../hocalist-places/auth.ts';
import {placesPreflight, withPlacesCors} from '../hocalist-places/cors.ts';
const project = 'https://icqwbzswokoulatomgql.supabase.co';
Deno.serve(async request => {
  if (request.method === 'OPTIONS') return placesPreflight(request);
  if (request.headers.has('Origin') && request.headers.get('Origin') !== 'http://127.0.0.1:7359') {
    return withPlacesCors(request, new Response(null, {status: 403}));
  }
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const key = Deno.env.get('HOCALIST_GOOGLE_ROUTES_SERVER_API_KEY') ?? '';
  if (!service || !key || Deno.env.get('SUPABASE_URL') !== project ||
      Deno.env.get('HOCALIST_ROUTES_ENABLED') !== 'true') {
    return withPlacesCors(request, new Response(JSON.stringify({error:'unconfigured'}), {
      status:404, headers:{'Content-Type':'application/json','Cache-Control':'no-store'},
    }));
  }
  const handler = createRoutesHandler({
    authenticate: createPlacesAuthVerifier(project, service),
    meeting: async (authorization, id) => {
      const response = await fetch(`${project}/rest/v1/rpc/meeting_detail`, {
        method:'POST', headers:{apikey:service, Authorization:authorization,
          'Content-Type':'application/json','Content-Profile':'hocalist'},
        body:JSON.stringify({p_meeting:id}), signal:AbortSignal.timeout(10000), redirect:'error',
      });
      if (!response.ok) { await response.body?.cancel(); return null; }
      return await response.json();
    },
    gate: async userId => {
      const response = await fetch(`${project}/rest/v1/rpc/places_gate`, {
        method:'POST', headers:{apikey:service, Authorization:`Bearer ${service}`,
          'Content-Type':'application/json','Content-Profile':'hocalist'},
        body:JSON.stringify({p_user:userId,p_operation:'autocomplete',p_session_token:crypto.randomUUID(),
          p_input:'meeting-route',p_place_id:null}), signal:AbortSignal.timeout(10000), redirect:'error',
      });
      if (!response.ok) { await response.body?.cancel(); throw Error('gate_failed'); }
      return await response.json();
    },
    compute: async body => {
      const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
        method:'POST', headers:{'Content-Type':'application/json','X-Goog-Api-Key':key,
          'X-Goog-FieldMask':'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.legs.startLocation,routes.legs.endLocation,routes.legs.steps.navigationInstruction'},
        body:JSON.stringify(body), signal:AbortSignal.timeout(15000), redirect:'error',
      });
      if (!response.ok) { await response.body?.cancel(); throw Error('provider_failed'); }
      return await response.json();
    },
  });
  return withPlacesCors(request, await handler(request));
});
