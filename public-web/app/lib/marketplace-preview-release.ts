// Pinned preview assets; the regular Android download remains independent.
const releaseRoot = 'https://github.com/Hocalist/Hocalist/releases/download/marketplace-preview-2026-11-26';

export const marketplacePreviewRelease = {
  date: '26 November 2026',
  version: '1.0.0',
  sourceCommit: 'acc04f4aec204b1c28e71b9c400c6df005e83268',
  arm64: {
    assetUrl: `${releaseRoot}/Hocalist-Marketplace-Preview-2026-11-26-arm64.apk`,
    bytes: 77390388,
    sha256: 'e522f42f7049c5edef5b8652c9d762572aa5a70747cfa3eb77e3c7e106ac093a',
  },
  arm32: {
    assetUrl: `${releaseRoot}/Hocalist-Marketplace-Preview-2026-11-26-arm32.apk`,
    bytes: 70197496,
    sha256: '5f7ec7fe43dfe36ee47761a858b0abfc89ef537e9cb67727c54875a54126a4cb',
  },
} as const;
