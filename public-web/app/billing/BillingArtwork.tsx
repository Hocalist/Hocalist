import type {CSSProperties} from 'react';
export default function BillingArtwork({plan='pro',crop,size=36}:{plan?:string;crop:[number,number,number,number];size?:number}){
 const [x,y,w,h]=crop,scale=size/w;
 return <span className="billing-artwork" aria-hidden="true" style={{width:size,height:h*scale} as CSSProperties}>
  {/* Display the supplied artwork directly, without substitute icons. */}
  {/* eslint-disable-next-line @next/next/no-img-element */}
  <img src={`/billing/${plan}-reference.jpg`} alt="" style={{width:(plan==='free'?852:850)*scale,left:-x*scale,top:-y*scale}}/>
 </span>;
}
