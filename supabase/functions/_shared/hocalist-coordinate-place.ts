// Server-only, bounded pin lookup. Never log URLs (they contain credentials).
import { PlacesFailure, structuredAddress } from './hocalist-places.ts';
import type { PlacesFetch, PlacesResult } from './hocalist-places.ts';

type LocationConfig = {
  apiKey: string; fetcher?: PlacesFetch; timeoutMs?: number; now?: () => number;
};
export function createCoordinatePlaceProvider(config: LocationConfig) {
  const resolve = createLocationPlaceProvider(config);
  return (latitude: number, longitude: number) => resolve({latitude,longitude});
}
export function createAddressPlaceProvider(config: LocationConfig) {
  const resolve = createLocationPlaceProvider(config);
  return (address: string) => resolve({address});
}
function createLocationPlaceProvider(config: LocationConfig) {
  const fetcher = config.fetcher ?? fetch;
  const timeoutMs = config.timeoutMs ?? 7000;
  if (!config.apiKey.trim() || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 10000) {
    throw new PlacesFailure('maps_unconfigured');
  }
  return async (query: {latitude:number;longitude:number}|{address:string}): Promise<PlacesResult> => {
    if ('address' in query) {
      if (typeof query.address !== 'string' || !query.address.trim() || query.address.length > 1000) throw new PlacesFailure('invalid_input');
    } else if (!Number.isFinite(query.latitude) || Math.abs(query.latitude) > 90 ||
        !Number.isFinite(query.longitude) || Math.abs(query.longitude) > 180) throw new PlacesFailure('invalid_input');
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), timeoutMs);
    const get = async (path: string, params: Record<string,string>) => {
      const url = new URL(`https://maps.googleapis.com/maps/api/${path}/json`);
      url.search = new URLSearchParams({...params, key: config.apiKey}).toString();
      const response = await fetcher(url.href, {method:'GET',redirect:'error',signal:abort.signal});
      if (!response.ok) {
        await response.body?.cancel();
        throw new PlacesFailure(response.status === 429 ? 'maps_rate_limited' : 'maps_unavailable');
      }
      if (!response.headers.get('content-type')?.includes('application/json')) {
        await response.body?.cancel(); throw new PlacesFailure('maps_invalid_response');
      }
      const reader = response.body?.getReader();
      if (!reader) throw new PlacesFailure('maps_invalid_response');
      const chunks: Uint8Array[] = []; let size = 0;
      try {
        while (true) {
          const part = await reader.read(); if (part.done) break;
          size += part.value.length;
          if (size > 65536) { await reader.cancel(); throw new PlacesFailure('maps_invalid_response'); }
          chunks.push(part.value);
        }
      } finally { reader.releaseLock(); }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const part of chunks) { bytes.set(part,offset); offset += part.length; }
      const data = JSON.parse(new TextDecoder().decode(bytes));
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new PlacesFailure('maps_invalid_response');
      if (data.status === 'OVER_QUERY_LIMIT' || data.status === 'OVER_DAILY_LIMIT') throw new PlacesFailure('maps_rate_limited');
      if (data.status !== 'OK') throw new PlacesFailure('maps_unavailable');
      return data;
    };
    try {
      // Sequential calls avoid billing a timezone request if no address exists.
      const geo = await get('geocode','address' in query ? {address:query.address.trim()} : {latlng:`${query.latitude},${query.longitude}`});
      if (!Array.isArray(geo.results) || geo.results.length < 1 || geo.results.length > 50) throw new PlacesFailure('maps_invalid_response');
      const place = geo.results[0];
      // Forward lookup must be unambiguous and complete. Do not silently turn
      // an unknown house/street into a city-centre meeting pin.
      if ('address' in query && (geo.results.length !== 1 || place?.partial_match === true ||
          !Array.isArray(place?.types) || !place.types.some((type:string)=>['street_address','premise','subpremise','establishment','point_of_interest'].includes(type)))) {
        throw new PlacesFailure('maps_unavailable');
      }
      const latitude = 'address' in query ? place?.geometry?.location?.lat : query.latitude;
      const longitude = 'address' in query ? place?.geometry?.location?.lng : query.longitude;
      if (typeof latitude !== 'number' || !Number.isFinite(latitude) || Math.abs(latitude)>90 ||
          typeof longitude !== 'number' || !Number.isFinite(longitude) || Math.abs(longitude)>180) throw new PlacesFailure('maps_invalid_response');
      const address = place?.formatted_address;
      const id = place?.place_id;
      if (typeof address !== 'string' || !address.trim() || address.length > 1000 ||
          typeof id !== 'string' || id.length > 256 || !/^[A-Za-z0-9_-]+$/.test(id)) throw new PlacesFailure('maps_invalid_response');
      const zone = await get('timezone',{location:`${latitude},${longitude}`,timestamp:String(Math.floor((config.now ?? Date.now)()/1000))});
      if (typeof zone.timeZoneId !== 'string' || zone.timeZoneId.length > 100) throw new PlacesFailure('maps_invalid_response');
      // Validate an IANA identifier, not a guessed offset; DST is handled later.
      try { new Intl.DateTimeFormat('en',{timeZone:zone.timeZoneId}).format(); }
      catch { throw new PlacesFailure('maps_invalid_response'); }
      const components = place.address_components;
      if (components != null && !Array.isArray(components)) throw new PlacesFailure('maps_invalid_response');
      const postalAddress = structuredAddress(components?.map((c: Record<string,unknown>) => ({
        types:c.types, longText:c.long_name, shortText:c.short_name,
      })));
      return {placeId:id,address,postalAddress,latitude,longitude,timezoneId:zone.timeZoneId,
        attributions:[{provider:'Google Maps',uri:'https://maps.google.com/'}]};
    } catch (error) {
      if (error instanceof PlacesFailure) throw error;
      throw new PlacesFailure(error instanceof SyntaxError ? 'maps_invalid_response' : 'maps_unavailable');
    } finally { clearTimeout(timer); }
  };
}
