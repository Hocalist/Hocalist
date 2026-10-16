import EditorialAccent from '../EditorialAccent';
import { OfflineNotice, PageShell } from '../site-content';

export const metadata = {
  title: 'Hocalist Safety | Offline payment guidance',
  description:
    'Safety guidance for Hocalist buyers and sellers coordinating local deals with offline item payment.'
};

const safetyItems = [
  {
    category: 'Meetup',
    title: 'Meet in public places',
    body: 'Choose visible, public locations and avoid private or isolated meetups.'
  },
  {
    category: 'Item check',
    title: 'Inspect before paying',
    body: 'Confirm condition, authenticity, and included items before handing over money.'
  },
  {
    category: 'Payment',
    title: 'Avoid unknown deposits',
    body: 'Do not send deposits to unknown parties before inspection and agreement.'
  },
  {
    category: 'Records',
    title: 'Keep records clear',
    body: 'Keep communication inside Hocalist where possible and use chat to confirm timing, condition, and meetup expectations.'
  },
  {
    category: 'Signals',
    title: 'Report suspicious behavior',
    body: 'Contact safety support if a user pressures you, asks for verification codes, changes terms, or acts unsafely.'
  },
  {
    category: 'Boundary',
    title: 'Understand the boundary',
    body: 'Hocalist facilitates discovery and coordination only. It does not guarantee transaction outcomes.'
  }
];

export default function SafetyPage() {
  return (
    <PageShell>
      <main>
        <section className="subpage-hero editorial-hero reveal"><EditorialAccent />
          <p className="eyebrow">Safety</p>
          <h1>A good exchange<br /><em>starts with care.</em></h1>
          <p>
            Hocalist is designed to make local buying coordination clearer. Buyers and sellers
            still need to use good judgment when meeting and arranging offline payment.
          </p>
        </section>
        <section className="page-section safety-guidance-section">
          <div className="safety-section-note reveal">
            <div>
              <p className="eyebrow">Practical guidance</p>
              <h2>Use these checks before you meet, inspect, or pay offline.</h2>
            </div>
            <p>
              Each card keeps the advice plain and action-focused, while the boundary note
              explains what Hocalist can and cannot do inside the marketplace.
            </p>
          </div>
          <div className="safety-guidance-grid" aria-label="Safety guidance checklist">
            {safetyItems.map((item, index) => (
              <article className="safety-guidance-card reveal" key={item.title}>
                <div className="safety-card-topline">
                  <span className="safety-card-number">{String(index + 1).padStart(2, '0')}</span>
                  <span className="safety-card-category">{item.category}</span>
                </div>
                <h2>{item.title}</h2>
                <p>{item.body}</p>
              </article>
            ))}
          </div>
          <OfflineNotice compact />
        </section>
        <section className="safety-report-section reveal">
          <div>
            <p className="eyebrow">Report a concern</p>
            <h2>Need Hocalist to review a safety issue?</h2>
            <p>
              Email support with the request, offer, chat, profile, or seller plan details that
              help explain what happened. Hocalist can review marketplace conduct and account
              concerns, while item payment disputes remain between buyer and seller.
            </p>
          </div>
          <div className="safety-report-actions">
            <a className="button primary" href="mailto:safety@hocalist.com?subject=Hocalist%20safety%20report">
              Email safety report
            </a>
            <a className="button secondary" href="mailto:support@hocalist.com?subject=Hocalist%20support%20request">
              Contact support
            </a>
          </div>
        </section>
      </main>
    </PageShell>
  );
}
