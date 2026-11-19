import React, { useState, useEffect } from 'react';
import './styles/design-tokens.css';
import { WebsiteRoute, AppProposalSurface, ViewportMode, TextScale, SurfaceState } from './types';
import { PrototypeBar } from './components/PrototypeBar';
import { Header } from './components/Header';
import { Footer } from './components/Footer';

// Website Views
import { HomeView } from './views/website/HomeView';
import { HowItWorksView } from './views/website/HowItWorksView';
import { PricingView } from './views/website/PricingView';
import { DownloadView } from './views/website/DownloadView';
import { SupportView } from './views/website/SupportView';
import { SafetyView } from './views/website/SafetyView';
import { TermsView } from './views/website/TermsView';
import { PrivacyView } from './views/website/PrivacyView';
import { RefundCancellationView } from './views/website/RefundCancellationView';
import { BillingView } from './views/website/BillingView';
import { BillingReturnView } from './views/website/BillingReturnView';
import { BillingCancelView } from './views/website/BillingCancelView';

// App Supplemental Proposals View
import { AppProposalsView } from './views/app-proposals/AppProposalsView';

export function App() {
  const [mode, setMode] = useState<'website' | 'app-proposals'>('website');
  const [currentRoute, setRoute] = useState<WebsiteRoute>('home');
  const [currentSurface, setSurface] = useState<AppProposalSurface>('location-map');
  const [viewport, setViewport] = useState<ViewportMode>('desktop');
  const [reducedMotion, setReducedMotion] = useState(false);
  const [textScale, setTextScale] = useState<TextScale>('1.0');
  const [surfaceState, setSurfaceState] = useState<SurfaceState>('default');

  // Handle URL hash navigation for direct linking
  useEffect(() => {
    const handleHash = () => {
      const hash = window.location.hash.replace('#', '');
      if (hash.startsWith('app-')) {
        setMode('app-proposals');
        const sId = hash.replace('app-', '') as AppProposalSurface;
        if (sId) setSurface(sId);
      } else if (hash) {
        setMode('website');
        setRoute(hash as WebsiteRoute);
      }
    };
    handleHash();
    window.addEventListener('hashchange', handleHash);
    return () => window.removeEventListener('hashchange', handleHash);
  }, []);

  function handleRouteSelect(route: WebsiteRoute) {
    setRoute(route);
    window.location.hash = route;
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function handleSurfaceSelect(surface: AppProposalSurface) {
    setSurface(surface);
    window.location.hash = `app-${surface}`;
  }

  return (
    <div className={`app-root ${reducedMotion ? 'reduced-motion' : ''}`}>
      {/* Top Review Bar for Owner */}
      <PrototypeBar
        mode={mode}
        setMode={setMode}
        currentRoute={currentRoute}
        setRoute={handleRouteSelect}
        currentSurface={currentSurface}
        setSurface={handleSurfaceSelect}
        viewport={viewport}
        setViewport={setViewport}
        reducedMotion={reducedMotion}
        setReducedMotion={setReducedMotion}
        textScale={textScale}
        setTextScale={setTextScale}
        surfaceState={surfaceState}
        setSurfaceState={setSurfaceState}
      />

      {/* Render Website Redesign or App Supplemental Proposals */}
      {mode === 'website' ? (
        <div className={`website-wrapper viewport-${viewport}`}>
          <div className="website-frame">
            <Header currentRoute={currentRoute} setRoute={handleRouteSelect} />

            <main className="main-content">
              {currentRoute === 'home' && <HomeView setRoute={handleRouteSelect} />}
              {currentRoute === 'how-it-works' && <HowItWorksView setRoute={handleRouteSelect} />}
              {currentRoute === 'pricing' && <PricingView setRoute={handleRouteSelect} />}
              {currentRoute === 'download' && <DownloadView setRoute={handleRouteSelect} />}
              {currentRoute === 'support' && <SupportView setRoute={handleRouteSelect} />}
              {currentRoute === 'safety' && <SafetyView setRoute={handleRouteSelect} />}
              {currentRoute === 'terms' && <TermsView setRoute={handleRouteSelect} />}
              {currentRoute === 'privacy' && <PrivacyView setRoute={handleRouteSelect} />}
              {currentRoute === 'refund-cancellation' && <RefundCancellationView setRoute={handleRouteSelect} />}
              {currentRoute === 'billing' && <BillingView setRoute={handleRouteSelect} />}
              {currentRoute === 'billing-return' && <BillingReturnView setRoute={handleRouteSelect} />}
              {currentRoute === 'billing-cancel' && <BillingCancelView setRoute={handleRouteSelect} />}
            </main>

            <Footer setRoute={handleRouteSelect} />
          </div>
        </div>
      ) : (
        <AppProposalsView
          currentSurface={currentSurface}
          setSurface={handleSurfaceSelect}
          viewport={viewport}
          setViewport={setViewport}
          textScale={textScale}
          setTextScale={setTextScale}
          surfaceState={surfaceState}
          setSurfaceState={setSurfaceState}
        />
      )}

      <style>{`
        .app-root {
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          background: #00036C;
        }
        .website-wrapper {
          flex: 1;
          display: flex;
          flex-direction: column;
          background: #FFFFFF;
          transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
        }
        .website-frame {
          width: 100%;
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          background: #FFFFFF;
          margin: 0 auto;
        }
        .main-content {
          flex: 1;
        }

        /* Viewport Simulation Modes */
        .website-wrapper.viewport-tablet {
          background: #111827;
          padding: 2rem 0;
        }
        .website-wrapper.viewport-tablet .website-frame {
          max-width: 768px;
          border-radius: 16px;
          overflow: hidden;
          box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
        }

        .website-wrapper.viewport-mobile-390 {
          background: #111827;
          padding: 2rem 0;
        }
        .website-wrapper.viewport-mobile-390 .website-frame {
          max-width: 390px;
          border-radius: 28px;
          overflow: hidden;
          box-shadow: 0 20px 40px rgba(0, 0, 0, 0.5);
        }

        .website-wrapper.viewport-mobile-320 {
          background: #111827;
          padding: 2rem 0;
        }
        .website-wrapper.viewport-mobile-320 .website-frame {
          max-width: 320px;
          border-radius: 20px;
          overflow: hidden;
          box-shadow: 0 20px 40px rgba(0, 0, 0, 0.5);
        }
      `}</style>
    </div>
  );
}

export default App;
