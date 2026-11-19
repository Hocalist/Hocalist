import React, { useState } from 'react';
import { WebsiteRoute, AppProposalSurface, ViewportMode, TextScale, SurfaceState, WEBSITE_ROUTES, APP_PROPOSALS } from '../types';
import { Globe, Smartphone, Monitor, Eye, Activity, RotateCcw, ChevronUp, ChevronDown, Sliders } from 'lucide-react';

interface PrototypeBarProps {
  mode: 'website' | 'app-proposals';
  setMode: (m: 'website' | 'app-proposals') => void;
  currentRoute: WebsiteRoute;
  setRoute: (r: WebsiteRoute) => void;
  currentSurface: AppProposalSurface;
  setSurface: (s: AppProposalSurface) => void;
  viewport: ViewportMode;
  setViewport: (v: ViewportMode) => void;
  reducedMotion: boolean;
  setReducedMotion: (r: boolean) => void;
  textScale: TextScale;
  setTextScale: (t: TextScale) => void;
  surfaceState: SurfaceState;
  setSurfaceState: (s: SurfaceState) => void;
}

export const PrototypeBar: React.FC<PrototypeBarProps> = ({
  mode,
  setMode,
  currentRoute,
  setRoute,
  currentSurface,
  setSurface,
  viewport,
  setViewport,
  reducedMotion,
  setReducedMotion,
  textScale,
  setTextScale,
  surfaceState,
  setSurfaceState,
}) => {
  const [isCollapsed, setIsCollapsed] = useState(false);

  if (isCollapsed) {
    return (
      <div className="proto-collapsed-float">
        <button
          className="proto-collapsed-btn"
          onClick={() => setIsCollapsed(false)}
          title="Open Prototype Control Bar"
        >
          <span className="proto-dot" />
          <Sliders size={13} />
          <span>Prototype Menu</span>
          <ChevronDown size={14} />
        </button>
        <style>{`
          .proto-collapsed-float {
            position: fixed;
            bottom: 24px;
            right: 24px;
            z-index: 999999;
          }
          .proto-collapsed-btn {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            background: #000236;
            color: #FFFFFF;
            border: 1.5px solid #2A3C7E;
            border-radius: 9999px;
            padding: 0.6rem 1.1rem;
            font-size: 0.82rem;
            font-weight: 600;
            box-shadow: 0 8px 24px rgba(0, 3, 108, 0.45);
            cursor: pointer;
            transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
          }
          .proto-collapsed-btn:hover {
            background: #1A28D4;
            border-color: #4A63FF;
            transform: translateY(-2px);
            box-shadow: 0 10px 28px rgba(26, 40, 212, 0.5);
          }
          .proto-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #10B981;
            box-shadow: 0 0 8px #10B981;
          }
        `}</style>
      </div>
    );
  }

  return (
    <header className="proto-bar">
      <div className="proto-container">
        {/* Left: Mode Switcher */}
        <div className="proto-left">
          <div className="proto-brand">
            <span className="proto-pill">Hocalist Prototype</span>
          </div>

          <div className="proto-tabs" role="tablist">
            <button
              role="tab"
              aria-selected={mode === 'website'}
              className={`proto-tab ${mode === 'website' ? 'active' : ''}`}
              onClick={() => setMode('website')}
            >
              <Globe size={15} />
              <span>Public Website ({WEBSITE_ROUTES.length} Routes)</span>
            </button>
            <button
              role="tab"
              aria-selected={mode === 'app-proposals'}
              className={`proto-tab ${mode === 'app-proposals' ? 'active' : ''}`}
              onClick={() => setMode('app-proposals')}
            >
              <Smartphone size={15} />
              <span>App Proposals ({APP_PROPOSALS.length} Surfaces)</span>
            </button>
          </div>
        </div>

        {/* Center: Route or Surface Selector */}
        <div className="proto-center">
          {mode === 'website' ? (
            <div className="proto-select-wrapper">
              <label htmlFor="route-select" className="proto-label">Route:</label>
              <select
                id="route-select"
                className="proto-select"
                value={currentRoute}
                onChange={(e) => setRoute(e.target.value as WebsiteRoute)}
              >
                <optgroup label="Public Routes">
                  {WEBSITE_ROUTES.filter(r => r.category === 'public').map((r) => (
                    <option key={r.id} value={r.id}>{r.label} ({r.path})</option>
                  ))}
                </optgroup>
                <optgroup label="Billing & Stripe Portal">
                  {WEBSITE_ROUTES.filter(r => r.category === 'billing').map((r) => (
                    <option key={r.id} value={r.id}>{r.label} ({r.path})</option>
                  ))}
                </optgroup>
                <optgroup label="Legal & Policies">
                  {WEBSITE_ROUTES.filter(r => r.category === 'legal').map((r) => (
                    <option key={r.id} value={r.id}>{r.label} ({r.path})</option>
                  ))}
                </optgroup>
              </select>
            </div>
          ) : (
            <div className="proto-select-wrapper">
              <label htmlFor="surface-select" className="proto-label">Surface:</label>
              <select
                id="surface-select"
                className="proto-select"
                value={currentSurface}
                onChange={(e) => setSurface(e.target.value as AppProposalSurface)}
              >
                {APP_PROPOSALS.map((s) => (
                  <option key={s.id} value={s.id}>[{s.category}] {s.title}</option>
                ))}
              </select>
            </div>
          )}
        </div>

        {/* Right: Viewport, State & Text Scale Controls */}
        <div className="proto-right">
          {mode === 'website' ? (
            <div className="proto-viewport-group">
              <span className="proto-label">Viewport:</span>
              <button
                className={`proto-vp-btn ${viewport === 'desktop' ? 'active' : ''}`}
                title="Desktop (100% full width)"
                onClick={() => setViewport('desktop')}
              >
                <Monitor size={14} /> Desktop
              </button>
              <button
                className={`proto-vp-btn ${viewport === 'tablet' ? 'active' : ''}`}
                title="Tablet (768px)"
                onClick={() => setViewport('tablet')}
              >
                768px
              </button>
              <button
                className={`proto-vp-btn ${viewport === 'mobile-390' ? 'active' : ''}`}
                title="Mobile (390px iPhone)"
                onClick={() => setViewport('mobile-390')}
              >
                390px
              </button>
              <button
                className={`proto-vp-btn ${viewport === 'mobile-320' ? 'active' : ''}`}
                title="Narrow Mobile (320px)"
                onClick={() => setViewport('mobile-320')}
              >
                320px
              </button>
            </div>
          ) : (
            <div className="proto-controls-group">
              <div className="proto-ctl">
                <span className="proto-label">Device Width:</span>
                <select
                  className="proto-mini-select"
                  value={viewport}
                  onChange={(e) => setViewport(e.target.value as ViewportMode)}
                >
                  <option value="mobile-430">430px (Max/Plus)</option>
                  <option value="mobile-390">390px (Standard)</option>
                  <option value="mobile-360">360px (Samsung/Android)</option>
                  <option value="mobile-320">320px (Compact)</option>
                </select>
              </div>

              <div className="proto-ctl">
                <span className="proto-label">Text Scale:</span>
                <select
                  className="proto-mini-select"
                  value={textScale}
                  onChange={(e) => setTextScale(e.target.value as TextScale)}
                >
                  <option value="1.0">1.0x (Default)</option>
                  <option value="1.15">1.15x (Medium)</option>
                  <option value="1.3">1.3x (Large)</option>
                  <option value="1.6">1.6x (Extra Large)</option>
                </select>
              </div>

              <div className="proto-ctl">
                <span className="proto-label">State:</span>
                <select
                  className="proto-mini-select"
                  value={surfaceState}
                  onChange={(e) => setSurfaceState(e.target.value as SurfaceState)}
                >
                  <option value="default">Default / Populated</option>
                  <option value="loading">Loading Skeleton</option>
                  <option value="empty">Empty State</option>
                  <option value="unavailable">Unavailable / Gated</option>
                  <option value="error">Error State</option>
                </select>
              </div>
            </div>
          )}

          {/* Reduced Motion Toggle */}
          <button
            className={`proto-icon-btn ${reducedMotion ? 'active' : ''}`}
            title={reducedMotion ? 'Reduced Motion: ON' : 'Reduced Motion: OFF'}
            onClick={() => setReducedMotion(!reducedMotion)}
          >
            <Activity size={14} />
            <span className="proto-btn-text">{reducedMotion ? 'Reduced Motion' : 'Motion: On'}</span>
          </button>

          {/* Minimize / Collapse Bar */}
          <button
            className="proto-icon-btn"
            title="Minimize Prototype Controls to view full website"
            onClick={() => setIsCollapsed(true)}
          >
            <ChevronUp size={14} />
            <span className="proto-btn-text">Hide Bar</span>
          </button>
        </div>
      </div>

      <style>{`
        .proto-bar {
          background-color: #000236;
          color: #E2E8F0;
          border-bottom: 2px solid #1A28D4;
          position: sticky;
          top: 0;
          z-index: 9999;
          font-family: var(--font-body);
          font-size: 0.82rem;
          box-shadow: 0 4px 14px rgba(0, 0, 0, 0.25);
        }
        .proto-container {
          max-width: 1500px;
          margin: 0 auto;
          padding: 0.45rem 1rem;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 1rem;
          flex-wrap: wrap;
        }
        .proto-left {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }
        .proto-brand {
          display: flex;
          align-items: center;
        }
        .proto-pill {
          background: #1A28D4;
          color: white;
          font-weight: 700;
          font-size: 0.75rem;
          padding: 0.2rem 0.55rem;
          border-radius: 4px;
          letter-spacing: 0.04em;
          text-transform: uppercase;
        }
        .proto-tabs {
          display: flex;
          background: rgba(255, 255, 255, 0.08);
          padding: 2px;
          border-radius: 6px;
        }
        .proto-tab {
          display: inline-flex;
          align-items: center;
          gap: 0.4rem;
          padding: 0.35rem 0.75rem;
          border-radius: 5px;
          color: #94A3B8;
          background: transparent;
          font-size: 0.8rem;
          font-weight: 600;
          transition: all 0.15s ease;
        }
        .proto-tab.active {
          background: #1A28D4;
          color: white;
          box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
        }
        .proto-center {
          flex: 1;
          min-width: 260px;
          max-width: 440px;
        }
        .proto-select-wrapper {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .proto-label {
          color: #94A3B8;
          font-size: 0.78rem;
          font-weight: 500;
          white-space: nowrap;
        }
        .proto-select {
          flex: 1;
          background: #0A1138;
          color: #FFFFFF;
          border: 1px solid #2A3C7E;
          border-radius: 6px;
          padding: 0.35rem 0.65rem;
          font-size: 0.82rem;
          font-weight: 500;
          cursor: pointer;
        }
        .proto-select:focus {
          outline: none;
          border-color: #4A63FF;
        }
        .proto-right {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          flex-wrap: wrap;
        }
        .proto-viewport-group, .proto-controls-group {
          display: flex;
          align-items: center;
          gap: 0.35rem;
        }
        .proto-vp-btn {
          display: inline-flex;
          align-items: center;
          gap: 0.3rem;
          background: rgba(255, 255, 255, 0.08);
          color: #CBD5E1;
          border: 1px solid rgba(255, 255, 255, 0.1);
          padding: 0.3rem 0.55rem;
          border-radius: 4px;
          font-size: 0.76rem;
          font-weight: 500;
          cursor: pointer;
          transition: all 0.15s;
        }
        .proto-vp-btn:hover {
          background: rgba(255, 255, 255, 0.16);
          color: #FFF;
        }
        .proto-vp-btn.active {
          background: #1A28D4;
          color: #FFF;
          border-color: #2540FF;
        }
        .proto-ctl {
          display: flex;
          align-items: center;
          gap: 0.35rem;
        }
        .proto-mini-select {
          background: #0A1138;
          color: #FFF;
          border: 1px solid #2A3C7E;
          border-radius: 4px;
          padding: 0.25rem 0.45rem;
          font-size: 0.76rem;
          cursor: pointer;
        }
        .proto-icon-btn {
          display: inline-flex;
          align-items: center;
          gap: 0.35rem;
          background: rgba(255, 255, 255, 0.08);
          color: #94A3B8;
          border: 1px solid rgba(255, 255, 255, 0.1);
          padding: 0.3rem 0.6rem;
          border-radius: 4px;
          font-size: 0.76rem;
          cursor: pointer;
          transition: all 0.15s;
        }
        .proto-icon-btn.active {
          background: #B45309;
          color: white;
          border-color: #D97706;
        }
      `}</style>
    </header>
  );
};
