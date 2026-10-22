"use client";
import {useEffect,useRef} from 'react';
import {Status} from './components';
export function RecordDetails({columns,cells,statusIndex,onClose}:{columns:readonly string[];cells:string[];statusIndex:number;onClose:()=>void}){
 const ref=useRef<HTMLDialogElement>(null);
 useEffect(()=>{const dialog=ref.current;dialog?.showModal();return()=>dialog?.close();},[]);
 return <dialog className="record-drawer" ref={ref} onCancel={onClose} onClose={onClose}><div className="record-drawer-head"><h2>Record details</h2><button type="button" aria-label="Close details" onClick={onClose}>×</button></div><div className="record-drawer-body"><dl className="record-details">{columns.map((column,i)=><div key={column}><dt>{column}</dt><dd>{i===statusIndex?<Status>{cells[i]}</Status>:cells[i]||'—'}</dd></div>)}</dl></div></dialog>
}
