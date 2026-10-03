'use client';

import { useState } from 'react';

type Status = 'idle' | 'submitting' | 'unavailable' | 'confirmed' | 'error';

export default function WaitlistForm() {
  const [email, setEmail] = useState('');
  const [consent, setConsent] = useState(false);
  const [status, setStatus] = useState<Status>('idle');
  const [message, setMessage] = useState('');

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (status === 'submitting') return;
    if (!consent) {
      setStatus('error');
      setMessage('Please confirm you agree to be contacted about launch updates.');
      return;
    }
    setStatus('submitting');
    setMessage('');
    try {
      const response = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, consent, source: 'download-page' })
      });
      if (response.ok) {
        const data = await response.json().catch(() => null);
        setStatus('confirmed');
        setMessage(
          typeof data?.message === 'string'
            ? data.message
            : 'You are on the launch update list. You can unsubscribe at any time.'
        );
        return;
      }
      const data = await response.json().catch(() => null);
      if (response.status === 503 || data?.error === 'waitlist_not_configured') {
        setStatus('unavailable');
        setMessage(
          'The launch list is not open yet, so nothing was stored. Use the email updates button instead.'
        );
        return;
      }
      if (response.status === 429 || data?.error === 'rate_limited') {
        setStatus('error');
        setMessage('Too many launch-list requests from this connection. Try again later.');
        return;
      }
      setStatus('error');
      setMessage(
        data?.error === 'invalid_email'
          ? 'Enter a valid email address.'
          : 'The request could not be sent. Try again or use the email updates button.'
      );
    } catch {
      setStatus('error');
      setMessage('The request could not reach the server. Try again in a moment.');
    }
  }

  return (
    <form className="waitlist-form" onSubmit={submit} noValidate>
      <label className="request-field wide">
        <span>Email for launch updates</span>
        <input
          type="email"
          name="email"
          autoComplete="email"
          value={email}
          required
          onChange={(event) => setEmail(event.target.value)}
        />
      </label>
      <label className="waitlist-consent">
        <input
          type="checkbox"
          checked={consent}
          onChange={(event) => setConsent(event.target.checked)}
        />
        <span>
          I agree to receive launch updates about Hocalist and understand no
          marketplace request is created by this form.
        </span>
      </label>
      <button className="button primary" type="submit" disabled={status === 'submitting'}>
        {status === 'submitting' ? 'Sending…' : 'Join launch list'}
      </button>
      {message ? (
        <p
          className={`waitlist-status ${status}`}
          role={status === 'confirmed' ? 'status' : 'alert'}
        >
          {message}
        </p>
      ) : null}
    </form>
  );
}
