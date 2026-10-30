import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const root = dirname(fileURLToPath(import.meta.url));
export function protectBrandColours(html) {
  const whiteText = text => `<span class="gmail-blend-screen"><span class="gmail-blend-difference">${text}</span></span>`;
  return html
    .replace('</head>', `<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark"><style>
u + .hocalist-email .gmail-blend-screen { background:#000; mix-blend-mode:screen; }
u + .hocalist-email .gmail-blend-difference { background:#000; mix-blend-mode:difference; }
.gmail-blend-screen,.gmail-blend-difference { display:block; }
@media (prefers-color-scheme:dark) { .email-card { background:#161d2d !important; color:#edf1fa !important; } .email-card h1,.email-card a:not(.brand-button) { color:#c5ceff !important; } .email-card p,.email-footer { color:#d0d7e5 !important; } .brand-header p { color:#fff !important; } }
</style></head>`)
    .replace('<body style=', '<body class="hocalist-email" style=')
    .replace('style="max-width:560px', 'class="email-card" style="max-width:560px')
    .replace('style="padding:20px 28px;border-top:', 'class="email-footer" style="padding:20px 28px;border-top:')
    .replace('bgcolor="#00036c" style="padding:', 'class="brand-header" bgcolor="#00036c" style="padding:')
    .replace('background:#00036c;color:', 'background:#00036c;background-image:linear-gradient(#00036c,#00036c);color:')
    .replace('style="border-radius:8px"', 'style="border-radius:8px;background:#00036c;background-image:linear-gradient(#00036c,#00036c)"')
    .replace('>YOUR LOCAL CONNECTION</p>', `>${whiteText('YOUR LOCAL CONNECTION')}</p>`)
    .replace(/<a href="([^"]+)" style="display:inline-block;([^\"]+)">([^<]+)<\/a>/, (_all, href, style, text) => `<a class="brand-button" href="${href}" style="display:inline-block;${style}">${whiteText(text)}</a>`);
}
export const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
// System-owned Supabase expressions are deliberately kept verbatim. Never insert user HTML.
export function shell({ title, body, action, href, code, preview = title }) {
  if (action && href !== '{{ .ConfirmationURL }}') {
    const url = new URL(href);
    if (url.protocol !== 'https:' || url.hostname !== 'www.hocalist.com' || url.username || url.password) {
      throw new Error('Email actions require an approved Hocalist HTTPS destination');
    }
    href = escapeHtml(href);
  }
  if (code && code !== '{{ .Token }}') code = escapeHtml(code);
  return protectBrandColours(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(title)}</title></head>
<body style="margin:0;background:#f3f6fb;color:#17213b;font-family:Arial,Helvetica,sans-serif">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all">${escapeHtml(preview)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f3f6fb"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border:1px solid #dde3ee;border-radius:16px;overflow:hidden">
<tr><td bgcolor="#00036c" style="padding:28px 28px 24px;background:#00036c;color:#ffffff"><img src="https://www.hocalist.com/brand/hocalist-wordmark-white.png" width="154" alt="Hocalist" style="display:block;border:0;width:154px;max-width:100%;height:auto;color:#ffffff;font-size:24px"><p style="margin:16px 0 0;color:#ffffff;font-size:12px;letter-spacing:1px">YOUR LOCAL CONNECTION</p></td></tr>
<tr><td style="padding:28px"><h1 style="margin:0 0 16px;color:#00036c;font-size:26px;line-height:1.25">${escapeHtml(title)}</h1>
<p style="margin:0 0 24px;font-size:16px;line-height:1.65">${escapeHtml(body)}</p>
${code ? `<p style="margin:0 0 24px;font-size:30px;font-weight:bold;letter-spacing:6px;color:#00036c">${code}</p>` : ''}
${action ? `<table role="presentation" cellspacing="0" cellpadding="0"><tr><td bgcolor="#00036c" style="border-radius:8px"><a href="${href}" style="display:inline-block;padding:15px 24px;color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold">${escapeHtml(action)}</a></td></tr></table>` : ''}
<p style="margin:24px 0 0;font-size:14px;line-height:1.6;color:#566176">${action || code ? 'Only continue if you requested this action. Never share your sign-in link, password or verification code.' : 'If you did not make this change, open Hocalist directly and contact support.'}</p>
</td></tr><tr><td style="padding:20px 28px;border-top:1px solid #e4e8f0;font-size:12px;line-height:1.8;color:#566176">Hocalist · Reverse Marketplace<br><a href="https://www.hocalist.com/support" style="color:#00036c">Help &amp; support</a> · <a href="https://www.hocalist.com/privacy" style="color:#00036c">Privacy</a><br>We never ask you to email your password or verification code.</td></tr></table>
</td></tr></table></body></html>`);
}
const auth = [
 ['confirmation','Confirm your Hocalist email','Confirm your email address to finish creating your Hocalist account.','Confirm email'],
 ['invite','You’re invited to Hocalist','You have been invited to join Hocalist. Continue to set up your account.','Accept invitation'],
 ['magic_link','Your Hocalist sign-in link','Use this one-time link to sign in to Hocalist. If you did not request it, you can ignore this email.','Sign in to Hocalist'],
 ['recovery','Reset your Hocalist password','You requested a password reset. Continue to choose a new password. If you did not request this, ignore this email.','Reset password'],
 ['email_change','Confirm your email change','Confirm this email address for your Hocalist account. If you did not request this change, contact support.','Confirm email change'],
 ['reauthentication','Your Hocalist verification code','Enter this code in Hocalist to confirm your identity.',null],
];
const security = [
 ['password_changed','Your password was changed'], ['email_changed','Your email address was changed'],
 ['phone_changed','Your phone number was changed'], ['identity_linked','A sign-in method was linked'],
 ['identity_unlinked','A sign-in method was removed'], ['mfa_factor_enrolled','A verification method was added'],
 ['mfa_factor_unenrolled','A verification method was removed'],
];
mkdirSync(join(root,'supabase'),{recursive:true});
const manifest = [];
for (const [id,title,body,action] of auth) {
 const content=shell({title,body,action,href:'{{ .ConfirmationURL }}',code:id==='reauthentication'?'{{ .Token }}':null});
 writeFileSync(join(root,'supabase',`${id}.html`),content);
 manifest.push({id,subject:title,file:`supabase/${id}.html`,category:'authentication'});
}
for (const [id,event] of security) {
 const title=`${event} on Hocalist`;
 writeFileSync(join(root,'supabase',`${id}_notification.html`),shell({title,body:`${event} for your Hocalist account. If this was you, no action is needed.`}));
 manifest.push({id:`${id}_notification`,subject:title,file:`supabase/${id}_notification.html`,category:'security'});
}
writeFileSync(join(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
writeFileSync(join(root,'preview.html'),shell({title:'Confirm your email',body:'You’re one step away. Confirm your email address to finish creating your Hocalist account.',action:'Confirm email',href:'https://www.hocalist.com/support'}).replace('https://www.hocalist.com/brand/hocalist-wordmark-white.png','../public-web/public/brand/hocalist-wordmark-white.png'));
console.log(`Generated ${manifest.length} templates and a token-free preview.`);
