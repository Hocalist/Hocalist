export type StoreListing = {id:string; kind:'product'|'service'; title:string; description:string; price_label:string; service_area:string; category_label:string};
export type PublicStore = {available:false}|{available:true;name:string;area:string|null;items:StoreListing[]};
export function validStoreId(value:string):boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
export function decodePublicStore(value:unknown):PublicStore {
  if (!value || typeof value!=='object') throw new Error('store_response_invalid');
  const row=value as Record<string,unknown>;
  if(row.available===false) return {available:false};
  if(row.available!==true || typeof row.name!=='string' || !Array.isArray(row.items) || row.items.length>50 || (row.area!==null && typeof row.area!=='string')) throw new Error('store_response_invalid');
  const items=row.items.map((item:unknown):StoreListing=> {
    if(!item || typeof item!=='object') throw new Error('store_response_invalid');
    const l=item as Record<string,unknown>;
    if(typeof l.id!=='string' || !validStoreId(l.id) || !['product','service'].includes(String(l.kind)) || ['title','description','price_label','service_area','category_label'].some(k=>typeof l[k]!=='string')) throw new Error('store_response_invalid');
    return {id:l.id,kind:l.kind as StoreListing['kind'],title:l.title as string,description:l.description as string,price_label:l.price_label as string,service_area:l.service_area as string,category_label:l.category_label as string};
  });
  return {available:true,name:row.name,area:row.area as string|null,items};
}

export async function loadPublicStore(id:string,config:{url:string;anonKey:string}|null,request:typeof fetch=fetch):Promise<PublicStore|null> {
  if(!validStoreId(id)) return {available:false};
  if(!config) return null;
  try {
    const init: RequestInit & {cache:'no-store'} = {method:'POST',cache:'no-store',headers:{apikey:config.anonKey,'Content-Type':'application/json','Content-Profile':'hocalist'},body:JSON.stringify({p_seller:id}),signal:AbortSignal.timeout(10000)};
    const response=await request(`${config.url}/rest/v1/rpc/public_store`, init);
    if(!response.ok) return null;
    return decodePublicStore(await response.json());
  } catch { return null; }
}
