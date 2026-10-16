type RecordValue = Record<string, unknown>;
type Dependencies = {
  authenticate: (authorization: string) => Promise<{userId: string} | {error: string}>;
  meeting: (authorization: string, id: string) => Promise<RecordValue | null>;
  gate: (userId: string) => Promise<RecordValue>;
  compute: (body: RecordValue) => Promise<RecordValue>;
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const object = (value: unknown): value is RecordValue =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'},
});
export function createRoutesHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return json({error: 'method_not_allowed'}, 405);
    const auth = req.headers.get('Authorization') ?? '';
    if (!/^Bearer \S+$/.test(auth)) return json({error: 'unauthorized'}, 401);
    if (!(req.headers.get('Content-Type') ?? '').includes('application/json')) {
      return json({error: 'invalid_input'}, 400);
    }
    try {
      const user = await deps.authenticate(auth);
      if ('error' in user) return json({error: user.error}, user.error === 'unauthorized' ? 401 : 503);
      if (Number(req.headers.get('Content-Length')) > 2048) return json({error: 'invalid_input'}, 413);
      const reader = req.body?.getReader();
      if (!reader) return json({error: 'invalid_input'}, 400);
      const parts: Uint8Array[] = []; let length = 0;
      for (;;) {
        const part = await reader.read(); if (part.done) break;
        length += part.value.length;
        if (length > 2048) { await reader.cancel(); return json({error: 'invalid_input'}, 413); }
        parts.push(part.value);
      }
      const bytes = new Uint8Array(length); let offset = 0;
      for (const part of parts) {bytes.set(part, offset); offset += part.length;}
      let input: unknown;
      try { input = JSON.parse(new TextDecoder().decode(bytes)); }
      catch { return json({error: 'invalid_input'}, 400); }
      if (!object(input) || Object.keys(input).some(k => !['meetingId','origin','mode'].includes(k)) ||
          typeof input.meetingId !== 'string' || !uuid.test(input.meetingId) ||
          typeof input.origin !== 'string' || !input.origin.trim() || input.origin.length > 200 ||
          !['DRIVE','WALK'].includes(String(input.mode))) return json({error: 'invalid_input'}, 400);
      // This uses the caller's JWT, never the service role, for private meeting access.
      const meeting = await deps.meeting(auth, input.meetingId);
      if (!meeting || !['accepted','reschedule_proposed'].includes(String(meeting.status)) ||
          !object(meeting.accepted_schedule)) return json({error: 'meeting_access_denied'}, 403);
      const place = meeting.accepted_schedule;
      const address = typeof place.place_address === 'string' ? place.place_address.trim() : '';
      const placeId = typeof place.place_id === 'string' ? place.place_id.trim() : '';
      const latitude = place.place_latitude;
      const longitude = place.place_longitude;
      const hasPin = latitude != null || longitude != null;
      if (hasPin && (typeof latitude !== 'number' || typeof longitude !== 'number' ||
          !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
          Math.abs(latitude) > 90 || Math.abs(longitude) > 180)) {
        return json({error: 'invalid_response'}, 502);
      }
      if (!hasPin && !address && !placeId) return json({error: 'destination_missing'}, 409);
      // Routes conservatively consume the existing shared Places autocomplete
      // budget (user/global minute/day). No separate unlimited provider path.
      const gate = await deps.gate(user.userId);
      if (gate.decision !== 'allowed' || gate.user_id !== user.userId) {
        return json({error: gate.decision === 'rate_limited' ? 'rate_limited' : 'access_denied'},
          gate.decision === 'rate_limited' ? 429 : 403);
      }
      const result = await deps.compute({
        origin: {address: input.origin.trim()},
        destination: hasPin ? {location: {latLng: {latitude, longitude}}}
          : placeId ? {placeId} : {address},
        travelMode: input.mode,
        languageCode: 'en-US', units: 'IMPERIAL', computeAlternativeRoutes: false,
      });
      if (!Array.isArray(result.routes) || result.routes.length === 0) return json({error: 'no_route'}, 404);
      const route = result.routes[0];
      if (!object(route) || !object(route.polyline) || typeof route.polyline.encodedPolyline !== 'string' ||
          route.polyline.encodedPolyline.length > 200000 || typeof route.distanceMeters !== 'number' ||
          typeof route.duration !== 'string' || !Array.isArray(route.legs) || !object(route.legs[0])) {
        return json({error: 'invalid_response'}, 502);
      }
      const leg = route.legs[0];
      if (!object(leg.startLocation) || !object(leg.endLocation) || !Array.isArray(leg.steps) || leg.steps.length > 1000) {
        return json({error: 'invalid_response'}, 502);
      }
      return json({meetingId: input.meetingId, distanceMeters: route.distanceMeters,
        duration: route.duration, polyline: route.polyline.encodedPolyline,
        start: leg.startLocation.latLng, end: leg.endLocation.latLng,
        steps: leg.steps.map(step => object(step) && object(step.navigationInstruction) &&
          typeof step.navigationInstruction.instructions === 'string'
            ? step.navigationInstruction.instructions.slice(0, 1000) : '').filter(Boolean),
      });
    } catch { return json({error: 'unavailable'}, 503); }
  };
}
