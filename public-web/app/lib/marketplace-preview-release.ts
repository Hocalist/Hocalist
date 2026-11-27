// Pinned preview assets; the regular Android download remains independent.
const releaseAsset = {
  assetUrl: 'https://github.com/Hocalist/Hocalist/releases/download/marketplace-preview-4005/Hocalist-Android-Preview-4005.apk',
  bytes: 107742017,
  sha256: '2b891cae08bd968d71ca8d192eff90eeeb0677fb33339673ee2db59655baecc4',
} as const;

export const marketplacePreviewRelease = {
  date: '27 November 2026',
  version: '1.0.0',
  sourceCommit: '0575895ca28ba76ae815f1f61f6242f8e28eb139',
  arm64: releaseAsset,
  arm32: releaseAsset,
} as const;
