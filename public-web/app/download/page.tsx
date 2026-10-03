import Link from 'next/link';
import WaitlistForm from '../WaitlistForm';
import { PageShell } from '../site-content';

export const metadata = {
  title: 'Hocalist Mobile App | Early access updates',
  description: 'Hocalist Android and iOS early access updates for buyer requests, seller offers, chat coordination, and local marketplace access.'
};

const playStoreUrl = process.env.NEXT_PUBLIC_PLAY_STORE_URL || '';
const appStoreUrl = process.env.NEXT_PUBLIC_APP_STORE_URL || '';

export default function DownloadPage() {
  return (
    <PageShell>
      <main className="download-page">
        <section className="download-hero reveal">
          <div className="download-hero-copy">
            <p className="eyebrow">Early access updates</p>
            <h1>Get notified when Hocalist app access is ready.</h1>
            <p>
              Describe what you want, compare seller offers, choose who to continue with, and use
              chat to coordinate the details before arranging item payment directly with the seller.
            </p>
            <div className="download-hero-actions">
              <Link className="button primary" href="/how-it-works">
                See how it works
              </Link>
              <Link className="button secondary" href="/support">
                Request early access
              </Link>
            </div>
            <div className="download-status-row" aria-label="App availability">
              <span>Android and iOS planned</span>
              <span>Buyer requests</span>
              <span>Seller offers</span>
            </div>
          </div>
          <div className="download-phone-stage" aria-label="Hocalist mobile app preview">
            <div className="download-phone-orbit download-phone-orbit-one" aria-hidden="true" />
            <div className="download-phone-orbit download-phone-orbit-two" aria-hidden="true" />
            <div className="download-phone">
              <div className="download-phone-top">
                <span>9:41</span>
                <span>Hocalist</span>
              </div>
              <div className="download-phone-screen">
                <div className="phone-request-card">
                  <span className="status-chip success">App preview</span>
                  <h2>What do you want to buy?</h2>
                  <p>Used dining table near me, flexible pickup this week.</p>
                  <div className="phone-chip-row">
                    <span>Home</span>
                    <span>$150-$300</span>
                    <span>Nearby</span>
                  </div>
                </div>
                <div className="phone-offer-card phone-offer-card-one">
                  <strong>Sample seller offers</strong>
                  <span>Compare details before choosing</span>
                </div>
                <div className="phone-offer-card phone-offer-card-two">
                  <strong>Chat opens after selection</strong>
                  <span>Coordinate condition, timing, and handoff</span>
                </div>
                <div className="phone-bottom-bar">
                  <span />
                  <span />
                  <span />
                </div>
              </div>
            </div>
            <div className="download-float-card download-float-card-left">
              <strong>Buyer request</strong>
              <span>Post once. Let sellers respond.</span>
            </div>
            <div className="download-float-card download-float-card-right">
              <strong>Local coordination</strong>
              <span>Details happen in chat.</span>
            </div>
          </div>
        </section>

        <section className="download-panel">
          <article className="reveal">
            <span className="status-chip">Android</span>
            <h2>Android app</h2>
            <p>
              Android availability gives buyers and sellers a mobile-first way to post requests,
              review offers, and coordinate locally.
            </p>
            {playStoreUrl ? (
              <a className="button primary small" href={playStoreUrl}>Get it on Google Play</a>
            ) : (
              <p className="store-availability">Not available to download yet. Store links appear here once the listing is live.</p>
            )}
          </article>
          <article className="reveal delay-1">
            <span className="status-chip gold">iOS</span>
            <h2>iOS app</h2>
            <p>
              iOS availability keeps the same request-led marketplace experience available for
              Apple device users.
            </p>
            {appStoreUrl ? (
              <a className="button primary small" href={appStoreUrl}>Download on the App Store</a>
            ) : (
              <p className="store-availability">Not available to download yet. Store links appear here once the listing is live.</p>
            )}
          </article>
          <article className="reveal delay-2">
            <span className="status-chip success">Launch updates</span>
            <h2>Buyer and seller availability</h2>
            <p>
              Buyers can post requests and compare offers, while sellers can use plans, credits,
              and profile features to respond to local demand.
            </p>
          </article>
        </section>
        <section className="download-flow-section reveal">
          <div>
            <p className="eyebrow">Request-led marketplace</p>
            <h2>Hocalist is designed around the buyer request, not a product cart.</h2>
          </div>
          <ol>
            <li>Post what you want and the details sellers need.</li>
            <li>Compare seller responses and choose who to continue with.</li>
            <li>Use chat to coordinate condition, timing, and local handoff details.</li>
          </ol>
        </section>
        <section className="cta-band download-cta-band">
          <h2>Want to be notified when app access is ready?</h2>
          <p>
            Join the consented launch update list below. The form stores only your address, the
            consent version and time. If the list is not open on this deployment it says so and
            stores nothing.
          </p>
          <WaitlistForm />
          <div>
            <Link className="button secondary" href="mailto:support@hocalist.com?subject=Hocalist%20app%20availability">
              Email launch updates
            </Link>
            <Link className="button secondary" href="/support">
              Contact support
            </Link>
          </div>
        </section>
      </main>
    </PageShell>
  );
}
