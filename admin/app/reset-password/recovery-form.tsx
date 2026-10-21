"use client";
import Link from 'next/link';
import { PasswordInput } from '../password-input';
import { useEffect,useRef,useState,type FormEvent } from 'react';
import { recoveryFragment } from '../lib/recovery-fragment';
export function PasswordRecoveryForm(){
 const token=useRef(''),initialised=useRef(false),gate=useRef(false);
 const [mode,setMode]=useState<'loading'|'request'|'update'|'done'>('loading');
 const [email,setEmail]=useState(''),[password,setPassword]=useState(''),[confirm,setConfirm]=useState('');
 const [busy,setBusy]=useState(false),[message,setMessage]=useState('');
 useEffect(()=>{
  const receive=()=>{
   if(initialised.current&&!location.hash)return;initialised.current=true;
   const fragment=recoveryFragment(location.hash);
   history.replaceState(null,'',location.pathname);
   token.current=fragment.token;setPassword('');setConfirm('');setMode(fragment.token?'update':'request');
   setMessage(fragment.error?'This link is invalid or has expired. Request a new reset email below.':'');
  };
  receive();window.addEventListener('hashchange',receive);
  return()=>window.removeEventListener('hashchange',receive);
 },[]);
 async function submit(event:FormEvent){
  event.preventDefault();if(gate.current)return;
  if(mode==='update'&&password!==confirm){setMessage('The passwords do not match.');return;}
  gate.current=true;setBusy(true);setMessage('');
  try{
   const response=await fetch('/api/password-recovery',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(mode==='update'?{action:'update',access_token:token.current,password}:{action:'request',email})});
   const result=await response.json();setMessage(result.message||'Please retry.');
   if(response.ok&&result.ok){if(mode==='update'){token.current='';setPassword('');setConfirm('');setMode('done');}}
   else if(response.status===401){token.current='';setPassword('');setConfirm('');setMode('request');}
  }catch{setMessage('The server could not be reached. Please retry.');}
  finally{gate.current=false;setBusy(false);}
 }
 return <main className="login"><section className="login-brand"><img className="auth-logo auth-logo-white" src="/brand/hocalist-wordmark-white.png" alt="Hocalist" width={240} height={80}/><p>Hocalist administration</p><h1>Let’s get you back in.</h1><p>Choose a new password for your Hocalist account. You’ll still use your authenticator app when you sign in.</p></section><section className="login-panel"><img className="auth-logo auth-logo-mobile" src="/brand/hocalist-wordmark.png" alt="Hocalist" width={200} height={66}/><form className="login-card" onSubmit={submit}>
  <div><p className="eyebrow">Account recovery</p><h2>{mode==='update'?'Choose a new password':mode==='done'?'Password updated':'Reset your password'}</h2></div>
  {mode==='request'&&<label>Hocalist account email<input type="email" autoComplete="username" maxLength={254} value={email} onChange={e=>setEmail(e.target.value)} required disabled={busy}/></label>}
  {mode==='update'&&<><label>New password<PasswordInput autoComplete="new-password" minLength={8} maxLength={200} value={password} onChange={e=>setPassword(e.target.value)} required disabled={busy}/></label><label>Confirm new password<PasswordInput autoComplete="new-password" minLength={8} maxLength={200} value={confirm} onChange={e=>setConfirm(e.target.value)} required disabled={busy}/></label></>}
  {(mode==='request'||mode==='update')&&<button className="primary login-button" disabled={busy}>{busy?'Please wait…':mode==='update'?'Save new password':'Send reset email'}</button>}
  {mode==='loading'&&<p role="status">Checking reset link…</p>}
  <p role="status">{message}</p><Link href="/login">Back to sign-in</Link>
 </form></section></main>;
}
