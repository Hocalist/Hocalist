// Pinned preview assets; the regular Android download remains independent.
const releaseRoot = 'https://github.com/Hocalist/Hocalist/releases/download/marketplace-preview-2026-11-26';

export const marketplacePreviewRelease = {
  date: '26 November 2026 · Revision 2',
  version: '1.0.0',
  sourceCommit: '04e88deae50afaa153f7c75c2bd842ba15b8041b',
  arm64: {
    assetUrl: `${releaseRoot}/Hocalist-Marketplace-Preview-2026-11-26-arm64.apk`,
    bytes: 77683886,
    sha256: '08a11dd7e36dab79eac6241a38e928599b75967dc451072a4cd76e351d1525ff',
  },
  arm32: {
    assetUrl: `${releaseRoot}/Hocalist-Marketplace-Preview-2026-11-26-arm32.apk`,
    bytes: 70507378,
    sha256: '99908e266d880467ce970399ae9db5b5463b439f767f3e63e9942db97b49db84',
  },
} as const;
