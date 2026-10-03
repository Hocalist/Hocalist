import Link from 'next/link';
import Image from 'next/image';
import { MobileMenu } from './MobileMenu';

export const siteNav = [
  { href: '/', label: 'Home' },
  { href: '/#requests', label: 'Preview requests' },
  { href: '/how-it-works', label: 'How it works' },
  { href: '/pricing', label: 'Seller plans' },
  { href: '/safety', label: 'Safety' },
  { href: '/support', label: 'Support' }
];

export const legalNav = [
  { href: '/terms', label: 'Terms' },
  { href: '/privacy', label: 'Privacy' },
  { href: '/download', label: 'App updates' }
];

export const sellerPlanUrl = process.env.NEXT_PUBLIC_SELLER_PLAN_URL || '';

const headerCtas = [
  { href: '/download', label: 'Join buyer waitlist' },
  { href: '/pricing', label: 'Seller plans' }
];

export function SiteHeader() {
  return (
    <header className="site-header">
      <Link aria-label="Hocalist home" className="brand-link" href="/">
        <Image className="brand-wordmark" src="/brand/hocalist-wordmark.png" width={184} height={86} alt="Hocalist Reverse Marketplace" priority />
      </Link>
      <nav aria-label="Primary navigation" className="desktop-nav">
        {siteNav.map((item) => (
          <Link href={item.href} key={item.href}>
            {item.label}
          </Link>
        ))}
      </nav>
      <MobileMenu ctaItems={headerCtas} navItems={siteNav} />
      <div className="header-actions">
        <Link className="ghost-link" href="/pricing">
          Seller plans
        </Link>
        <Link className="button primary small" href="/download">
          Join buyer waitlist
        </Link>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="footer-grid">
        <div>
          <Link className="brand-link footer-brand" href="/">
            <Image className="brand-wordmark footer-wordmark" src="/brand/hocalist-wordmark.png" width={184} height={86} alt="Hocalist Reverse Marketplace" />
          </Link>
          <p>
            Hocalist helps buyers post local requests, compare seller offers, choose who to
            continue with, and coordinate the deal details directly.
          </p>
          <p className="fine-print">
            Sellers can use plans, credits, and profile tools to respond to active local demand.
          </p>
        </div>
        <FooterColumn title="Company" links={siteNav} />
        <FooterColumn title="Legal" links={legalNav} />
        <div>
          <h2>Support</h2>
          <p>Email: support@hocalist.com</p>
          <p>For written notices, email support for current mailing details.</p>
          <p className="fine-print">We aim to respond within 2 business days.</p>
        </div>
      </div>
      <div className="footer-bottom">
        <span>(c) 2026 Hocalist. All rights reserved.</span>
        <span>Buyer requests, seller offers, chat coordination, and item payment arranged by users.</span>
      </div>
    </footer>
  );
}

