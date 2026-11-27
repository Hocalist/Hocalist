// Pinned preview assets; the regular Android download remains independent.
const releaseAsset = {
  assetUrl: 'https://github.com/Hocalist/Hocalist/releases/download/marketplace-preview-4003/Hocalist-Android-Preview-4003.apk',
  bytes: 107449631,
  sha256: '80369229457a8f9878386480a5c3c514fddeded1a48ffd74a6649daebe871f0f',
} as const;

export const marketplacePreviewRelease = {
  date: '27 November 2026',
  version: '1.0.0',
  sourceCommit: '59bbf43273be91fe7e3d52f7d46997fe022b39c2',
  arm64: releaseAsset,
  arm32: releaseAsset,
} as const;
