import { marketplacePreviewRelease as release } from '../lib/marketplace-preview-release';
import { DownloadLink } from './DownloadLink';

export function MarketplacePreview() {
  return (
    <section id="marketplace-preview" className="marketplace-preview-section" aria-labelledby="marketplace-preview-title">
      <div>
        <span className="status-chip">Android preview</span>
        <h2 id="marketplace-preview-title">Try the latest marketplace updates.</h2>
        <p>Review the latest buyer and seller screens, meeting improvements and account fixes on your phone.</p>
        <p className="store-availability">Preview build · {release.date}. Payments are in test mode and calling is unavailable.</p>
      </div>
      <div className="marketplace-preview-install">
        <h3>Download the preview</h3>
        <p>Open the downloaded file on your phone to install it.</p>
        <div className="marketplace-preview-actions">
          <DownloadLink href="/download/android-preview" platform="android">Download preview APK</DownloadLink>
        </div>
        <p className="store-availability">{(release.arm64.bytes / 1000000).toFixed(1)} MB · 32-bit and 64-bit ARM phones · Android 7 or later.</p>
        <p className="store-availability">If your Hocalist preview uses the previous signing key (build 4002 or earlier), uninstall it before switching to this preview and then sign in again. This is an early-access test app. Optional analytics follow your in-app consent setting.</p>
      </div>
    </section>
  );
}