function FooterColumn({
  title,
  links
}: {
  title: string;
  links: Array<{ href: string; label: string }>;
}) {
  return (
    <div>
      <h2>{title}</h2>
      <ul>
        {links.map((link) => (
          <li key={link.href}>
            <Link href={link.href}>{link.label}</Link>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function SellerPlanLink({
  children,
  className = 'button primary'
}: {
  children: React.ReactNode;
  className?: string;
}) {
  if (sellerPlanUrl) {
    return (
      <a className={className} href={sellerPlanUrl}>
        {children}
      </a>
    );
  }

  return (
    <Link className={className} href="/pricing#seller-plans">
      {children}
    </Link>
  );
}

export function PageShell({ children }: { children: React.ReactNode }) {
  return (
    <>
      <SiteHeader />
      {children}
      <SiteFooter />
    </>
  );
}

export function SectionIntro({
  eyebrow,
  title,
  body,
  align = 'center'
}: {
  eyebrow: string;
  title: string;
  body: string;
  align?: 'center' | 'left';
}) {
  return (
    <div className={`section-intro ${align === 'left' ? 'left' : ''}`}>
      <p className="eyebrow">{eyebrow}</p>
      <h2>{title}</h2>
      <p>{body}</p>
    </div>
  );
}

export function OfflineNotice({ compact = false }: { compact?: boolean }) {
  return (
    <aside className={`offline-notice ${compact ? 'compact' : ''}`}>
      <span aria-hidden="true">!</span>
      <div>
        <strong>Offline item payment boundary</strong>
        <p>
          Hocalist helps buyers and sellers discover, compare, choose, and coordinate. Item
          payment is arranged directly between buyer and seller after inspection and agreement.
        </p>
      </div>
    </aside>
  );
}

export function MarketplaceSnapshot() {
  return (
    <div aria-label="Hocalist marketplace model" className="marketplace-snapshot">
      <div className="snapshot-header">
        <span>Marketplace model</span>
        <strong>Buyer + seller coordination</strong>
      </div>
      <dl>
        <div>
          <dt>Buyers</dt>
          <dd>Post what they want, compare offers, choose a seller, and chat.</dd>
        </div>
        <div>
          <dt>Sellers</dt>
          <dd>Respond to buyer requests, manage offers, and build a local profile.</dd>
        </div>
        <div>
          <dt>Seller billing</dt>
          <dd>Used for seller plans, credits, promoted visibility, and marketplace tools.</dd>
        </div>
        <div>
          <dt>Item payment</dt>
          <dd>Arranged directly between buyer and seller after inspection and agreement.</dd>
        </div>
      </dl>
    </div>
  );
}

export const pricingPlans = [
  {
    name: 'Free',
    price: '$0',
    cadence: 'USD / month',
    summary: 'For sellers preparing a profile before wider marketplace launch.',
    features: ['10 customer targets per week', 'Up to 3 Store listings', 'Create a seller profile', 'Targeting fees are separate'],
    action: 'Join as an early seller'
  },
  {
    name: 'Pro Seller',
    price: '$15',
    cadence: 'USD / month',
    summary: 'For active local sellers who need more buyer-request visibility and offer tools.',
    features: [
      '50 customer targets per week',
      'Up to 15 Store listings',
      'Seller contacts and recommendations',
      'Targeting fees are separate'
    ],
    action: 'Request early seller access',
    featured: true
  },
  {
    name: 'Elite Seller',
    price: '$30',
    cadence: 'USD / month',
    summary: 'For sellers who need higher targeting and Store listing limits.',
    features: [
      '100 customer targets per week',
      'Up to 50 Store listings',
      'Seller contacts and recommendations',
      'Targeting fees are separate'
    ],
    action: 'Contact seller support'
  }
];

export const faqItems = [
  {
    question: 'What am I paying Hocalist for?',
    answer:
      'Subscriptions pay for seller tools and plan limits. HocaCredits are purchased separately for eligible targeting fees; a weekly target allowance does not include those fees. Item purchases are paid directly between buyers and sellers.'
  },
  {
    question: 'Does Hocalist process item payments?',
    answer:
      'No. Hocalist helps buyers and sellers discover, compare, chat, and coordinate. Item payment is arranged offline between buyer and seller.'
  },
  {
    question: 'Can I cancel my seller plan?',
    answer:
      'Seller subscriptions can be cancelled according to the account billing terms shown during the seller plan flow.'
  },
  {
    question: 'Are seller credits refundable?',
    answer:
      'Unused credits or promotional fees are reviewed according to the seller product purchased. Used credits and consumed promotional placements are generally not refundable.'
  }
];

export const policyUpdated = 'Last updated: July 8, 2026';

export function PolicyPage({
  title,
  lead,
  sections,
  updated = policyUpdated
}: {
  title: string;
  lead: string;
  sections: Array<{ title: string; body: string[] }>;
  updated?: string;
}) {
  return (
    <PageShell>
      <main className="policy-page">
        <section className="policy-hero reveal">
          <p className="eyebrow">{updated}</p>
          <h1>{title}</h1>
          <p>{lead}</p>
        </section>
        <section className="policy-layout">
          <aside className="policy-toc" aria-label={`${title} sections`}>
            {sections.map((section) => (
              <a href={`#${slugify(section.title)}`} key={section.title}>
                {section.title}
              </a>
            ))}
          </aside>
          <article className="policy-card">
            {sections.map((section) => (
              <section id={slugify(section.title)} key={section.title}>
                <h2>{section.title}</h2>
                {section.body.map((paragraph) => (
                  <p key={paragraph}>{paragraph}</p>
                ))}
              </section>
            ))}
          </article>
        </section>
      </main>
    </PageShell>
  );
}

function slugify(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}
