import type { MetadataRoute } from 'next';
import { blogPostPath, blogPosts } from './blog/posts';

const siteUrl = 'https://www.hocalist.com';

const publicRoutes = [
  '',
  '/how-it-works',
  '/pricing',
  '/safety',
  '/support',
  '/download',
  '/privacy',
  '/terms',
  '/refund-cancellation'
];

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    ...publicRoutes.map((route) => ({
      url: `${siteUrl}${route}`,
      lastModified: new Date('2026-07-09')
    })),
    ...['/blog', ...blogPosts.map(({ slug }) => blogPostPath(slug))].map((route) => ({
      url: `${siteUrl}${route}`
    }))
  ];
}
