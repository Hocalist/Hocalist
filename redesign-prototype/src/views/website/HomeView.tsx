import React, { useState } from 'react';
import { WebsiteRoute } from '../../types';
import {
  ArrowRight,
  Shield,
  CheckCircle2,
  Sparkles,
  MapPin,
  Clock,
  DollarSign,
  Search,
  ChevronDown,
  ChevronUp,
  Store,
  Lock,
  Layers,
  Zap,
  TrendingUp,
  Award
} from 'lucide-react';

interface HomeViewProps {
  setRoute: (r: WebsiteRoute) => void;
}

export const HomeView: React.FC<HomeViewProps> = ({ setRoute }) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [openFaq, setOpenFaq] = useState<number | null>(0);

  const sampleDemands = [
    {
      category: 'Electronics',
      title: 'Apple iPad Air 5th Gen (64GB)',
      budget: '$350 – $400',
      location: 'Within 5 miles',
      condition: 'Mint / Open Box',
      offersCount: 3,
      time: '14m ago',
      img: '/assets/ipad-air.png'
    },
    {
      category: 'Computers',
      title: 'Lenovo Legion Pro Gaming Laptop',
      budget: '$850 – $950',
      location: 'Within 10 miles',
      condition: 'Excellent',
      offersCount: 2,
      time: '32m ago',
      img: '/assets/gaming-laptop.png'
    },
    {
      category: 'Home & Living',
      title: 'Mid-Century Teak Coffee Table',
      budget: '$150 – $220',
      location: 'Within 8 miles',
      condition: 'Good condition',
      offersCount: 4,
      time: '1h ago',
      img: '/assets/living-room-furniture.png'
    },
    {
      category: 'Tools & Hardware',
      title: 'Electric Pressure Washer 2000+ PSI',
      budget: '$100 – $140',
      location: 'Within 12 miles',
      condition: 'Working order',
      offersCount: 2,
      time: '2h ago',
      img: '/assets/pressure-washer.png'
    }
  ];

  const faqs = [
    {
      q: 'How does Hocalist reverse marketplace work?',
      a: 'Instead of searching static catalogs with outdated prices, buyers post what they want, their budget, and location. Local verified stores and sellers send direct offers to you. You choose the best offer, open private chat, agree on a meetup, inspect the item in person, and pay offline directly.'
    },
    {
      q: 'Does Hocalist charge buyers any fees or process item payments?',
      a: 'Zero fees for buyers. Hocalist does not process buyer-to-seller item payments, hold escrow, or ship items. Item payments are finalized and settled directly offline between buyer and seller upon physical inspection.'
    },
    {
      q: 'What is the 5-Digit Purchase PIN protocol?',
      a: 'When you accept an offer and agree to meet, Hocalist gives you a secure 5-digit PIN. During your in-person meeting, only after inspecting and testing the item to your full satisfaction, you give this PIN to the seller. Entering the PIN validates the deal and unlocks your buyer rewards.'
    },
    {
      q: 'What do sellers pay for on Hocalist?',
      a: 'Sellers pay for access to high-intent local customer demand. Plans range from Starter ($0/mo, 10 weekly customer targets) to Pro ($15/mo, 50 targets) and Elite ($30/mo, 100 targets). Prepaid HocaCredits cover small customer targeting fees with transparent, frozen deposit batch rates ($20 or $40 deposits).'
    },
    {
      q: 'Where do meetups happen?',
      a: 'At verified seller storefronts or designated public safe exchange zones (such as local police station parking lots, bank lobbies, or busy coffee shops). Never meet in secluded areas or send money in advance.'
    }
  ];

  return (
    <div className="pro-home">
      {/* =========================================================================
          HERO: High-Impact, Minimalist, Silicon-Valley Caliber
         ========================================================================= */}
      <section className="pro-hero">
        <div className="container">
          <div className="pro-hero-badge-wrap">
            <div className="pro-badge">
              <span className="live-pulse" />
              <span>The In-Person Reverse Marketplace</span>
            </div>
          </div>

          <h1 className="pro-hero-title">
            Buy anything locally. <br />
            <span className="text-gradient">Without the endless searching.</span>
          </h1>

          <p className="pro-hero-sub">
            Post what you need and what you want to pay. Competing local stores and verified sellers pitch their best offers directly to you. Meet locally, inspect in person, and pay offline.
          </p>

          {/* Sleek Interactive Search Bar */}
          <div className="pro-search-box">
            <div className="search-input-wrap">
              <Search className="search-icon" size={20} />
              <input
                type="text"
                placeholder="What are you looking for? (e.g. iPad Air, M2 MacBook, Lawn Mower...)"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') setRoute('download');
                }}
              />
            </div>
            <button className="btn btn-primary btn-search" onClick={() => setRoute('download')}>
              <span>Get Offers</span>
              <ArrowRight size={18} />
            </button>
          </div>

          {/* Boundary Notice Strip */}
          <div className="pro-hero-trust-bar">
            <div className="trust-pill">
              <CheckCircle2 size={15} className="text-success" />
              <span>100% Free for Buyers</span>
            </div>
            <span className="divider-dot">•</span>
            <div className="trust-pill">
              <Shield size={15} className="text-navy" />
              <span>Offline In-Person Item Payment</span>
            </div>
            <span className="divider-dot">•</span>
            <div className="trust-pill">
              <Lock size={15} className="text-navy" />
              <span>5-Digit PIN Verification</span>
            </div>
            <span className="divider-dot">•</span>
            <div className="trust-pill">
              <Store size={15} className="text-navy" />
              <span>Verified Local Businesses</span>
            </div>
          </div>

          {/* High-End Visual Showcase */}
          <div className="pro-hero-showcase">
            <div className="showcase-glow" />
            <div className="showcase-stage">
              {/* Left Floating Card: Buyer Request */}
              <div className="sc-card sc-request-card">
                <div className="sc-card-header">
                  <span className="sc-chip navy">Buyer Request</span>
                  <span className="sc-time"><Clock size={12} /> Just now</span>
                </div>
                <div className="sc-item-row">
                  <img src="/assets/ipad-air.png" alt="iPad Air" className="sc-thumb" />
                  <div>
                    <h4>Apple iPad Air 5th Gen (64GB)</h4>
                    <span className="sc-meta-sub">Space Gray • Mint Condition</span>
                  </div>
                </div>
                <div className="sc-tags">
                  <span className="sc-tag"><DollarSign size={12} /> Target: $350 – $400</span>
                  <span className="sc-tag"><MapPin size={12} /> Chicago, IL (5 mi)</span>
                </div>
              </div>

              {/* Center Main: Merchant Interaction Stream */}
              <div className="sc-center-hero-frame">
                <img
                  src="/assets/seller-home-person.png"
                  alt="Verified Local Merchant"
                  className="sc-hero-img"
                />
                <div className="sc-hero-glass-bar">
                  <div className="merchant-info">
                    <img src="/brand/hocalist-brand-circled-background.png" alt="Avatar" className="m-avatar" />
                    <div>
                      <strong>Northside Tech Hub</strong>
                      <span>Verified Local Store • 1.8 mi away</span>
                    </div>
                  </div>
                  <div className="merchant-bid">
                    <span className="bid-label">Offer Sent</span>
                    <span className="bid-amount">$365</span>
                  </div>
                </div>
              </div>

              {/* Right Floating Card: Confirmed Meeting & Offline PIN */}
              <div className="sc-card sc-offer-card">
                <div className="sc-card-header">
                  <span className="sc-chip green">Deal Matched</span>
                  <span className="sc-time">Direct Chat Open</span>
                </div>
                <div className="sc-meet-box">
                  <div className="sc-meet-title">
                    <MapPin size={14} className="text-navy" />
                    <span>Starbucks Safe Exchange Zone</span>
                  </div>
                  <p className="sc-meet-note">
                    "Meeting confirmed for today 3:30 PM. Item tested and boxed."
                  </p>
                </div>
                <div className="sc-pin-strip">
                  <div className="pin-label">
                    <Lock size={12} />
                    <span>Buyer PIN:</span>
                  </div>
                  <span className="pin-numbers">4 • 8 • 2 • 0 • 5</span>
                  <span className="pin-rule">Give to seller only after inspecting</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* =========================================================================
          HOW IT WORKS: 3 Clean Pillars (01 - 02 - 03)
         ========================================================================= */}
      <section className="pro-section bg-subtle">
        <div className="container">
          <div className="section-head text-center">
            <span className="eyebrow">A Better Way to Transact</span>
            <h2 className="section-h2">How the reverse marketplace works</h2>
            <p className="section-p">
              Traditional marketplaces force you to spend hours scrolling through stale listings. Hocalist flips the model so local sellers work for your business.
            </p>
          </div>

          <div className="three-pillars-grid">
            <div className="pillar-card">
              <div className="pillar-num">01</div>
              <div className="pillar-icon-box">
                <Layers size={24} className="text-navy" />
              </div>
              <h3 className="pillar-title">You post what you need</h3>
              <p className="pillar-desc">
                Specify the exact item or service, your target budget range, condition preferences, and location radius. No browsing hundreds of expired listings.
              </p>
              <div className="pillar-footer-tip">
                ✓ Free to post • Zero buyer fees
              </div>
            </div>

            <div className="pillar-card">
              <div className="pillar-num">02</div>
              <div className="pillar-icon-box">
                <Zap size={24} className="text-navy" />
              </div>
              <h3 className="pillar-title">Verified sellers compete</h3>
              <p className="pillar-desc">
                Nearby merchants and qualified sellers receive your request and send tailored offers with photos, availability, and transparent pricing.
              </p>
              <div className="pillar-footer-tip">
                ✓ Compare distance, rating & price
              </div>
            </div>

            <div className="pillar-card">
              <div className="pillar-num">03</div>
              <div className="pillar-icon-box">
                <Shield size={24} className="text-navy" />
              </div>
              <h3 className="pillar-title">Inspect & pay offline</h3>
              <p className="pillar-desc">
                Accept the best offer, finalize meeting details in private chat, inspect the item in person at a safe exchange zone, and settle payment directly offline.
              </p>
              <div className="pillar-footer-tip">
                ✓ 5-digit PIN security validation
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* =========================================================================
          LIVE LOCAL DEMAND SHOWCASE
         ========================================================================= */}
      <section className="pro-section">
        <div className="container">
          <div className="section-head-split">
            <div>
              <span className="eyebrow">Real Marketplace Activity</span>
              <h2 className="section-h2">What buyers are requesting right now</h2>
              <p className="section-p">
                Real customer needs posted across electronics, home goods, vehicles, and services.
              </p>
            </div>
            <button className="btn btn-secondary" onClick={() => setRoute('download')}>
              View All Categories
              <ArrowRight size={16} />
            </button>
          </div>

          <div className="demands-grid">
            {sampleDemands.map((item, idx) => (
              <div key={idx} className="demand-card">
                <div className="demand-card-top">
                  <span className="demand-category">{item.category}</span>
                  <span className="demand-time">{item.time}</span>
                </div>
                <div className="demand-media-row">
                  <div className="demand-img-frame">
                    <img src={item.img} alt={item.title} />
                  </div>
                  <div className="demand-info">
                    <h4>{item.title}</h4>
                    <div className="demand-budget">{item.budget}</div>
                  </div>
                </div>
                <div className="demand-footer">
                  <div className="demand-loc">
                    <MapPin size={13} />
                    <span>{item.location}</span>
                  </div>
                  <div className="demand-offers-badge">
                    <Sparkles size={13} />
                    <span>{item.offersCount} offers received</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* =========================================================================
          SELLER SECTION: Corporate, Sleek Dark Navy Container
         ========================================================================= */}
      <section className="pro-section-dark">
        <div className="container">
          <div className="seller-editorial-grid">
            <div className="seller-left">
              <span className="eyebrow-light">For Local Businesses & Merchants</span>
              <h2 className="seller-dark-title">
                Stop paying for cold ads. <br />
                Target buyers who are ready right now.
              </h2>
              <p className="seller-dark-sub">
                Traditional advertising charges you whether a customer buys or not. On Hocalist, you review live customer requests with declared budgets, send custom offers, and keep 100% of your sales revenue.
              </p>

              <div className="seller-bullet-list">
                <div className="seller-bullet">
                  <div className="bullet-check"><CheckCircle2 size={18} /></div>
                  <div>
                    <h4>Zero Marketplace Commissions</h4>
                    <p>Item payments are finalized directly offline between you and the customer. Hocalist takes 0% cut of your merchandise price.</p>
                  </div>
                </div>

                <div className="seller-bullet">
                  <div className="bullet-check"><CheckCircle2 size={18} /></div>
                  <div>
                    <h4>Transparent FIFO HocaCredits</h4>
                    <p>Prepaid credit deposits ($20 or $40 batches) with permanently frozen rates. Winning fee is the total—pay only the remaining difference on deal win.</p>
                  </div>
                </div>

                <div className="seller-bullet">
                  <div className="bullet-check"><CheckCircle2 size={18} /></div>
                  <div>
                    <h4>Weekly Target Capacity</h4>
                    <p>Predictable monthly tiers: Free (10 weekly targets), Pro ($15/mo, 50 weekly targets), and Elite ($30/mo, 100 weekly targets).</p>
                  </div>
                </div>
              </div>

              <div className="seller-cta-row">
                <button className="btn btn-bright btn-lg" onClick={() => setRoute('pricing')}>
                  <span>Explore Seller Plans & Pricing</span>
                  <ArrowRight size={18} />
                </button>
                <button className="btn btn-dark-outline btn-lg" onClick={() => setRoute('billing')}>
                  <span>Seller Portal</span>
                </button>
              </div>
            </div>

            <div className="seller-right">
              <div className="seller-mockup-frame">
                <img
                  src="/assets/seller-home-card.png"
                  alt="Hocalist Seller Dashboard"
                  className="seller-mockup-img"
                />
                <div className="seller-mockup-floating-badge">
                  <span className="live-pulse" />
                  <span>Real-time local demand feed</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* =========================================================================
          FAQ ACCORDION: Clean, Organized, Direct
         ========================================================================= */}
      <section className="pro-section bg-subtle">
        <div className="container">
          <div className="section-head text-center">
            <span className="eyebrow">Clear Answers</span>
            <h2 className="section-h2">Frequently asked questions</h2>
            <p className="section-p">
              Everything you need to know about our reverse marketplace and offline payment model.
            </p>
          </div>

          <div className="pro-faq-wrap">
            {faqs.map((faq, idx) => {
              const isOpen = openFaq === idx;
              return (
                <div key={idx} className={`pro-faq-item ${isOpen ? 'open' : ''}`}>
                  <button
                    className="faq-toggle"
                    onClick={() => setOpenFaq(isOpen ? null : idx)}
                    aria-expanded={isOpen}
                  >
                    <span>{faq.q}</span>
                    <span className="faq-icon-pill">
                      {isOpen ? <ChevronUp size={18} /> : <ChevronDown size={18} />}
                    </span>
                  </button>
                  {isOpen && (
                    <div className="faq-content">
                      <p>{faq.a}</p>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* =========================================================================
          FINAL CORPORATE CTA BANNER
         ========================================================================= */}
      <section className="pro-final-cta">
        <div className="container text-center">
          <h2 className="final-title">Experience the future of local commerce.</h2>
          <p className="final-sub">
            Whether you want the best price on your next purchase or want to grow your local retail business, Hocalist gives you the advantage.
          </p>
          <div className="final-actions">
            <button className="btn btn-primary btn-lg" onClick={() => setRoute('download')}>
              <span>Join as a Buyer (Free)</span>
              <ArrowRight size={18} />
            </button>
            <button className="btn btn-outline btn-lg" onClick={() => setRoute('pricing')}>
              <span>View Seller Plans</span>
            </button>
          </div>
          <div className="final-disclaimer">
            <span>Item payments are arranged and settled directly offline upon in-person inspection.</span>
          </div>
        </div>
      </section>

      {/* =========================================================================
          STYLES: High-End Corporate Typography, Spacing, and Elevations
         ========================================================================= */}
      <style>{`
        .pro-home {
          font-family: var(--font-body);
          color: var(--text-primary);
          overflow-x: hidden;
        }

        /* Hero */
        .pro-hero {
          padding: 5rem 0 4rem;
          background: radial-gradient(circle at 50% 0%, #EEF2FF 0%, #FFFFFF 70%);
          text-align: center;
          position: relative;
        }
        .pro-hero-badge-wrap {
          display: flex;
          justify-content: center;
          margin-bottom: 1.5rem;
        }
        .pro-badge {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.4rem 1rem;
          border-radius: var(--radius-full);
          background: #FFFFFF;
          border: 1px solid rgba(0, 3, 108, 0.12);
          box-shadow: 0 2px 8px rgba(0, 3, 108, 0.04);
          font-size: 0.82rem;
          font-weight: 700;
          color: var(--hoca-navy);
          letter-spacing: 0.02em;
        }
        .live-pulse {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: var(--hoca-blue);
          box-shadow: 0 0 0 3px rgba(26, 40, 212, 0.25);
          animation: pulseGlow 2s infinite ease-in-out;
        }
        .pro-hero-title {
          font-size: 4rem;
          font-weight: 800;
          letter-spacing: -0.03em;
          line-height: 1.12;
          color: var(--hoca-navy-deep);
          margin-bottom: 1.5rem;
          max-width: 850px;
          margin-left: auto;
          margin-right: auto;
        }
        @media (max-width: 768px) {
          .pro-hero-title {
            font-size: 2.5rem;
          }
        }
        .text-gradient {
          background: linear-gradient(135deg, var(--hoca-navy) 0%, var(--hoca-blue-bright) 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
        }
        .pro-hero-sub {
          font-size: 1.2rem;
          line-height: 1.65;
          color: var(--text-secondary);
          max-width: 720px;
          margin: 0 auto 2.5rem;
        }
        @media (max-width: 768px) {
          .pro-hero-sub {
            font-size: 1rem;
          }
        }

        /* Search Box */
        .pro-search-box {
          max-width: 660px;
          margin: 0 auto 2rem;
          background: #FFFFFF;
          border: 1.5px solid var(--border-medium);
          border-radius: var(--radius-full);
          padding: 0.4rem 0.5rem 0.4rem 1.25rem;
          display: flex;
          align-items: center;
          gap: 0.75rem;
          box-shadow: 0 12px 32px rgba(0, 3, 108, 0.08);
          transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
        }
        .pro-search-box:focus-within {
          border-color: var(--hoca-navy);
          box-shadow: 0 16px 40px rgba(0, 3, 108, 0.14);
        }
        .search-input-wrap {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          flex: 1;
        }
        .search-icon {
          color: var(--text-muted);
          flex-shrink: 0;
        }
        .search-input-wrap input {
          width: 100%;
          border: none;
          outline: none;
          background: transparent;
          font-size: 0.95rem;
          color: var(--text-primary);
        }
        .btn-search {
          border-radius: var(--radius-full);
          padding: 0.7rem 1.4rem;
          font-size: 0.92rem;
          flex-shrink: 0;
        }

        /* Trust Bar */
        .pro-hero-trust-bar {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.85rem;
          font-size: 0.82rem;
          color: var(--text-secondary);
          margin-bottom: 4rem;
          flex-wrap: wrap;
        }
        .trust-pill {
          display: flex;
          align-items: center;
          gap: 0.35rem;
          font-weight: 600;
        }
        .text-success { color: #0D8249; }
        .text-navy { color: var(--hoca-navy); }
        .divider-dot { color: #CBD5E1; }

        /* Showcase Stage */
        .pro-hero-showcase {
          position: relative;
          max-width: 1100px;
          margin: 0 auto;
        }
        .showcase-glow {
          position: absolute;
          inset: 0;
          background: radial-gradient(circle at 50% 50%, rgba(37, 64, 255, 0.12) 0%, rgba(255, 255, 255, 0) 70%);
          pointer-events: none;
        }
        .showcase-stage {
          display: grid;
          grid-template-columns: 290px 1fr 290px;
          gap: 1.5rem;
          align-items: center;
          position: relative;
        }
        @media (max-width: 990px) {
          .showcase-stage {
            grid-template-columns: 1fr;
          }
        }
        .sc-card {
          background: #FFFFFF;
          border: 1px solid rgba(0, 3, 108, 0.1);
          border-radius: var(--radius-lg);
          padding: 1.25rem;
          box-shadow: 0 16px 36px rgba(0, 3, 108, 0.09);
          text-align: left;
        }
        .sc-card-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 0.75rem;
        }
        .sc-chip {
          font-size: 0.68rem;
          font-weight: 700;
          padding: 0.2rem 0.55rem;
          border-radius: var(--radius-full);
          text-transform: uppercase;
          letter-spacing: 0.03em;
        }
        .sc-chip.navy { background: var(--hoca-blue-tint); color: var(--hoca-navy); }
        .sc-chip.green { background: #DCFCE7; color: #15803D; }
        .sc-time {
          font-size: 0.72rem;
          color: var(--text-muted);
          display: flex;
          align-items: center;
          gap: 0.25rem;
        }
        .sc-item-row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          margin-bottom: 0.75rem;
        }
        .sc-thumb {
          width: 42px;
          height: 42px;
          object-fit: contain;
          background: #F8FAFC;
          border-radius: var(--radius-sm);
          padding: 2px;
          border: 1px solid var(--border-subtle);
        }
        .sc-item-row h4 {
          font-size: 0.88rem;
          font-weight: 700;
          color: var(--hoca-navy);
          line-height: 1.3;
        }
        .sc-meta-sub {
          display: block;
          font-size: 0.72rem;
          color: var(--text-muted);
        }
        .sc-tags {
          display: flex;
          gap: 0.35rem;
          flex-wrap: wrap;
        }
        .sc-tag {
          font-size: 0.7rem;
          background: #F1F5F9;
          color: var(--text-secondary);
          padding: 0.2rem 0.5rem;
          border-radius: 4px;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: 0.2rem;
        }

        /* Center Showcase Frame */
        .sc-center-hero-frame {
          height: 380px;
          border-radius: var(--radius-xl);
          overflow: hidden;
          position: relative;
          box-shadow: 0 24px 50px rgba(0, 3, 108, 0.18);
          border: 1px solid rgba(0, 3, 108, 0.15);
          background: #00036C;
        }
        .sc-hero-img {
          width: 100%;
          height: 100%;
          object-fit: cover;
          object-position: center top;
        }
        .sc-hero-glass-bar {
          position: absolute;
          bottom: 14px;
          left: 14px;
          right: 14px;
          background: rgba(0, 2, 66, 0.82);
          backdrop-filter: blur(12px);
          padding: 0.75rem 1rem;
          border-radius: var(--radius-md);
          display: flex;
          align-items: center;
          justify-content: space-between;
          border: 1px solid rgba(255, 255, 255, 0.18);
          color: white;
          text-align: left;
        }
        .merchant-info {
          display: flex;
          align-items: center;
          gap: 0.65rem;
        }
        .m-avatar {
          width: 34px;
          height: 34px;
          border-radius: 50%;
        }
        .merchant-info strong {
          display: block;
          font-size: 0.85rem;
        }
        .merchant-info span {
          display: block;
          font-size: 0.72rem;
          color: #93C5FD;
        }
        .merchant-bid {
          text-align: right;
        }
        .bid-label {
          display: block;
          font-size: 0.65rem;
          text-transform: uppercase;
          color: #93C5FD;
          font-weight: 700;
        }
        .bid-amount {
          font-size: 1.25rem;
          font-weight: 800;
          color: #38BDF8;
        }

        /* Right Card Meetup */
        .sc-meet-box {
          background: #F8FAFC;
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-sm);
          padding: 0.65rem;
          margin-bottom: 0.75rem;
        }
        .sc-meet-title {
          display: flex;
          align-items: center;
          gap: 0.35rem;
          font-size: 0.78rem;
          font-weight: 700;
          color: var(--hoca-navy);
          margin-bottom: 0.25rem;
        }
        .sc-meet-note {
          font-size: 0.72rem;
          color: var(--text-secondary);
          line-height: 1.4;
        }
        .sc-pin-strip {
          background: #00036C;
          color: white;
          padding: 0.65rem;
          border-radius: var(--radius-sm);
          text-align: center;
        }
        .pin-label {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.3rem;
          font-size: 0.68rem;
          text-transform: uppercase;
          color: #93C5FD;
          margin-bottom: 0.25rem;
          font-weight: 700;
        }
        .pin-numbers {
          display: block;
          font-family: monospace;
          font-size: 1.15rem;
          font-weight: 800;
          letter-spacing: 0.2em;
          color: #38BDF8;
        }
        .pin-rule {
          display: block;
          font-size: 0.62rem;
          color: #CBD5E1;
          margin-top: 0.2rem;
        }

        /* Sections General */
        .pro-section {
          padding: 6rem 0;
        }
        .pro-section.bg-subtle {
          background: #F8FAFC;
          border-top: 1px solid var(--border-subtle);
          border-bottom: 1px solid var(--border-subtle);
        }
        .section-head {
          max-width: 680px;
          margin: 0 auto 3.5rem;
        }
        .eyebrow {
          font-size: 0.8rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--hoca-blue);
          margin-bottom: 0.5rem;
          display: block;
        }
        .section-h2 {
          font-size: 2.6rem;
          font-weight: 800;
          letter-spacing: -0.025em;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.75rem;
          line-height: 1.2;
        }
        @media (max-width: 768px) {
          .section-h2 {
            font-size: 2rem;
          }
        }
        .section-p {
          font-size: 1.05rem;
          line-height: 1.6;
          color: var(--text-secondary);
        }

        /* Three Pillars */
        .three-pillars-grid {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 2rem;
        }
        @media (max-width: 860px) {
          .three-pillars-grid {
            grid-template-columns: 1fr;
          }
        }
        .pillar-card {
          background: #FFFFFF;
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-xl);
          padding: 2.5rem 2rem;
          box-shadow: 0 4px 16px rgba(0, 3, 108, 0.04);
          position: relative;
          transition: transform var(--transition-normal), box-shadow var(--transition-normal);
        }
        .pillar-card:hover {
          transform: translateY(-4px);
          box-shadow: 0 16px 36px rgba(0, 3, 108, 0.1);
        }
        .pillar-num {
          font-family: var(--font-heading);
          font-size: 3rem;
          font-weight: 900;
          color: #E2E8F0;
          line-height: 1;
          margin-bottom: 1rem;
        }
        .pillar-icon-box {
          width: 52px;
          height: 52px;
          border-radius: var(--radius-md);
          background: var(--hoca-blue-tint);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 1.25rem;
        }
        .pillar-title {
          font-size: 1.35rem;
          font-weight: 700;
          color: var(--hoca-navy-deep);
          margin-bottom: 0.75rem;
        }
        .pillar-desc {
          font-size: 0.95rem;
          line-height: 1.6;
          color: var(--text-secondary);
          margin-bottom: 1.5rem;
        }
        .pillar-footer-tip {
          font-size: 0.8rem;
          font-weight: 700;
          color: var(--hoca-blue);
          border-top: 1px solid var(--border-subtle);
          padding-top: 1rem;
        }

        /* Demand Grid */
        .section-head-split {
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          margin-bottom: 3rem;
          gap: 2rem;
        }
        @media (max-width: 768px) {
          .section-head-split {
            flex-direction: column;
            align-items: flex-start;
          }
        }
        .demands-grid {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 1.5rem;
        }
        @media (max-width: 1024px) {
          .demands-grid {
            grid-template-columns: repeat(2, 1fr);
          }
        }
        @media (max-width: 600px) {
          .demands-grid {
            grid-template-columns: 1fr;
          }
        }
        .demand-card {
          background: #FFFFFF;
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-lg);
          padding: 1.25rem;
          box-shadow: 0 4px 12px rgba(0, 3, 108, 0.03);
          transition: transform var(--transition-normal), box-shadow var(--transition-normal);
        }
        .demand-card:hover {
          transform: translateY(-3px);
          box-shadow: 0 12px 28px rgba(0, 3, 108, 0.08);
          border-color: rgba(0, 3, 108, 0.2);
        }
        .demand-card-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 0.75rem;
        }
        .demand-category {
          font-size: 0.72rem;
          font-weight: 700;
          text-transform: uppercase;
          color: var(--text-muted);
          letter-spacing: 0.04em;
        }
        .demand-time {
          font-size: 0.72rem;
          color: var(--text-subtle);
        }
        .demand-media-row {
          display: flex;
          align-items: center;
          gap: 0.85rem;
          margin-bottom: 1rem;
        }
        .demand-img-frame {
          width: 56px;
          height: 56px;
          background: #F1F5F9;
          border-radius: var(--radius-md);
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 4px;
          flex-shrink: 0;
        }
        .demand-img-frame img {
          max-width: 100%;
          max-height: 100%;
          object-fit: contain;
        }
        .demand-info h4 {
          font-size: 0.95rem;
          font-weight: 700;
          color: var(--hoca-navy-deep);
          line-height: 1.35;
          margin-bottom: 0.25rem;
        }
        .demand-budget {
          font-size: 0.95rem;
          font-weight: 800;
          color: var(--hoca-blue);
        }
        .demand-footer {
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 0.75rem;
          border-top: 1px solid var(--border-subtle);
          padding-top: 0.75rem;
        }
        .demand-loc {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          color: var(--text-muted);
        }
        .demand-offers-badge {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          color: #0D8249;
          font-weight: 600;
        }

        /* Seller Dark Section */
        .pro-section-dark {
          background: var(--hoca-navy-deep);
          color: white;
          padding: 6rem 0;
        }
        .seller-editorial-grid {
          display: grid;
          grid-template-columns: 1.15fr 0.85fr;
          gap: 4rem;
          align-items: center;
        }
        @media (max-width: 960px) {
          .seller-editorial-grid {
            grid-template-columns: 1fr;
          }
        }
        .eyebrow-light {
          font-size: 0.8rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: #93C5FD;
          margin-bottom: 0.75rem;
          display: block;
        }
        .seller-dark-title {
          font-size: 2.8rem;
          font-weight: 800;
          line-height: 1.15;
          letter-spacing: -0.025em;
          color: white;
          margin-bottom: 1.25rem;
        }
        @media (max-width: 768px) {
          .seller-dark-title {
            font-size: 2rem;
          }
        }
        .seller-dark-sub {
          font-size: 1.1rem;
          line-height: 1.65;
          color: #CBD5E1;
          margin-bottom: 2.5rem;
        }
        .seller-bullet-list {
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
          margin-bottom: 2.5rem;
        }
        .seller-bullet {
          display: flex;
          align-items: flex-start;
          gap: 0.85rem;
        }
        .bullet-check {
          color: #38BDF8;
          flex-shrink: 0;
          margin-top: 0.2rem;
        }
        .seller-bullet h4 {
          font-size: 1.05rem;
          font-weight: 700;
          color: white;
          margin-bottom: 0.25rem;
        }
        .seller-bullet p {
          font-size: 0.88rem;
          line-height: 1.5;
          color: #94A3B8;
        }
        .seller-cta-row {
          display: flex;
          align-items: center;
          gap: 1rem;
          flex-wrap: wrap;
        }
        .btn-bright {
          background: #2540FF;
          color: white;
          border-radius: var(--radius-md);
        }
        .btn-bright:hover {
          background: #1A28D4;
        }
        .btn-dark-outline {
          background: transparent;
          border: 1px solid rgba(255, 255, 255, 0.3);
          color: white;
          border-radius: var(--radius-md);
        }
        .btn-dark-outline:hover {
          background: rgba(255, 255, 255, 0.08);
        }
        .seller-mockup-frame {
          border-radius: var(--radius-xl);
          background: #0A0F3D;
          border: 1px solid rgba(255, 255, 255, 0.15);
          padding: 1.25rem;
          box-shadow: 0 24px 60px rgba(0, 0, 0, 0.4);
          position: relative;
        }
        .seller-mockup-img {
          width: 100%;
          height: auto;
          border-radius: var(--radius-lg);
          display: block;
        }
        .seller-mockup-floating-badge {
          position: absolute;
          bottom: 24px;
          left: 24px;
          background: rgba(0, 2, 66, 0.85);
          backdrop-filter: blur(8px);
          padding: 0.45rem 0.85rem;
          border-radius: var(--radius-full);
          border: 1px solid rgba(255, 255, 255, 0.2);
          display: flex;
          align-items: center;
          gap: 0.45rem;
          font-size: 0.75rem;
          font-weight: 600;
          color: white;
        }

        /* FAQ */
        .pro-faq-wrap {
          max-width: 800px;
          margin: 0 auto;
          display: flex;
          flex-direction: column;
          gap: 0.85rem;
        }
        .pro-faq-item {
          background: #FFFFFF;
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-lg);
          overflow: hidden;
          transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
        }
        .pro-faq-item.open {
          border-color: var(--hoca-navy);
          box-shadow: 0 4px 16px rgba(0, 3, 108, 0.06);
        }
        .faq-toggle {
          width: 100%;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 1.4rem 1.75rem;
          background: transparent;
          font-size: 1.05rem;
          font-weight: 700;
          color: var(--hoca-navy-deep);
          text-align: left;
        }
        .faq-icon-pill {
          width: 32px;
          height: 32px;
          border-radius: 50%;
          background: #F1F5F9;
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--hoca-navy);
          flex-shrink: 0;
        }
        .faq-content {
          padding: 0 1.75rem 1.4rem;
          font-size: 0.95rem;
          line-height: 1.65;
          color: var(--text-secondary);
          border-top: 1px solid #F1F5F9;
          padding-top: 1rem;
        }

        /* Final CTA */
        .pro-final-cta {
          padding: 6rem 0;
          background: radial-gradient(circle at 50% 100%, #EEF2FF 0%, #FFFFFF 80%);
        }
        .final-title {
          font-size: 2.8rem;
          font-weight: 800;
          letter-spacing: -0.025em;
          color: var(--hoca-navy-deep);
          margin-bottom: 1rem;
        }
        @media (max-width: 768px) {
          .final-title {
            font-size: 2rem;
          }
        }
        .final-sub {
          font-size: 1.15rem;
          line-height: 1.6;
          color: var(--text-secondary);
          max-width: 640px;
          margin: 0 auto 2.5rem;
        }
        .final-actions {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 1rem;
          margin-bottom: 2rem;
          flex-wrap: wrap;
        }
        .final-disclaimer {
          font-size: 0.8rem;
          color: var(--text-muted);
        }
      `}</style>
    </div>
  );
};
