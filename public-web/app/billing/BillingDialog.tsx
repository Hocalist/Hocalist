'use client';
import {useEffect,useRef,type ReactNode} from 'react';
export default function BillingDialog({open,onClose,busy,title,eyebrow,children}:{open:boolean;onClose:()=>void;busy:boolean;title:string;eyebrow:string;children:ReactNode}){
 const dialog=useRef<HTMLDialogElement>(null);
 useEffect(()=>{const node=dialog.current;if(!node)return;if(open&&!node.open)node.showModal();if(!open&&node.open)node.close();if(!open)return;const previous=document.body.style.overflow;document.body.style.overflow='hidden';return()=>{document.body.style.overflow=previous;};},[open]);
 return <dialog ref={dialog} className="billing-dialog" aria-label={title} onCancel={event=>{if(busy)event.preventDefault();else onClose();}} onClose={onClose}>
  <div className="billing-dialog-heading"><div><p className="plan-kicker">{eyebrow}</p><h2>{title}</h2></div><button className="button secondary small" type="button" disabled={busy} onClick={onClose}>Close</button></div>
  {children}
 </dialog>;
}
