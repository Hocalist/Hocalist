export type ActivityDay={date:string;requests:number;offers:number};
export type WorkspaceMetrics={generated_at:string;timezone:'UTC';series:ActivityDay[];resources:Record<string,{total:number;statuses:Record<string,number>}>;recent_requests:{id:string;title:string;buyer:string;category:string;status:string;created_at:string;offers:number}[];queues:{listings:number;reports:number;withdrawals:number};periods:{requests_current:number;requests_previous:number;offers_current:number;offers_previous:number}};
const object=(x:unknown):x is Record<string,unknown>=>!!x&&typeof x==='object'&&!Array.isArray(x);
const count=(x:unknown):x is number=>typeof x==='number'&&Number.isSafeInteger(x)&&x>=0;
export function decodeWorkspaceMetrics(x:unknown):WorkspaceMetrics|null{
 if(!object(x)||x.timezone!=='UTC'||typeof x.generated_at!=='string'||!Number.isFinite(Date.parse(x.generated_at))||!Array.isArray(x.series)||x.series.length!==7||!object(x.resources)||!object(x.queues)||!object(x.periods)||!Array.isArray(x.recent_requests)||x.recent_requests.length>6)return null;
 let prior=0;
 for(const day of x.series){if(!object(day)||typeof day.date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(day.date)||!count(day.requests)||!count(day.offers))return null;const time=Date.parse(day.date+'T00:00:00Z');if(!Number.isFinite(time)||new Date(time).toISOString().slice(0,10)!==day.date||(prior&&time-prior!==86400000))return null;prior=time;}
 for(const [key,v] of Object.entries(x.resources)){if(!['users','requests','offers','billing'].includes(key)||!object(v)||!count(v.total)||!object(v.statuses)||Object.values(v.statuses).some(n=>!count(n))||Object.values(v.statuses).reduce<number>((n,v)=>n+(v as number),0)!==v.total)return null;}
 if(['listings','reports','withdrawals'].some(k=>!count((x.queues as Record<string,unknown>)[k]))||['requests_current','requests_previous','offers_current','offers_previous'].some(k=>!count((x.periods as Record<string,unknown>)[k])))return null;
 const ids=new Set();for(const r of x.recent_requests){if(!object(r)||typeof r.id!=='string'||!/^[0-9a-f-]{36}$/i.test(r.id)||ids.has(r.id)||['title','buyer','category','status','created_at'].some(k=>typeof r[k]!=='string'||(r[k] as string).length>2000)||!count(r.offers)||!Number.isFinite(Date.parse(r.created_at as string)))return null;ids.add(r.id);}
 return x as WorkspaceMetrics;
}
export function periodChange(current:number,previous:number):string{return previous===0?current===0?'No new records in either period':'No records in previous period':`${current>=previous?'+':''}${Math.round((current-previous)/previous*100)}% vs previous 7 days`;}
export function chartCoordinates(days:ActivityDay[],field:'requests'|'offers'){
 const max=Math.max(1,...days.flatMap(d=>[d.requests,d.offers]));return days.map((day,i)=>`${40+i*90},${170-day[field]/max*140}`).join(' ');
}
