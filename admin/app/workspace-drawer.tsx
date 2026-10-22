"use client";
import {useEffect,useRef,type ReactNode} from 'react';
export function WorkspaceDrawer({open,title,onClose,locked=false,children}:{open:boolean;title:string;onClose:()=>void;locked?:boolean;children:ReactNode}){
 const ref=useRef<HTMLDialogElement>(null);
 useEffect(()=>{const dialog=ref.current;if(open&&!dialog?.open)dialog?.showModal();if(!open&&dialog?.open)dialog.close();},[open]);
 return <dialog ref={ref} className="record-drawer" aria-label={title} onCancel={e=>{e.preventDefault();if(!locked)onClose();}}><div className="record-drawer-head"><h2>{title}</h2><button type="button" disabled={locked} aria-label="Close panel" onClick={onClose}>×</button></div><div className="record-drawer-body">{children}</div></dialog>;
}
