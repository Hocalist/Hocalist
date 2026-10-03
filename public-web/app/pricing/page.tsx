import Link from 'next/link';
import { OfflineNotice, PageShell, SectionIntro, faqItems, pricingPlans } from '../site-content';

const planDetails = [
  {
    badge: 'Profile launch',
    note: 'For sellers getting ready',
    metric: 'Setup',
    metricLabel: 'Profile and offer basics',
    action: { href: '/download', label: 'Join as an early seller', variant: 'secondary' }
  },
  {
    badge: 'Best seller fit',
    note: 'For active local sellers',
    metric: 'Growth',
    metricLabel: 'Visibility and response tools',
    action: { href: '/billing', label: 'Buy Pro from your account', variant: 'primary' }
  },
  {
    badge: 'Shop support',
    note: 'For higher-volume sellers',
    metric: 'Scale',
    metricLabel: 'Higher targeting and listing limits',
    action: { href: '/billing', label: 'Buy Elite from your account', variant: 'secondary' }
  }
];

const pricingProof = [
  'Monthly prices in USD',
  'Seller tools and visibility only',
  'Seller plan payment boundary',
  'Item payment stays between users'
];

export const metadata = {
  title: 'Hocalist Seller Pricing | Seller plans',
  description:
    'Seller plans for Hocalist tools, credits, and request visibility, with buyer-to-seller item payment arranged directly between users.'
};

export default function PricingPage() {
  return (
    <PageShell>
      <main>
        <section className="subpage-hero reveal">
          <p className="eyebrow">Seller pricing</p>
          <h1>Seller plans for local offer matching</h1>
          <p>
            Hocalist plans are for seller tools, credits, profile features, and buyer-request
            visibility. Buyers still compare offers and arrange item payment directly with sellers.
          </p>
        </section>

        <section className="page-section" id="seller-plans">
          <div className="pricing-section-head">
            <div className="pricing-section-copy">
              <p className="eyebrow">Seller plan options</p>
              <h2>Plans for seller tools, visibility, and profile support.</h2>
              <p>
                Monthly prices in USD. Seller plans and HocaCredits are purchased from your seller
                account on this website; billing runs in TEST mode until activation. HocaCredits
                are separate from weekly target limits. Buyer rewards are separate from seller
                credits. Annual plans and trials are not offered here.
              </p>
            </div>
            <div className="pricing-proof-strip" aria-label="Seller pricing boundaries">
              {pricingProof.map((item) => (
                <span key={item}>{item}</span>
              ))}
            </div>
          </div>

          <div className="pricing-grid pricing-page-grid">
            {pricingPlans.map((plan, index) => {
              const details = planDetails[index];

              return (
                <article
                  className={`pricing-card pricing-page-card ${plan.featured ? 'featured' : ''}`}
                  key={plan.name}
                >
                  <div className="plan-card-topline">
                    <span className="plan-badge">{details.badge}</span>
                    {plan.featured && <span className="plan-ribbon">Recommended</span>}
                  </div>
                  <div className="plan-card-heading">
                    <div>
                      <h2>{plan.name}</h2>
                      <p>{plan.summary}</p>
                    </div>
                    <div className="plan-signal" aria-label={`${details.metric}: ${details.metricLabel}`}>
                      <strong>{details.metric}</strong>
                      <span>{details.metricLabel}</span>
                    </div>
                  </div>
                  <div className="price">
                    <strong>{plan.price}</strong>
                    <span>{plan.cadence}</span>
                  </div>
                  <div className="plan-feature-group">
                    <span>Included seller support</span>
                    <ul>
                      {plan.features.map((feature) => (
                        <li key={feature}>{feature}</li>
                      ))}
                    </ul>
                  </div>
                  <div className="plan-action-row">
                    <Link
                      className={`button ${details.action.variant === 'primary' ? 'primary' : 'secondary'}`}
                      href={details.action.href}
                    >
                      {details.action.label}
                    </Link>
                    <p>{details.note}</p>
                  </div>
                </article>
              );
            })}
          </div>
          <OfflineNotice compact />
        </section>

        <section className="page-section">
          <SectionIntro
            eyebrow="Pricing FAQ"
            title="Clear answers for seller plans and buyer payments"
            body="Seller plans cover marketplace tools. Buyer-to-seller item payment is arranged directly between users."
          />
          <div className="faq-grid">
            {faqItems.map((item) => (
              <article className="faq-card" key={item.question}>
                <h2>{item.question}</h2>
                <p>{item.answer}</p>
              </article>
            ))}
          </div>
          <p className="pricing-policy-note">
            Seller billing policy details are available in the{' '}
            <a href="/refund-cancellation">refund and cancellation policy</a>.
          </p>
        </section>
      </main>
    </PageShell>
  );
}
