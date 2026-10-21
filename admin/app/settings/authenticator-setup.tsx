"use client";
import { useState, type FormEvent } from 'react';
export function AuthenticatorSetup({ onComplete, signedIn = false }: { onComplete?: () => void; signedIn?: boolean } = {}) {
 const [email,setEmail]=useState(''); const [password,setPassword]=useState('');
 const [qr,setQr]=useState(''); const [factor,setFactor]=useState(''); const [code,setCode]=useState('');
 const [busy,setBusy]=useState(false); const [message,setMessage]=useState(''); const [complete,setComplete]=useState(false);
 async function submit(event: FormEvent) {
  event.preventDefault(); if(busy) return; setBusy(true); setMessage('');
  try {
   const response=await fetch('/api/mfa/enroll',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(qr ? {action:'verify',factor_id:factor,code} : {action:'start',email,password})});
   const body=await response.json(); setPassword(''); setCode('');
   if(!response.ok || !body.ok) { setMessage(body.message || 'Setup could not be completed. Please retry.'); return; }
   if(qr) { setQr(''); setFactor(''); setComplete(true); setMessage('Authenticator verified. Keep access to your authenticator for future sign-ins.'); onComplete?.(); }
   else { setQr(body.qr_code.startsWith('data:image/svg+xml;') ? body.qr_code : 'data:image/svg+xml;charset=utf-8,'+encodeURIComponent(body.qr_code)); setFactor(body.factor_id); }
  } catch { setMessage('The server could not be reached. Please retry.'); }
  finally { setBusy(false); }
 }
 return <section className="panel authenticator-setup">
  <h2>Protect administrator sign-in</h2><p>Add an authenticator as a second sign-in step. It is free. Keep the QR code and verification codes private.</p>
  {!complete && <form onSubmit={submit} style={{display:'grid',gap:12}}>
   {qr ? <><img src={qr} alt="Scan this private QR code with your authenticator" width={220} height={220} style={{maxWidth:'100%',background:'white'}}/><label>Authenticator code<input aria-label="Authenticator code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,''))} required disabled={busy}/></label></>
   : signedIn ? <p>Your sign-in is verified. Set up your authenticator, then enter its six-digit code.</p> : <><label>Administrator email<input aria-label="Administrator email" type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} required disabled={busy}/></label><label>Confirm your password<input aria-label="Confirm your password" type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required disabled={busy}/></label></>}
   <button className="primary" type="submit" disabled={busy}>{busy ? 'Please wait…' : qr ? 'Verify authenticator' : 'Set up authenticator'}</button>
   {qr && <button className="secondary" type="button" disabled={busy} onClick={()=>{setQr('');setFactor('');setCode('');setMessage('Setup closed. The authenticator is not enabled until you verify a code.');}}>Close setup</button>}
  </form>}
  <p role="status">{message}</p>
 </section>;
}
