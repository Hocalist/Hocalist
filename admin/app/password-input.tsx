"use client";
import { useState, type InputHTMLAttributes } from 'react';

export function PasswordInput(props: InputHTMLAttributes<HTMLInputElement>) {
 const [visible,setVisible]=useState(false);
 return <span className="password-control">
  <input {...props} type={visible?'text':'password'}/>
  <button className="password-eye" type="button" aria-label={visible?'Hide password':'Show password'} aria-pressed={visible} disabled={props.disabled} onClick={()=>setVisible(!visible)}>
   <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>{visible&&<path d="m3 3 18 18"/>}</svg>
  </button>
 </span>;
}
