export type ReportCreditTarget={id:string;title:string;fee_minor:number;status:string;returned:boolean};
export function decodeReportCreditTargets(value:unknown):ReportCreditTarget[]|null {
 if(!Array.isArray(value)||value.length>100)return null;
 const ids=new Set<string>();
 for(const r of value){
  if(!r||typeof r!=='object'||typeof r.id!=='string'||!/^[\da-f-]{36}$/i.test(r.id)||ids.has(r.id)||
    typeof r.title!=='string'||r.title.length>500||typeof r.status!=='string'||typeof r.returned!=='boolean'||
    !Number.isSafeInteger(r.fee_minor)||r.fee_minor<=0)return null;
  ids.add(r.id);
 }
 return value as ReportCreditTarget[];
}
