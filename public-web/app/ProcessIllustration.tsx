const scenes = [
  { label: 'ILLUSTRATIVE REQUEST', title: 'An unlocked iPhone.', lines: ['iPhone 14 Pro · Good condition', 'East Austin · $360–$430'], icon: 'request' },
  { label: 'ILLUSTRATIVE OFFERS', title: 'A few possibilities.', lines: ['Offer A · $395 · Tonight', 'Offer B · $420 · Includes case'], icon: 'offers' },
  { label: 'YOUR CHOICE', title: 'Explore your options.', lines: ['Select sellers to open chat', 'One final purchase seller'], icon: 'choice' },
  { label: 'ILLUSTRATIVE CONVERSATION', title: 'Could we meet Saturday?', lines: ['Confirm condition and timing', 'Agree on a suitable public place'], icon: 'chat' },
  { label: 'OFFLINE HANDOFF', title: 'From an ask to a find.', lines: ['Meet · Inspect · Agree', 'Pay the seller directly offline'], icon: 'handoff' }
];
export function ProcessIllustration({ step }: { step: number }) {
  const scene = scenes[step];
  return <div className="process-scene" aria-label={`${scene.label}: ${scene.title}`}>
    <svg viewBox="0 0 420 330" aria-hidden="true" className="process-scene-art"><path d="M38 98Q130 3 285 39T386 215Q300 335 117 291T38 98" fill="#ece8ff"/><path d="M29 205Q-4 42 181 23T399 153" fill="none" stroke="#1717d5" strokeWidth="2" strokeDasharray="5 9"/><path d="M346 44l4 9 10 1-8 6 2 10-8-5-9 5 3-10-8-6 10-1z" fill="#eab943"/></svg>
    <div className="process-paper"><span>{scene.label}</span><h3>{scene.title}</h3>{scene.lines.map(line => <p key={line}>{line}</p>)}<div className="process-paper-rule" /><small>{String(step + 1).padStart(2, '0')} / 05</small></div>
  </div>;
}
