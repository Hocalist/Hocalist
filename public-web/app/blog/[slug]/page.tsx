import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { PageShell } from '../../site-content';
import { blogPostPath, blogPosts } from '../posts';
import { articleDates } from '../topics';
import BlogArticle from '../BlogArticle';

type Props = { params: Promise<{ slug: string }> };
const siteUrl = 'https://www.hocalist.com';

export const dynamicParams = false;

export function generateStaticParams() {
  return blogPosts.map(({ slug }) => ({ slug }));
}

async function getPost(params: Props['params']) {
  const { slug } = await params;
  const post = blogPosts.find((entry) => entry.slug === slug);
  if (!post) notFound();
  return post;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const post = await getPost(params);
  const canonical = siteUrl + blogPostPath(post.slug);
  const dates = articleDates(post);
  return {
    title: post.title,
    description: post.description,
    alternates: { canonical },
    openGraph: {
      title: post.title,
      description: post.description,
      url: canonical,
      type: 'article',
      publishedTime: dates.datePublished,
      modifiedTime: dates.dateModified,
      images: [{ url: siteUrl + post.image, alt: post.imageAlt }]
    }
  };
}

export default async function BlogPostPage({ params }: Props) {
  const post = await getPost(params);
  const dates = articleDates(post);
  const structuredData = {
    '@context': 'https://schema.org',
    '@type': 'BlogPosting',
    headline: post.title,
    description: post.description,
    ...dates,
    image: siteUrl + post.image,
    mainEntityOfPage: siteUrl + blogPostPath(post.slug),
    author: { '@type': 'Organization', name: 'Hocalist', url: siteUrl }
  };
  return (
    <PageShell>
      <BlogArticle post={post}>
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, '\\u003c') }} />
        <script type="application/json" id="hocalist-editorial-article" dangerouslySetInnerHTML={{ __html: JSON.stringify(post).replace(/</g, '\\u003c') }} />
      </BlogArticle>
    </PageShell>
  );
}
