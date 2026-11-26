import { marketplacePreviewRelease } from '../../lib/marketplace-preview-release';

export function GET(request: Request) {
  const architecture = new URL(request.url).searchParams.get('architecture');
  const asset = architecture === 'arm32'
    ? marketplacePreviewRelease.arm32
    : marketplacePreviewRelease.arm64;
  return new Response(null, {
    status: 307,
    headers: { Location: asset.assetUrl, 'Cache-Control': 'no-store' },
  });
}
