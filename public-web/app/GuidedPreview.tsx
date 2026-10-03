'use client';

import { useEffect, useState } from 'react';

type PreviewKind = 'request' | 'select';

const previews: Record<
  PreviewKind,
  { chip: string; title: string; body: string; steps: string[]; note: string }
> = {
  request: {
    chip: 'Guided preview',
    title: 'How a Hocalist request works',
    body: 'This walkthrough mirrors the app flow. It does not create a live request and is not connected to marketplace accounts.',
    steps: [
      'Describe the item or service, your approximate area, budget, and timing.',
      'Relevant local sellers respond with offers and availability.',
      'Compare price, condition, and meetup context side by side.',
      'You can accept more than one seller while you compare; each gets a separate chat and meeting.',
      'When you decide, choose the seller you purchased from to complete the request PIN.',
      'Inspect in person and arrange item payment directly with the seller.'
    ],
    note: 'Preview only. Item payment is never processed inside Hocalist.'
  },
  select: {
    chip: 'Guided preview',
    title: 'How selecting a seller works',
    body: 'This walkthrough shows the comparison step. It does not select a real seller or open a live chat.',
    steps: [
      'Review every offer for the request, not just the lowest price.',
      'Open seller details to check condition notes and public profile facts.',
      'Accept the sellers you want to continue with; each keeps its own chat and meeting.',
      'When the purchase is done in person, confirm it with the buyer-held request PIN.',
      'Only the chosen purchase seller can complete that PIN, and a request completes once.',
      'Other negotiations close after the confirmed purchase; history stays available.'
    ],
    note: 'Preview only. No seller is selected and no message is sent.'
  }
};

export default function GuidedPreviewButton({
  kind,
  label,
  className
}: {
  kind: PreviewKind;
  label: string;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const preview = previews[kind];

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  return (
    <>
      <button type="button" className={className} onClick={() => setOpen(true)}>
        {label}
      </button>
      {open ? (
        <div
          className="preview-modal-backdrop"
          role="presentation"
          onClick={() => setOpen(false)}
        >
          <div
            className="preview-modal"
            role="dialog"
            aria-modal="true"
            aria-label={preview.title}
            onClick={(event) => event.stopPropagation()}
          >
            <div className="preview-modal-head">
              <div>
                <span className="status-chip">{preview.chip}</span>
                <h2>{preview.title}</h2>
              </div>
              <button
                type="button"
                className="preview-modal-close"
                onClick={() => setOpen(false)}
              >
                Close
              </button>
            </div>
            <p>{preview.body}</p>
            <ol className="preview-steps">
              {preview.steps.map((step) => (
                <li key={step}>{step}</li>
              ))}
            </ol>
            <p className="preview-note">{preview.note}</p>
          </div>
        </div>
      ) : null}
    </>
  );
}
