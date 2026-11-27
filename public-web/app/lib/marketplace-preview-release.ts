// Pinned preview assets; the regular Android download remains independent.
const releaseAsset = {
  assetUrl: 'https://github.com/Hocalist/Hocalist/releases/download/marketplace-preview-4004/Hocalist-Android-Preview-4004.apk',
  bytes: 107642663,
  sha256: '69d01ff6eb3588d6baa2dd2617cdc2edd98a2b5e6a5b0dc8178a6ad71a6c9fa8',
} as const;

export const marketplacePreviewRelease = {
  date: '27 November 2026',
  version: '1.0.0',
  sourceCommit: '59bbf43273be91fe7e3d52f7d46997fe022b39c2',
  arm64: releaseAsset,
  arm32: releaseAsset,
} as const;
