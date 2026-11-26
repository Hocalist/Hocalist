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
        <p>For most Android phones, choose the 64-bit APK. Open the downloaded file on your phone to install it.</p>
        <div className="marketplace-preview-actions">
          <DownloadLink href="/download/android-preview" platform="android">Download preview APK</DownloadLink>
          <DownloadLink href="/download/android-preview?architecture=arm32" platform="android" variant="secondary">Older phone? Get 32-bit</DownloadLink>
        </div>
        <p className="store-availability">64-bit: {(release.arm64.bytes / 1000000).toFixed(1)} MB · 32-bit: {(release.arm32.bytes / 1000000).toFixed(1)} MB · Android 7 or later.</p>
        <p className="store-availability">This updates an existing Hocalist installation. It is a test app, not a Google Play release. Optional analytics follow your in-app consent setting.</p>
      </div>
    </section>
  );
}
