import Link from 'next/link';
import GuidedPreviewButton from './GuidedPreview';
import {
  OfflineNotice,
  PageShell,
  SectionIntro,
  faqItems,
  pricingPlans
} from './site-content';

const popularCategories = [
  { name: 'Phones & tablets', count: 'Sample category', cue: 'Unlocked devices, repairs, accessories', mark: 'PT' },
  { name: 'Home essentials', count: 'Sample category', cue: 'Furniture, small appliances, decor', mark: 'HE' },
  { name: 'Auto parts', count: 'Sample category', cue: 'Tires, batteries, trims, tools', mark: 'AP' },
  { name: 'Local services', count: 'Sample category', cue: 'Setup help, repairs, moving support', mark: 'LS' },
  { name: 'Kids & baby', count: 'Sample category', cue: 'Strollers, cribs, gear, toys', mark: 'KB' },
  { name: 'Events & gifts', count: 'Sample category', cue: 'Bundles, decor, last-minute finds', mark: 'EG' }
];

const recentRequests = [
  {
    title: 'Need a clean unlocked iPhone 14 Pro',
    meta: 'Phones & tablets - East Austin area',
    budget: '$360-$430',
    offers: 'Sample offers',
    tag: 'Preview request',
    status: 'Demo preview'
  },
  {
    title: 'Looking for a compact dining table',
    meta: 'Home - 10 mile radius',
    budget: '$120-$220',
    offers: 'Sample offers',
    tag: 'Photos requested',
    status: 'Example activity'
  }
];

const comparisonOffers = [
  {
    seller: 'Verified seller preview',
    price: '$395',
    condition: 'Good condition, 87% battery health',
    availability: 'Available tonight',
    distance: 'About 4 miles away',
    rating: '4.8 rating',
    status: 'Shortlisted'
  },
  {
    seller: 'Local shop preview',
    price: '$420',
    condition: 'Very good condition, case included',
    availability: 'Pickup tomorrow',
    distance: 'East Austin area',
    rating: 'Verified business',
    status: 'Selected preview'
  }
];

const workflowSteps = [
  {
    kicker: 'Start with demand',
    title: 'Buyer posts a request',
    body: 'A buyer describes what they need, where they are looking, and the budget range they have in mind.',
    image: '/images/how-it-works/buyer-request.png',
    alt: 'Buyer writing a local request on a phone'
  },
  {
    kicker: 'Sellers respond',
    title: 'Local sellers make offers',
    body: 'Sellers respond with relevant details, availability, condition notes, and any questions before the buyer chooses.',
    image: '/images/how-it-works/seller-offer.png',
    alt: 'Local seller preparing an offer for nearby buyer demand'
  },
  {
    kicker: 'Chat after choice',
    title: 'The buyer chooses a seller',
    body: 'Chat opens after selection so both sides can confirm timing, condition, meetup details, and how payment will be arranged.',
    image: '/images/how-it-works/buyer-seller-coordinate.png',
    alt: 'Buyer and seller coordinating details together'
  }
];

const sellerHighlights = [
  'Find buyers who are already looking for specific items',
  'Send targeted offers instead of broad ads to uninterested shoppers',
  'Use planned seller tools for visibility, reputation, and offer tracking'
];

const buyerHighlights = [
  'Describe the exact item, budget, and nearby area that work for you',
  'Compare seller price, condition, availability, and context in one place',
  'Choose a seller, then confirm details and arrange item payment directly'
];

const homepageFaqItems = [
  ...faqItems,
  {
    question: 'How do buyers receive offers?',
    answer:
      'Buyers post a request with the item, approximate area, budget, and useful details. Relevant sellers can then respond with offers for the buyer to compare.'
  },
  {
    question: 'When does buyer-seller chat open?',
    answer:
      'Chat opens after the buyer selects a seller so both sides can confirm condition, timing, meetup details, and how item payment will be arranged directly.'
  }
];

