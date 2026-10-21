"use client";
import { useState, type FormEvent } from 'react';
import { PasswordInput } from '../password-input';
export function AuthenticatorSetup({ onComplete, onRestart, signedIn = false }: { onComplete?: () => void; onRestart?: () => void; signedIn?: boolean } = {}) {
 const [email,setEmail]=useState(''); const [password,setPassword]=useState('');
 const [qr,setQr]=useState(''); const [factor,setFactor]=useState(''); const [code,setCode]=useState('');
 const [expired,setExpired]=useState(false);
 const [busy,setBusy]=useState(false); const [message,setMessage]=useState(''); const [complete,setComplete]=useState(false);
 async function submit(event: FormEvent) {
  event.preventDefault(); if(busy) return; setBusy(true); setMessage('');
  try {
   const response=await fetch('/api/mfa/enroll',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(qr ? {action:'verify',factor_id:factor,code} : {action:'start',email,password})});
   const body=await response.json(); setPassword(''); setCode('');
   if(!response.ok || !body.ok) { if(response.status===401){setQr('');setFactor('');setExpired(true);} setMessage(body.message || 'Setup could not be completed. Please retry.'); return; }
   if(qr) { setQr(''); setFactor(''); setComplete(true); setMessage('Authenticator verified. Keep access to your authenticator for future sign-ins.'); onComplete?.(); }
   else { setQr(body.qr_code.startsWith('data:image/svg+xml;') ? body.qr_code : 'data:image/svg+xml;charset=utf-8,'+encodeURIComponent(body.qr_code)); setFactor(body.factor_id); }
  } catch { setMessage('The server could not be reached. Please retry.'); }
  finally { setBusy(false); }
 }
 return <section className="login-card authenticator-setup">
  <div><p className="eyebrow">Account security</p><h2>Secure your account</h2><p>Use an authenticator app to protect your Hocalist account.</p></div>
  {!complete && <form onSubmit={submit} style={{display:'grid',gap:12}}>
   {qr ? <><p>Scan this QR code with an app such as Google Authenticator, then enter the code it shows.</p><img src={qr} alt="Scan this private QR code with your authenticator" width={220} height={220} style={{maxWidth:'100%',background:'white'}}/><label>Six-digit code<input aria-label="Six-digit authenticator code" aria-describedby="setup-code-help" placeholder="000000" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,''))} required disabled={busy}/></label><small id="setup-code-help">Enter six numbers from your authenticator app. This is not your password or the setup key.</small></>
   : signedIn ? <p>You’re signed in. Next, connect your authenticator app.</p> : <><label>Email address<input aria-label="Administrator email" type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} required disabled={busy}/></label><label>Confirm your password<PasswordInput aria-label="Confirm your password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required disabled={busy}/></label></>}
   <button className="primary" type="submit" disabled={busy||expired}>{busy ? 'Please wait…' : qr ? 'Verify authenticator' : 'Set up authenticator'}</button>
   {qr && !onRestart && <button className="text-action" type="button" disabled={busy} onClick={()=>{setQr('');setFactor('');setCode('');setMessage('Setup is not finished. You can continue when you’re ready.');}}>Set up later</button>}
  </form>}
  {message && <p role="status">{message}</p>}
  {signedIn && onRestart && <button className="text-action" type="button" disabled={busy} onClick={onRestart}>Back to sign-in</button>}
 </section>;
}
