import type { MetadataRoute } from 'next';
import { blogPostPath, blogPosts } from './blog/posts';
import { articleDates, blogTopicPath, groupBlogPosts } from './blog/topics';

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
    { url: `${siteUrl}/blog` },
    ...groupBlogPosts(blogPosts).map(({ slug }) => ({ url: siteUrl + blogTopicPath(slug) })),
    ...blogPosts.map(post => {
      const { datePublished, dateModified } = articleDates(post);
      const lastModified = dateModified ?? datePublished;
      return { url: siteUrl + blogPostPath(post.slug), ...(lastModified && { lastModified }) };
    })
  ];
}