export default function HomePage() {
  return (
    <PageShell>
      <main className="homepage">
        <section className="hero marketplace-hero">
          <div className="hero-copy reveal hero-copy-card">
            <div className="hero-kicker">
              <span className="live-dot" aria-hidden="true" />
              Local reverse marketplace
            </div>
            <h1>Post a need. Get local offers.</h1>
            <p>
              Create a request, receive offers from local sellers, compare your options, and
              choose the best match before arranging details directly.
            </p>
            <div className="hero-actions">
              <Link className="button primary" href="/download">
                Get launch updates
              </Link>
              <Link className="button secondary seller-cta" href="/pricing">
                Join as an early seller
              </Link>
            </div>
            <div className="hero-proof" aria-label="Marketplace boundaries">
              <span>Buyer-led requests</span>
              <span>Seller offers</span>
              <span>Payment arranged by users</span>
            </div>
          </div>

          <div className="hero-stage reveal delay-1" aria-label="Hocalist request marketplace preview">
            <form className="request-panel" aria-label="Sample request composer preview">
              <div className="request-panel-header">
                <span>Sample request preview</span>
                <strong>Describe what you need</strong>
              </div>
              <label className="request-field wide">
                <span>What are you looking for?</span>
                <input readOnly value="Unlocked iPhone 13, clean condition" />
              </label>
              <div className="request-panel-grid">
                <label className="request-field">
                  <span>Category</span>
                  <input readOnly value="Phones & tablets" />
                </label>
                <label className="request-field">
                  <span>Location</span>
                  <input readOnly value="Austin, TX" />
                </label>
              </div>
              <label className="request-field wide">
                <span>Budget</span>
                <input readOnly value="$350-$450, pickup nearby" />
              </label>
              <GuidedPreviewButton kind="request" label="Preview request flow" />
              <p>
                Preview only. Hocalist supports discovery, offers, selection, and chat. Buyers
                and sellers arrange item payment directly after confirming the details.
              </p>
            </form>

            <div className="hero-preview-stack">
              <figure className="market-photo-card hero-context-photo">
                <img
                  alt="Buyer and seller coordinating around a local marketplace request"
                  src="/images/how-it-works/buyer-seller-coordinate.png"
                />
                <figcaption>Local supply meets buyer demand</figcaption>
              </figure>

              <article className="floating-card buyer-sample">
                <span className="status-chip success">Sample request</span>
                <h3>Unlocked phone by Friday</h3>
                <p>East Austin - prefers battery health above 85%</p>
                <div className="mini-meta">
                  <strong>$360-$430</strong>
                  <span>Sample offers</span>
                </div>
              </article>

              <article className="floating-card seller-sample">
                <div>
                  <span className="seller-avatar">S</span>
                  <strong>Seller offer preview</strong>
                </div>
                <p>Clean device, case included, available tonight.</p>
                <span className="offer-chip">Best match</span>
              </article>
            </div>
          </div>
        </section>

        <section className="market-strip reveal delay-2" aria-label="Hocalist marketplace model preview">
          <span>
            <strong>2-sided</strong>
            Buyer and seller marketplace
          </span>
          <span>
            <strong>Offer-first</strong>
            Sellers respond to demand
          </span>
          <span>
            <strong>Chat after choice</strong>
            Details finalized together
          </span>
          <span>
            <strong>User-arranged payment</strong>
            Buyers and sellers arrange the item payment
          </span>
        </section>

        <section className="category-ribbon" aria-label="Fast moving request categories">
          <div className="category-track">
            {popularCategories.concat(popularCategories).map((category, index) => (
              <span key={`${category.name}-${index}`}>{category.name}</span>
            ))}
          </div>
        </section>

        <section className="page-section category-section" id="categories">
          <SectionIntro
            eyebrow="Sample request categories"
            title="Local demand, organized around what buyers actually need"
            body="Preview categories show how buyer demand can be organized once marketplace activity is live."
          />
          <div className="category-grid">
            {popularCategories.map((category) => (
              <article className="category-card reveal" key={category.name}>
                <div className="category-icon">{category.mark}</div>
                <span>{category.count}</span>
                <h3>{category.name}</h3>
                <p>{category.cue}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="page-section request-section" id="requests">
          <div>
            <SectionIntro
              align="left"
              eyebrow="Sample buyer requests"
              title="Buyer requests give sellers a clear starting point"
              body="Demo request cards show the public-safe information sellers can review without exposing exact addresses or direct contact details."
            />
            <Link className="text-link" href="/how-it-works">
              See the request flow
            </Link>
          </div>
          <div className="request-card-list">
            {recentRequests.map((request) => (
              <article className="buyer-request-card reveal" key={request.title}>
                <div>
                  <span className="status-chip">{request.status}</span>
                  <h3>{request.title}</h3>
                  <p>{request.meta}</p>
                </div>
                <div className="request-card-meta">
                  <strong>{request.budget}</strong>
                  <span>{request.offers}</span>
                  <em>{request.tag}</em>
                </div>
              </article>
            ))}
          </div>
        </section>

        <section className="page-section offer-comparison-section" aria-labelledby="offer-comparison-title">
          <div className="offer-comparison-copy reveal">
            <p className="eyebrow">Offer comparison preview</p>
            <h2 id="offer-comparison-title">One request, several seller offers, one clear next step.</h2>
            <p>
              Buyers compare price, condition, availability, approximate location, and seller
              context before selecting a seller. Other valid offers can remain available as
              backups if a selected deal fails.
            </p>
          </div>
          <div className="offer-comparison-card reveal delay-1" aria-label="Demo offer comparison">
            <div className="comparison-request">
              <span className="status-chip">Demo preview</span>
              <h3>Buyer request: iPhone 14 Pro, 256 GB</h3>
              <p>Good condition, local pickup preferred, East Austin area. No exact address or direct contact shown.</p>
            </div>
            <div className="comparison-offers">
              {comparisonOffers.map((offer) => (
                <article className="comparison-offer" key={offer.seller}>
                  <div>
                    <span className="status-chip success">{offer.status}</span>
                    <h4>{offer.seller}</h4>
                    <strong>{offer.price}</strong>
                  </div>
                  <ul>
                    <li>{offer.condition}</li>
                    <li>{offer.availability}</li>
                    <li>{offer.distance}</li>
                    <li>{offer.rating}</li>
                  </ul>
                  <GuidedPreviewButton kind="select" label="Preview select seller" />
                </article>
              ))}
            </div>
            <p className="comparison-note">
              Chat unlocks after seller selection. Backup offers are not shown as deleted in this preview.
            </p>
          </div>
        </section>

        <section className="page-section workflow-section" id="how-it-works">
          <SectionIntro
            eyebrow="How Hocalist works"
            title="A simple path from request to seller chat"
            body="Buyers post what they need, compare seller offers, choose who to continue with, and coordinate the item payment directly after agreement."
          />
          <div className="workflow-grid">
            {workflowSteps.map((step, index) => (
              <article className="workflow-card reveal" key={step.title}>
                <figure className="workflow-photo">
                  <img alt={step.alt} src={step.image} />
                </figure>
                <div className="workflow-card-copy">
                  <span>{String(index + 1).padStart(2, '0')}</span>
                  <p className="workflow-kicker">{step.kicker}</p>
                  <h3>{step.title}</h3>
                  <p>{step.body}</p>
                </div>
              </article>
            ))}
          </div>
        </section>

        <section className="page-section role-split">
          <article className="role-panel buyer-panel reveal">
            <p className="eyebrow">For buyers</p>
            <h2>Stop searching every listing. Let sellers come to your request.</h2>
            <ul>
              {buyerHighlights.map((highlight) => (
                <li key={highlight}>{highlight}</li>
              ))}
            </ul>
            <figure className="role-photo">
              <img
                alt="Buyer writing a local marketplace request on a phone"
                src="/images/how-it-works/buyer-request.png"
              />
            </figure>
            <Link className="button primary" href="/download">
              Get launch updates
            </Link>
          </article>
          <article className="role-panel seller-panel reveal delay-1">
            <p className="eyebrow">For sellers</p>
            <h2>Respond to real buyer intent with focused offers.</h2>
            <ul>
              {sellerHighlights.map((highlight) => (
                <li key={highlight}>{highlight}</li>
              ))}
            </ul>
            <figure className="role-photo">
              <img
                alt="Local seller preparing an offer for a nearby buyer request"
                src="/images/how-it-works/seller-offer.png"
              />
            </figure>
            <Link className="button secondary" href="/pricing">
              Seller plan preview
            </Link>
          </article>
        </section>

        <section className="page-section seller-plan-section" id="seller-plans">
          <SectionIntro
            eyebrow="Seller plans and credits"
            title="Built-in plans for sellers who want better request visibility"
            body="Seller plans and HocaCredits are purchased from your seller account on this website; billing runs in TEST mode until activation. HocaCredits and targeting fees are separate from subscriptions and weekly target limits."
          />
          <div className="pricing-grid compact-pricing">
            {pricingPlans.map((plan) => (
              <article className={`pricing-card ${plan.featured ? 'featured' : ''}`} key={plan.name}>
                {plan.featured && <span className="plan-ribbon">Popular seller tier</span>}
                <h3>{plan.name}</h3>
                <p>{plan.summary}</p>
                <div className="price">
                  <strong>{plan.price}</strong>
                  <span>{plan.cadence}</span>
                </div>
                <ul>
                  {plan.features.slice(0, 4).map((feature) => (
                    <li key={feature}>{feature}</li>
                  ))}
                </ul>
              </article>
            ))}
          </div>
        </section>

        <section className="page-section safety-section">
          <div className="safety-copy reveal">
            <p className="eyebrow">Safety and coordination</p>
            <h2>Clear steps from offer review to buyer-seller agreement</h2>
            <p>
              Hocalist supports request discovery, seller offers, buyer selection, and chat. Buyers
              and sellers can inspect, agree on details, and arrange item payment directly with
              each other.
            </p>
            <Link className="text-link" href="/safety">
              Read safety guidance
            </Link>
          </div>
          <div className="safety-card-stack reveal delay-1">
            <OfflineNotice />
            <article className="safety-mini-card">
              <span className="status-chip gold">Buyer and seller clarity</span>
              <h3>Hocalist keeps discovery separate from item payment.</h3>
              <p>Buyers and sellers handle item payment directly after inspection and agreement.</p>
            </article>
          </div>
        </section>

        <section className="page-section faq-section">
          <SectionIntro
            eyebrow="Common questions"
            title="Clear answers for buyers, sellers, and reviewers"
            body="A simple summary of buyer requests, seller offers, account billing, and payment arranged by users."
          />
          <div className="faq-grid">
            {homepageFaqItems.map((item) => (
              <article className="faq-card reveal" key={item.question}>
                <h3>{item.question}</h3>
                <p>{item.answer}</p>
              </article>
            ))}
          </div>
        </section>
      </main>
    </PageShell>
  );
}
