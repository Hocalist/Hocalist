import { OfflineNotice, PageShell } from '../site-content';

export const metadata = {
  title: 'How Hocalist Works | Buyer requests and seller offers',
  description:
    'Hocalist helps buyers post local buying requests, compare seller offers, chat, and coordinate offline item payment.'
};

const steps = [
  {
    kicker: 'Buyer request',
    title: 'Buyer posts a request',
    body: 'The buyer describes what they want, their budget range, location, and timing.',
    image: '/images/how-it-works/buyer-request.png',
    alt: 'Buyer writing a local marketplace request on a phone',
    visual: 'request',
    badge: 'Request posted',
    detail: 'Budget, location, timing'
  },
  {
    kicker: 'Offer matching',
    title: 'Sellers send offers',
    body: 'Local sellers respond with tailored offers, details, availability, and profile context.',
    image: '/images/how-it-works/seller-offer.png',
    alt: 'Seller preparing items for nearby buyer requests',
    visual: 'offers',
    badge: 'Offers arrive',
    detail: 'Compare seller context'
  },
  {
    kicker: 'Buyer control',
    title: 'Buyer chooses who to continue with',
    body: 'The buyer compares offers and can accept more than one seller while comparing; each gets a separate chat and meeting.',
    image: '/images/how-it-works/buyer-seller-coordinate.png',
    alt: 'Buyer and seller reviewing details together',
    visual: 'choose',
    badge: 'Buyer chooses',
    detail: 'One purchase seller at the end',
    frameTitle: 'Offer shortlist',
    frameItems: ['Several sellers accepted', 'Profile checked', 'Next step: chat']
  },
  {
    kicker: 'Private coordination',
    title: 'Chat opens for details',
    body: 'The buyer and seller confirm condition, meetup details, and any remaining questions.',
    image: '/images/how-it-works/buyer-seller-coordinate.png',
    alt: 'People coordinating details through a phone',
    visual: 'chat',
    badge: 'Chat opens',
    detail: 'Questions and meetup details',
    frameTitle: 'Chat detail',
    frameItems: ['Condition confirmed', 'Pickup window set', 'Questions resolved']
  },
  {
    kicker: 'Outside Hocalist',
    title: 'Offline payment and handoff',
    body: 'The parties inspect, confirm, and arrange item payment outside Hocalist.',
    image: '/images/how-it-works/buyer-seller-coordinate.png',
    alt: 'Local handoff after buyer and seller agreement',
    visual: 'handoff',
    badge: 'Outside Hocalist',
    detail: 'Inspect, confirm, pay offline',
    frameTitle: 'Handoff checklist',
    frameItems: ['Inspect item', 'Confirm details', 'Pay directly offline']
  }
];

export default function HowItWorksPage() {
  return (
    <PageShell>
      <main>
        <section className="subpage-hero reveal">
          <p className="eyebrow">How it works</p>
          <h1>How Hocalist works</h1>
          <p>
            Hocalist helps buyers post requests, compare seller offers, choose who to continue
            with, and coordinate details before arranging item payment directly with the seller.
          </p>
        </section>
        <section className="timeline-section">
          {steps.map((step, index) => (
            <article className="timeline-card reveal" key={step.title}>
              <figure className={`timeline-photo timeline-photo-${step.visual}`}>
                <img alt={step.alt} src={step.image} />
                {step.frameItems && (
                  <div className="timeline-ui-frame" aria-hidden="true">
                    <span>{step.frameTitle}</span>
                    {step.frameItems.map((item) => (
                      <em key={item}>{item}</em>
                    ))}
                  </div>
                )}
                <figcaption>
                  <strong>{step.badge}</strong>
                  <span>{step.detail}</span>
                </figcaption>
              </figure>
              <div className="timeline-card-copy">
                <span>{String(index + 1).padStart(2, '0')}</span>
                <p className="workflow-kicker">{step.kicker}</p>
                <h2>{step.title}</h2>
                <p>{step.body}</p>
              </div>
            </article>
          ))}
        </section>
        <section className="page-section">
          <OfflineNotice />
        </section>
      </main>
    </PageShell>
  );
}
