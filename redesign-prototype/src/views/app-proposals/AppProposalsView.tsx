import React, { useState } from 'react';
import {
  AppProposalSurface,
  ViewportMode,
  TextScale,
  SurfaceState,
  APP_PROPOSALS
} from '../../types';
import {
  MapPin,
  Shield,
  Lock,
  DollarSign,
  Zap,
  ArrowRight,
  RotateCcw,
  CheckCircle2,
  AlertTriangle,
  Upload,
  Camera,
  Store,
  ChevronRight,
  Clock,
  ExternalLink,
  Info,
  Calendar,
  KeyRound,
  FileText,
  UserCheck,
  AlertCircle
} from 'lucide-react';

interface AppProposalsViewProps {
  currentSurface: AppProposalSurface;
  setSurface: (s: AppProposalSurface) => void;
  viewport: ViewportMode;
  setViewport: (v: ViewportMode) => void;
  textScale: TextScale;
  setTextScale: (t: TextScale) => void;
  surfaceState: SurfaceState;
  setSurfaceState: (s: SurfaceState) => void;
}

export const AppProposalsView: React.FC<AppProposalsViewProps> = ({
  currentSurface,
  setSurface,
  viewport,
  setViewport,
  textScale,
  setTextScale,
  surfaceState,
  setSurfaceState
}) => {
  // Device frame width mapping
  const deviceWidthMap: Record<ViewportMode, string> = {
    'desktop': '430px',
    'tablet': '430px',
    'mobile-430': '430px',
    'mobile-390': '390px',
    'mobile-360': '360px',
    'mobile-320': '320px'
  };

  const currentWidth = deviceWidthMap[viewport] || '390px';
  const scaleMultiplier = parseFloat(textScale);

  const meta = APP_PROPOSALS.find((p) => p.id === currentSurface) || APP_PROPOSALS[0];

  return (
    <div className="proposals-wrapper">
      {/* Intro Bar */}
      <div className="proposals-top-info">
        <div className="container">
          <div className="info-flex">
            <div>
              <div className="badge-row">
                <span className="badge badge-navy">App Supplemental Proposal</span>
                <span className="badge badge-neutral">Role: {meta.category}</span>
                <span className="badge badge-warning">State: {surfaceState.toUpperCase()}</span>
              </div>
              <h2 className="proposal-title">{meta.title}</h2>
              <p className="proposal-desc">{meta.description}</p>
            </div>

            {/* Quick Surface Switcher Bar */}
            <div className="surface-pill-selector">
              {APP_PROPOSALS.map((s) => (
                <button
                  key={s.id}
                  className={`surface-btn ${currentSurface === s.id ? 'active' : ''}`}
                  onClick={() => setSurface(s.id)}
                >
                  {s.title.split(' ')[0]}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Main Interactive Mobile Simulator */}
      <div className="device-stage">
        <div
          className="phone-mockup"
          style={{
            width: currentWidth,
            fontSize: `${scaleMultiplier * 14}px`
          }}
        >
          {/* Phone Hardware Bar & Dynamic Island */}
          <div className="phone-top-notch">
            <div className="phone-time">9:41</div>
            <div className="dynamic-island" />
            <div className="phone-icons">
              <span className="icon-sig">📶</span>
              <span className="icon-wifi">􀙇</span>
              <span className="icon-bat">🔋</span>
            </div>
          </div>

          {/* App Header */}
          <div className="app-nav-header">
            <span className="app-header-title">{meta.title}</span>
            <div className="app-header-meta">
              <span>{currentWidth} • {textScale}x</span>
            </div>
          </div>

          {/* App Content Scrollable Area */}
          <div className="app-screen-body">
            {/* RENDER ACTIVE PROPOSAL SURFACE BASED ON STATE */}
            {renderSurfaceContent(currentSurface, surfaceState, scaleMultiplier)}
          </div>

          {/* Phone Bottom Home Indicator */}
          <div className="phone-bottom-bar">
            <div className="home-pill" />
          </div>
        </div>
      </div>

      <style>{`
        .proposals-wrapper {
          background: #0B112C;
          min-height: calc(100vh - 120px);
          display: flex;
          flex-direction: column;
        }
        .proposals-top-info {
          background: #0F173D;
          border-bottom: 1px solid #1E2958;
          padding: 1.5rem 0;
          color: white;
        }
        .info-flex {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 2rem;
          flex-wrap: wrap;
        }
        .badge-row {
          display: flex;
          gap: 0.5rem;
          margin-bottom: 0.5rem;
        }
        .proposal-title {
          font-size: 1.6rem;
          color: #FFFFFF;
          margin-bottom: 0.25rem;
        }
        .proposal-desc {
          font-size: 0.88rem;
          color: #94A3B8;
          max-width: 580px;
        }
        .surface-pill-selector {
          display: flex;
          flex-wrap: wrap;
          gap: 0.4rem;
          max-width: 550px;
        }
        .surface-btn {
          background: rgba(255, 255, 255, 0.08);
          border: 1px solid rgba(255, 255, 255, 0.12);
          color: #CBD5E1;
          padding: 0.35rem 0.65rem;
          border-radius: var(--radius-sm);
          font-size: 0.78rem;
          font-weight: 600;
          transition: all 0.15s;
        }
        .surface-btn:hover {
          background: rgba(255, 255, 255, 0.16);
          color: white;
        }
        .surface-btn.active {
          background: var(--hoca-navy);
          border-color: #2540FF;
          color: white;
        }

        /* Device Stage */
        .device-stage {
          flex: 1;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 3rem 1.5rem;
          background: radial-gradient(circle at 50% 30%, #151D4D 0%, #080D24 100%);
        }
        .phone-mockup {
          background: #F8FAFC;
          border-radius: 46px;
          box-shadow: 0 25px 60px -10px rgba(0, 0, 0, 0.6), 0 0 0 10px #1E293B, 0 0 0 12px #334155;
          height: 844px;
          display: flex;
          flex-direction: column;
          overflow: hidden;
          position: relative;
          transition: width 0.3s cubic-bezier(0.16, 1, 0.3, 1);
        }
        .phone-top-notch {
          height: 44px;
          background: #00036C;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0 1.25rem;
          color: white;
          font-size: 0.8rem;
          font-weight: 700;
        }
        .dynamic-island {
          width: 90px;
          height: 22px;
          background: #000;
          border-radius: 20px;
        }
        .app-nav-header {
          background: #00036C;
          color: white;
          padding: 0.5rem 1rem 0.85rem;
          border-bottom: 1px solid rgba(255, 255, 255, 0.1);
          display: flex;
          align-items: baseline;
          justify-content: space-between;
        }
        .app-header-title {
          font-size: 1.05rem;
          font-weight: 700;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .app-header-meta {
          font-size: 0.72rem;
          color: #93C5FD;
        }
        .app-screen-body {
          flex: 1;
          overflow-y: auto;
          background: #FFFFFF;
          padding: 1rem;
          display: flex;
          flex-direction: column;
        }
        .phone-bottom-bar {
          height: 28px;
          background: #FFFFFF;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .home-pill {
          width: 120px;
          height: 4px;
          background: #94A3B8;
          border-radius: 2px;
        }

        /* Reusable Proposal Surface Components */
        .app-card {
          background: #FFFFFF;
          border: 1px solid #E2E8F0;
          border-radius: 12px;
          padding: 1rem;
          margin-bottom: 0.85rem;
          box-shadow: 0 1px 3px rgba(0, 3, 108, 0.04);
        }
        .app-card h4 {
          font-size: 1rem;
          color: #00036C;
          margin-bottom: 0.35rem;
        }
        .app-card p {
          font-size: 0.85rem;
          line-height: 1.45;
          color: #475569;
        }
        .app-badge-row {
          display: flex;
          gap: 0.35rem;
          margin-bottom: 0.5rem;
          flex-wrap: wrap;
        }
        .app-btn {
          width: 100%;
          padding: 0.7rem;
          border-radius: 8px;
          font-weight: 700;
          font-size: 0.88rem;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.4rem;
          cursor: pointer;
        }
        .app-btn-primary {
          background: #00036C;
          color: white;
        }
        .app-btn-secondary {
          background: #EEF2FF;
          color: #00036C;
          border: 1px solid rgba(0, 3, 108, 0.15);
        }
        .skeleton-block {
          background: linear-gradient(90deg, #F1F5F9 25%, #E2E8F0 50%, #F1F5F9 75%);
          background-size: 200% 100%;
          animation: shimmer 1.5s infinite;
          border-radius: 6px;
        }
        @keyframes shimmer {
          0% { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
        .empty-app-state {
          padding: 2.5rem 1rem;
          text-align: center;
        }
        .empty-app-icon {
          width: 52px;
          height: 52px;
          border-radius: 50%;
          background: #EEF2FF;
          color: #00036C;
          display: flex;
          align-items: center;
          justify-content: center;
          margin: 0 auto 0.75rem;
        }
        .empty-app-title {
          font-size: 1.05rem;
          font-weight: 700;
          color: #00036C;
          margin-bottom: 0.3rem;
        }
        .empty-app-desc {
          font-size: 0.82rem;
          color: #64748B;
          line-height: 1.45;
          margin-bottom: 1.25rem;
        }
        .app-notice {
          background: #F8FAFC;
          border-left: 3px solid #00036C;
          padding: 0.65rem 0.85rem;
          border-radius: 4px;
          font-size: 0.78rem;
          color: #334155;
          display: flex;
          gap: 0.5rem;
          margin-bottom: 0.85rem;
        }
      `}</style>
    </div>
  );
};

// =========================================================================
// RENDER INDIVIDUAL APP PROPOSAL SURFACES
// =========================================================================
function renderSurfaceContent(surface: AppProposalSurface, state: SurfaceState, scale: number) {
  // If loading state requested, render role-accurate skeleton loader
  if (state === 'loading') {
    return (
      <div className="skeleton-container">
        <div className="skeleton-block" style={{ height: '38px', marginBottom: '12px' }} />
        <div className="skeleton-block" style={{ height: '140px', marginBottom: '12px' }} />
        <div className="skeleton-block" style={{ height: '90px', marginBottom: '12px' }} />
        <div className="skeleton-block" style={{ height: '50px' }} />
        <p className="text-center mt-3 text-sm text-muted">Retrieving authoritative server records…</p>
      </div>
    );
  }

  // If error state requested, render role-accurate error notification
  if (state === 'error') {
    return (
      <div className="empty-app-state">
        <div className="empty-app-icon" style={{ background: '#FEE2E2', color: '#B91C1C' }}>
          <RotateCcw size={26} />
        </div>
        <div className="empty-app-title">Connection Interrupted</div>
        <p className="empty-app-desc">
          Unable to synchronize with Hocalist Supabase schema. Your local state is preserved.
        </p>
        <button className="app-btn app-btn-primary">
          <RotateCcw size={14} /> Retry Authorization
        </button>
      </div>
    );
  }

  // Surface 1: Location / Map / Directions Sheet
  if (surface === 'location-map') {
    if (state === 'empty') {
      return (
        <div className="empty-app-state">
          <div className="empty-app-icon"><MapPin size={24} /></div>
          <div className="empty-app-title">No Meeting Location Set</div>
          <p className="empty-app-desc">Choose a public place or safe exchange zone to schedule meetup.</p>
          <button className="app-btn app-btn-primary">Search Public Location</button>
        </div>
      );
    }
    return (
      <div>
        <div className="app-notice">
          <Shield size={14} />
          <span><strong>Privacy Guard:</strong> Exact private coordinates are kept confidential. Sellers see city and distance radius only.</span>
        </div>

        <div className="app-card">
          <h4>Search Safe Meetup Spot</h4>
          <input
            type="text"
            defaultValue="Starbucks • 150 N Michigan Ave, Chicago"
            style={{ width: '100%', padding: '8px 10px', border: '1px solid #CBD5E1', borderRadius: '6px', fontSize: '0.88rem', marginBottom: '8px' }}
          />
          <span className="badge badge-success">US-First Region Matched</span>
        </div>

        {/* Map Simulation Tile */}
        <div className="app-card" style={{ padding: '0', overflow: 'hidden' }}>
          <div style={{ height: '150px', background: '#E2E8F0', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
            <MapPin size={32} color="#00036C" />
            <span style={{ fontSize: '0.8rem', color: '#475569', fontWeight: 600 }}>Map Preview Radius: 3.5 miles</span>
          </div>
          <div style={{ padding: '12px' }}>
            <strong>Selected Zone: Downtown / Loop</strong>
            <p style={{ fontSize: '0.8rem', color: '#64748B', marginTop: '4px' }}>Public cafe, high foot traffic, daylight hours recommended.</p>
          </div>
        </div>

        <div className="app-card">
          <h4>Suggested Safe Exchange Zones</h4>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '6px' }}>
            <div style={{ padding: '8px', background: '#F8FAFC', borderRadius: '6px', fontSize: '0.82rem' }}>
              🏛️ <strong>1st District Police Station</strong> (Public Lobby) • 0.8 mi
            </div>
            <div style={{ padding: '8px', background: '#F8FAFC', borderRadius: '6px', fontSize: '0.82rem' }}>
              ☕ <strong>Corner Bakery Cafe</strong> • 0.4 mi
            </div>
          </div>
        </div>

        <button className="app-btn app-btn-primary">Confirm Meetup Spot</button>
      </div>
    );
  }

  // Surface 2: Seller Account Health & Policy
  if (surface === 'account-health') {
    return (
      <div>
        <div className="app-card">
          <div className="app-badge-row">
            <span className="badge badge-success">Account Health: Normal</span>
            <span className="badge badge-navy">Review Window: 30 Days</span>
          </div>
          <h4>Factual Seller Standing</h4>
          <p>
            Hocalist does NOT use arbitrary colored scorebars. Account standing is evaluated by verified meeting attendance, dispute frequency, and policy compliance.
          </p>
        </div>

        <div className="app-card">
          <h4>Health Indicators</h4>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px', fontSize: '0.85rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Completed Deals (PIN Validated):</span>
              <strong>14 deals</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>On-Time Meeting Rate:</span>
              <strong style={{ color: '#15803D' }}>98.2%</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Unresolved Buyer Reports:</span>
              <strong>0 reports</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Dispute / Appeal Status:</span>
              <span className="badge badge-neutral">No active flags</span>
            </div>
          </div>
        </div>

        <div className="app-notice">
          <Info size={14} />
          <span>Single reports enter human review queue; one allegation never imposes an automatic penalty.</span>
        </div>

        <button className="app-btn app-btn-secondary">View Policy & Appeal Workflow</button>
      </div>
    );
  }

  // Surface 3: Account Security, Recovery & Auth Gate
  if (surface === 'account-security-recovery') {
    return (
      <div>
        <div className="app-card">
          <h4>Account Identity & Role Gate</h4>
          <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
            <button className="app-btn app-btn-primary" style={{ padding: '6px' }}>Buyer Mode</button>
            <button className="app-btn app-btn-secondary" style={{ padding: '6px' }}>Seller Mode</button>
          </div>
        </div>

        <div className="app-card">
          <h4>Security Verification</h4>
          <div style={{ fontSize: '0.85rem', display: 'flex', flexDirection: 'column', gap: '8px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <strong>Two-Factor SMS OTP</strong>
                <div style={{ fontSize: '0.75rem', color: '#64748B' }}>Verified to +1 (312) •••-8492</div>
              </div>
              <span className="badge badge-success">Active</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <strong>Linked Email</strong>
                <div style={{ fontSize: '0.75rem', color: '#64748B' }}>member@example.com</div>
              </div>
              <span className="badge badge-navy">Confirmed</span>
            </div>
          </div>
        </div>

        <div className="app-card">
          <h4>Session Management</h4>
          <p style={{ fontSize: '0.82rem', marginBottom: '8px' }}>Logged in on 1 active Android phone device.</p>
          <button className="app-btn app-btn-secondary" style={{ fontSize: '0.8rem' }}>Revoke Other Sessions</button>
        </div>

        <button className="app-btn app-btn-primary" style={{ background: '#B91C1C' }}>Request Account Deletion</button>
      </div>
    );
  }

  // Surface 4: Buyer Rewards Ledger & Detail
  if (surface === 'rewards-ledger') {
    if (state === 'empty') {
      return (
        <div className="empty-app-state">
          <div className="empty-app-icon"><DollarSign size={24} /></div>
          <div className="empty-app-title">No Rewards Earned Yet</div>
          <p className="empty-app-desc">Complete your first PIN-verified transaction to earn cash rewards!</p>
          <button className="app-btn app-btn-primary">Browse Open Requests</button>
        </div>
      );
    }
    return (
      <div>
        <div className="app-card" style={{ background: '#00036C', color: 'white' }}>
          <span style={{ fontSize: '0.75rem', opacity: 0.8 }}>Withdrawable Earned Balance</span>
          <div style={{ fontSize: '2rem', fontWeight: 800 }}>$24.50 <small style={{ fontSize: '0.9rem' }}>USD</small></div>
          <span className="badge badge-success mt-2">Threshold Met (Min $20.00)</span>
        </div>

        <div className="app-card">
          <h4>Reward Accounting Ledger</h4>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', fontSize: '0.82rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid #F1F5F9' }}>
              <div>
                <strong>iPad Air Purchase (#REQ-842)</strong>
                <div style={{ color: '#64748B' }}>Regular PIN completion</div>
              </div>
              <strong style={{ color: '#15803D' }}>+$0.15</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid #F1F5F9' }}>
              <div>
                <strong>PS5 Deal Finalized (#REQ-710)</strong>
                <div style={{ color: '#64748B' }}>Late-window completion reward</div>
              </div>
              <strong style={{ color: '#15803D' }}>+$0.30</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0' }}>
              <div>
                <strong>Community Referral Bonus</strong>
                <div style={{ color: '#64748B' }}>Approved merchant onboarding</div>
              </div>
              <strong style={{ color: '#15803D' }}>+$24.05</strong>
            </div>
          </div>
        </div>

        <button className="app-btn app-btn-primary">Request Cash Withdrawal ($24.50)</button>
      </div>
    );
  }

  // Surface 5: Seller Credit Wallet & FIFO Batches
  if (surface === 'credit-wallet') {
    if (state === 'empty') {
      return (
        <div className="empty-app-state">
          <div className="empty-app-icon"><Zap size={24} /></div>
          <div className="empty-app-title">Zero HocaCredits</div>
          <p className="empty-app-desc">Deposit a $20 or $40 batch to begin sending competitive offers.</p>
          <button className="app-btn app-btn-primary">Make First Deposit</button>
        </div>
      );
    }
    return (
      <div>
        <div className="app-card" style={{ background: '#00036C', color: 'white' }}>
          <span style={{ fontSize: '0.75rem', opacity: 0.8 }}>Available HocaCredits</span>
          <div style={{ fontSize: '2rem', fontWeight: 800 }}>38.55 <small style={{ fontSize: '0.9rem' }}>HC</small></div>
          <div style={{ display: 'flex', gap: '8px', marginTop: '6px', fontSize: '0.78rem' }}>
            <span>Reserved: <strong>3.75 HC</strong></span>
            <span>•</span>
            <span>Target Quota: <strong>12 / 50</strong></span>
          </div>
        </div>

        <div className="app-card">
          <h4>FIFO Deposit Batches</h4>
          <div style={{ padding: '8px', background: '#F8FAFC', borderRadius: '6px', marginBottom: '8px', fontSize: '0.82rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <strong>BATCH-A ($40 Deposit)</strong>
              <span className="badge badge-success">Primary FIFO</span>
            </div>
            <div style={{ color: '#475569', marginTop: '4px' }}>
              Remaining: <strong>28.55 HC</strong> @ 1.45/3.25 rates
            </div>
          </div>
          <div style={{ padding: '8px', background: '#F8FAFC', borderRadius: '6px', fontSize: '0.82rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <strong>BATCH-B ($20 Deposit)</strong>
              <span className="badge badge-neutral">Secondary</span>
            </div>
            <div style={{ color: '#475569', marginTop: '4px' }}>
              Remaining: <strong>10.00 HC</strong> @ 1.55/3.75 rates
            </div>
          </div>
        </div>

        <div className="app-notice">
          <Shield size={14} />
          <span>Winning fee deducts only the difference upon PIN validation. Rates never mix on a single lead.</span>
        </div>

        <button className="app-btn app-btn-primary">Deposit Credit Batch on Website</button>
      </div>
    );
  }

  // Surface 6: Buyer Cash Withdrawals Flow
  if (surface === 'withdrawals') {
    return (
      <div>
        <div className="app-card">
          <h4>Withdrawal Eligibility Check</h4>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', fontSize: '0.82rem', marginTop: '6px' }}>
            <div>✓ Balance ($24.50) ≥ $20.00 Minimum: <strong>Passed</strong></div>
            <div>✓ Verified Mobile Phone: <strong>Confirmed</strong></div>
            <div>✓ Verified Email Address: <strong>Confirmed</strong></div>
          </div>
        </div>

        <div className="app-card">
          <h4>Net Payout Calculation</h4>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', fontSize: '0.85rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Gross Earned Balance:</span>
              <span>$24.50</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Processing Deduction:</span>
              <span style={{ color: '#B91C1C' }}>-$2.50</span>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px solid #E2E8F0', paddingTop: '6px', fontWeight: 700 }}>
              <span>Net Payout to Bank:</span>
              <span style={{ color: '#15803D' }}>$22.00 USD</span>
            </div>
          </div>
        </div>

        <button className="app-btn app-btn-primary">Confirm Payout of $22.00</button>
      </div>
    );
  }

  // Surface 7: Verified Sale History & Purchase Outcomes
  if (surface === 'sale-history') {
    return (
      <div>
        <div className="app-card">
          <div className="app-badge-row">
            <span className="badge badge-success">Completed & Validated</span>
            <span className="badge badge-navy">Deal #DL-4820</span>
          </div>
          <h4>Apple iPad Air 5th Gen (64GB)</h4>
          <p style={{ fontSize: '0.82rem', color: '#64748B' }}>Completed Oct 2, 2026 with Northside Tech Hub</p>

          <div style={{ padding: '8px', background: '#F8FAFC', borderRadius: '6px', marginTop: '8px', fontSize: '0.82rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span>Agreed Item Price:</span>
              <strong>$365.00 (Paid Offline)</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '4px' }}>
              <span>Validated PIN:</span>
              <code>• • • 0 5</code>
            </div>
          </div>
        </div>

        <div className="app-card">
          <h4>Leave Merchant Review</h4>
          <p style={{ fontSize: '0.82rem', color: '#64748B', marginBottom: '8px' }}>One review allowed per verified transaction.</p>
          <div style={{ fontSize: '1.2rem', marginBottom: '8px' }}>⭐️ ⭐️ ⭐️ ⭐️ ⭐️</div>
          <button className="app-btn app-btn-secondary" style={{ fontSize: '0.8rem' }}>Write 5-Star Review</button>
        </div>

        <button className="app-btn app-btn-secondary">Download Transaction Summary</button>
      </div>
    );
  }

  // Surface 8: Support Case Filing & Issue Reporting
  if (surface === 'support-reporting') {
    return (
      <div>
        <div className="app-card">
          <h4>Report an Incident or Transaction Issue</h4>
          <p style={{ fontSize: '0.82rem', color: '#64748B', marginBottom: '8px' }}>
            Attached to Deal #DL-4820 with Northside Tech Hub.
          </p>

          <label style={{ fontSize: '0.78rem', fontWeight: 700, display: 'block', marginBottom: '4px' }}>Issue Category</label>
          <select style={{ width: '100%', padding: '6px', borderRadius: '6px', border: '1px solid #CBD5E1', fontSize: '0.85rem', marginBottom: '8px' }}>
            <option>Item Condition Discrepancy</option>
            <option>Seller No-Show / Late</option>
            <option>Safety / Inappropriate Conduct</option>
            <option>Payment Dispute</option>
          </select>

          <label style={{ fontSize: '0.78rem', fontWeight: 700, display: 'block', marginBottom: '4px' }}>Description</label>
          <textarea
            rows={3}
            placeholder="Describe what occurred during the meeting..."
            style={{ width: '100%', padding: '6px', borderRadius: '6px', border: '1px solid #CBD5E1', fontSize: '0.85rem' }}
          />
        </div>

        <button className="app-btn app-btn-primary">Submit Report to Safety Operations</button>
      </div>
    );
  }

  // Surface 9: Upload / Camera / Image Picker & Media Manager
  if (surface === 'media-picker') {
    return (
      <div>
        <div className="app-card">
          <h4>Product & Attachment Photos</h4>
          <p style={{ fontSize: '0.82rem', color: '#64748B', marginBottom: '8px' }}>
            Upload real photos of your merchandise or proof. Maximum 5 photos.
          </p>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '8px', marginBottom: '12px' }}>
            <div style={{ aspectRatio: '1', background: '#F1F5F9', border: '1.5px dashed #94A3B8', borderRadius: '8px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', fontSize: '0.75rem', color: '#64748B' }}>
              <Camera size={20} />
              <span>Camera</span>
            </div>
            <div style={{ aspectRatio: '1', background: '#F1F5F9', border: '1.5px dashed #94A3B8', borderRadius: '8px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', fontSize: '0.75rem', color: '#64748B' }}>
              <Upload size={20} />
              <span>Gallery</span>
            </div>
            <div style={{ aspectRatio: '1', background: '#E2E8F0', borderRadius: '8px', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '0.75rem', fontWeight: 700 }}>
              iPad.jpg
            </div>
          </div>
        </div>

        <div className="app-notice">
          <Shield size={14} />
          <span>Uploaded images are stored in a private Supabase bucket and shown only to deal participants.</span>
        </div>

        <button className="app-btn app-btn-primary">Save Media Attachments</button>
      </div>
    );
  }

  // Surface 10: Store Catalog Category & Listing Manager Sheet
  if (surface === 'store-catalog') {
    return (
      <div>
        <div className="app-card">
          <div className="app-badge-row">
            <span className="badge badge-navy">Store Manager</span>
            <span className="badge badge-success">Active Listings: 4 / 15</span>
          </div>
          <h4>Store Products & Services</h4>
          <p style={{ fontSize: '0.82rem', color: '#64748B' }}>
            Pro plan allows up to 15 published listings. Item payments are settled offline in store.
          </p>
        </div>

        <div className="app-card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <strong>Apple iPad Pro 11" (256GB)</strong>
              <div style={{ fontSize: '0.78rem', color: '#64748B' }}>Electronics • $620.00</div>
            </div>
            <span className="badge badge-success">Published</span>
          </div>
        </div>

        <div className="app-card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <strong>iPhone 14 Screen Replacement</strong>
              <div style={{ fontSize: '0.78rem', color: '#64748B' }}>Local Service • $89.00</div>
            </div>
            <span className="badge badge-warning">Paused</span>
          </div>
        </div>

        <button className="app-btn app-btn-primary">+ Add New Product or Service</button>
      </div>
    );
  }

  return <div>Surface loaded</div>;
}
