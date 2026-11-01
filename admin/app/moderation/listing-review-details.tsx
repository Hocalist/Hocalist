"use client";
import {useEffect,useState} from 'react';
import type {AdminListing} from '../lib/admin-data';
function ListingPhoto({listingId,mediaId,index}:{listingId:string;mediaId:string;index:number}){
 const [url,setUrl]=useState(''),[error,setError]=useState(''),[retry,setRetry]=useState(0);
 useEffect(()=>{let active=true,objectUrl='';const controller=new AbortController();setUrl('');setError('');
 void (async()=>{try{
  const response=await fetch('/api/admin-store-photo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({submission_id:listingId,media_id:mediaId}),signal:controller.signal,cache:'no-store'});
  if(!response.ok||response.headers.get('content-type')?.split(';')[0]!=='image/jpeg')throw Error('unavailable');
  const blob=await response.blob();if(!active)return;if(blob.size>4*1024*1024)throw Error('size');
  objectUrl=URL.createObjectURL(blob);setUrl(objectUrl);
 }catch{if(active)setError('This photo could not be loaded.');}})();
 return()=>{active=false;controller.abort();if(objectUrl)URL.revokeObjectURL(objectUrl)};
 },[listingId,mediaId,retry]);
 return <figure style={{margin:0}}>{url?<img src={url} alt={`Listing photo ${index+1}`} style={{display:'block',width:'100%',maxHeight:420,objectFit:'contain',borderRadius:12}}/>:error?<p role="alert">{error} <button type="button" onClick={()=>setRetry(n=>n+1)}>Retry photo</button></p>:<p role="status">Loading photo {index+1}…</p>}</figure>;
}
export function ListingReviewDetails({listing}:{listing:AdminListing}){
 const photos=Array.isArray(listing.image_media_ids)?listing.image_media_ids:[];
 return <section aria-label="Listing details"><dl className="record-details">
 <div><dt>Description</dt><dd style={{whiteSpace:'pre-wrap'}}>{listing.description||'Not provided'}</dd></div>
 <div><dt>Pickup or service area</dt><dd>{listing.service_area||'Not provided'}</dd></div>
 <div><dt>Availability</dt><dd>{listing.availability||'Not provided'}</dd></div>
 </dl><h3>Listing photos</h3>{photos.length?<div style={{display:'grid',gap:12}}>{photos.map((id,index)=><ListingPhoto key={id} listingId={listing.id} mediaId={id} index={index}/>)}</div>:<p>No photos provided.</p>}</section>;
}
