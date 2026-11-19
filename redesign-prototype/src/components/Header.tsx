import React, { useState } from 'react';
import { WebsiteRoute } from '../types';
import { Menu, X, Shield, ArrowRight, ExternalLink } from 'lucide-react';

interface HeaderProps {
  currentRoute: WebsiteRoute;
  setRoute: (r: WebsiteRoute) => void;
}

export const Header: React.FC<HeaderProps> = ({ currentRoute, setRoute }) => {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const navLinks: { id: WebsiteRoute; label: string }[] = [
    { id: 'home', label: 'Home' },
    { id: 'how-it-works', label: 'How It Works' },
    { id: 'pricing', label: 'Seller Plans' },
    { id: 'safety', label: 'Safety Guide' },
    { id: 'support', label: 'Support' },
    { id: 'billing', label: 'Seller Portal' }
  ];

  function handleNavigate(route: WebsiteRoute) {
    setRoute(route);
    setMobileMenuOpen(false);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  return (
    <header className="site-header">
      <div className="container header-inner">
        {/* Brand Logo - Exact current transparent logo */}
        <div className="header-brand" onClick={() => handleNavigate('home')} role="button" tabIndex={0}>
          <img
            src="/brand/hocalist-logo-with-no-background.png"
            alt="Hocalist Logo"
            className="brand-logo"
            height={44}
          />
        </div>

        {/* Desktop Navigation */}
        <nav className="desktop-nav" aria-label="Main Navigation">
          {navLinks.map((link) => (
            <button
              key={link.id}
              className={`nav-link ${currentRoute === link.id ? 'active' : ''}`}
              onClick={() => handleNavigate(link.id)}
            >
              {link.label}
              {link.id === 'billing' && <span className="nav-sub-chip">Stripe</span>}
            </button>
          ))}
        </nav>

        {/* Desktop Action CTAs */}
        <div className="header-actions">
          <button
            className="btn btn-ghost btn-sm"
            onClick={() => handleNavigate('pricing')}
          >
            Seller Plans
          </button>
          <button
            className="btn btn-primary btn-sm"
            onClick={() => handleNavigate('download')}
          >
            Join Waitlist
            <ArrowRight size={15} />
          </button>
        </div>

        {/* Mobile Hamburger Button */}
        <button
          className="mobile-toggle"
          aria-label={mobileMenuOpen ? 'Close Menu' : 'Open Menu'}
          onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
        >
          {mobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
        </button>
      </div>

      {/* Mobile Drawer Menu */}
      {mobileMenuOpen && (
        <div className="mobile-drawer-overlay" onClick={() => setMobileMenuOpen(false)}>
          <div className="mobile-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="mobile-drawer-header">
              <img
                src="/brand/hocalist-logo-with-no-background.png"
                alt="Hocalist Logo"
                className="drawer-logo"
                height={36}
              />
              <button
                className="close-btn"
                onClick={() => setMobileMenuOpen(false)}
                aria-label="Close menu"
              >
                <X size={20} />
              </button>
            </div>

            <div className="mobile-drawer-body">
              <nav className="mobile-nav-list">
                {navLinks.map((link) => (
                  <button
                    key={link.id}
                    className={`mobile-nav-item ${currentRoute === link.id ? 'active' : ''}`}
                    onClick={() => handleNavigate(link.id)}
                  >
                    <span>{link.label}</span>
                    <ArrowRight size={16} />
                  </button>
                ))}
              </nav>

              <div className="mobile-boundary-box">
                <div className="boundary-title">
                  <Shield size={14} />
                  <span>Offline Marketplace Notice</span>
                </div>
                <p className="boundary-text">
                  Item payments happen offline in person between buyer and seller. Hocalist billing covers seller plans and HocaCredits only.
                </p>
              </div>

              <div className="mobile-drawer-actions">
                <button
                  className="btn btn-primary btn-lg full-width"
                  onClick={() => handleNavigate('download')}
                >
                  Join Buyer Waitlist
                </button>
                <button
                  className="btn btn-secondary btn-lg full-width"
                  onClick={() => handleNavigate('pricing')}
                >
                  Explore Seller Plans
                </button>
              </div>

              <div className="mobile-drawer-legal">
                <button onClick={() => handleNavigate('terms')}>Terms</button>
                <span>•</span>
                <button onClick={() => handleNavigate('privacy')}>Privacy</button>
                <span>•</span>
                <button onClick={() => handleNavigate('refund-cancellation')}>Refund Policy</button>
              </div>
            </div>
          </div>
        </div>
      )}

      <style>{`
        .site-header {
          position: sticky;
          top: 0;
          z-index: 999;
          background: rgba(255, 255, 255, 0.94);
          backdrop-filter: blur(12px);
          -webkit-backdrop-filter: blur(12px);
          border-bottom: 1px solid var(--border-subtle);
          box-shadow: 0 2px 10px rgba(0, 3, 108, 0.04);
        }
        .header-inner {
          display: flex;
          align-items: center;
          justify-content: space-between;
          height: var(--header-height);
        }
        .header-brand {
          display: flex;
          align-items: center;
          cursor: pointer;
        }
        .brand-logo {
          height: 44px;
          width: auto;
          object-fit: contain;
          transition: transform var(--transition-fast);
        }
        .brand-logo:hover {
          transform: scale(1.02);
        }
        .desktop-nav {
          display: flex;
          align-items: center;
          gap: 1.5rem;
        }
        .nav-link {
          background: transparent;
          font-size: 0.92rem;
          font-weight: 600;
          color: var(--text-secondary);
          padding: 0.5rem 0.25rem;
          position: relative;
          display: inline-flex;
          align-items: center;
          gap: 0.35rem;
          transition: color var(--transition-fast);
        }
        .nav-link:hover {
          color: var(--hoca-navy);
        }
        .nav-link.active {
          color: var(--hoca-navy);
        }
        .nav-link.active::after {
          content: '';
          position: absolute;
          bottom: -4px;
          left: 0;
          right: 0;
          height: 2.5px;
          background: var(--hoca-navy);
          border-radius: 2px;
        }
        .nav-sub-chip {
          font-size: 0.68rem;
          background: var(--hoca-blue-tint);
          color: var(--hoca-blue);
          padding: 0.15rem 0.4rem;
          border-radius: 4px;
          font-weight: 700;
          letter-spacing: 0.02em;
        }
        .header-actions {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }
        .mobile-toggle {
          display: none;
          background: transparent;
          color: var(--hoca-navy);
          padding: 0.4rem;
          border-radius: var(--radius-sm);
        }
        @media (max-width: 900px) {
          .desktop-nav, .header-actions {
            display: none;
          }
          .mobile-toggle {
            display: flex;
          }
        }
        .mobile-drawer-overlay {
          position: fixed;
          inset: 0;
          background: rgba(0, 3, 108, 0.4);
          backdrop-filter: blur(4px);
          z-index: 10000;
          display: flex;
          justify-content: flex-end;
          animation: fadeIn 0.2s ease-out;
        }
        .mobile-drawer {
          width: 85%;
          max-width: 360px;
          height: 100%;
          background: white;
          box-shadow: -4px 0 20px rgba(0, 0, 0, 0.15);
          display: flex;
          flex-direction: column;
          animation: slideLeft 0.25s cubic-bezier(0.16, 1, 0.3, 1);
        }
        @keyframes slideLeft {
          from { transform: translateX(100%); }
          to { transform: translateX(0); }
        }
        .mobile-drawer-header {
          padding: 1.25rem 1.5rem;
          display: flex;
          align-items: center;
          justify-content: space-between;
          border-bottom: 1px solid var(--border-subtle);
        }
        .drawer-logo {
          height: 34px;
          width: auto;
        }
        .close-btn {
          background: var(--bg-muted);
          border-radius: var(--radius-sm);
          padding: 0.4rem;
          color: var(--text-secondary);
        }
        .mobile-drawer-body {
          padding: 1.5rem;
          flex: 1;
          display: flex;
          flex-direction: column;
          overflow-y: auto;
        }
        .mobile-nav-list {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          margin-bottom: 1.5rem;
        }
        .mobile-nav-item {
          display: flex;
          align-items: center;
          justify-content: space-between;
          background: transparent;
          padding: 0.85rem 1rem;
          border-radius: var(--radius-md);
          font-weight: 600;
          font-size: 1rem;
          color: var(--text-primary);
          text-align: left;
          transition: all 0.15s ease;
        }
        .mobile-nav-item:hover, .mobile-nav-item.active {
          background: var(--hoca-blue-tint);
          color: var(--hoca-navy);
        }
        .mobile-boundary-box {
          background: var(--bg-subtle);
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-md);
          padding: 0.9rem;
          margin-bottom: 1.5rem;
        }
        .boundary-title {
          display: flex;
          align-items: center;
          gap: 0.4rem;
          font-size: 0.8rem;
          font-weight: 700;
          color: var(--hoca-navy);
          margin-bottom: 0.35rem;
        }
        .boundary-text {
          font-size: 0.78rem;
          line-height: 1.45;
          color: var(--text-muted);
        }
        .mobile-drawer-actions {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          margin-bottom: 1.5rem;
        }
        .full-width {
          width: 100%;
        }
        .mobile-drawer-legal {
          margin-top: auto;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.75rem;
          font-size: 0.82rem;
          color: var(--text-muted);
          padding-top: 1rem;
          border-top: 1px solid var(--border-subtle);
        }
        .mobile-drawer-legal button {
          background: transparent;
          color: var(--text-muted);
          font-size: 0.82rem;
        }
        .mobile-drawer-legal button:hover {
          color: var(--hoca-navy);
        }
      `}</style>
    </header>
  );
};
