import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { GET } from '../app/download/android-preview/route';
import { GET as regularDownload } from '../app/download/android/route';
import { marketplacePreviewRelease as preview } from '../app/lib/marketplace-preview-release';
import { androidTestRelease } from '../app/lib/android-test-release';

test('preview defaults to the pinned ARM64 APK and supports older ARM phones', () => {
  for (const [query, expected] of [
    ['', preview.arm64.assetUrl],
    ['?architecture=arm32', preview.arm32.assetUrl],
    ['?architecture=https://unrelated.test/file.apk', preview.arm64.assetUrl],
  ]) {
    const response = GET(new Request(`https://www.hocalist.com/download/android-preview${query}`));
    assert.equal(response.status, 307);
    assert.equal(response.headers.get('Location'), expected);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
  }
});

test('preview assets are complete, versioned and separate from the regular download', () => {
  for (const asset of [preview.arm64, preview.arm32]) {
    assert.ok(asset.bytes > 1000000);
    assert.match(asset.sha256, /^[a-f0-9]{64}$/);
    assert.equal(new URL(asset.assetUrl).hostname, 'github.com');
    assert.notEqual(asset.assetUrl, androidTestRelease.assetUrl);
  }
  assert.equal(regularDownload().headers.get('Location'), androidTestRelease.assetUrl);
});
