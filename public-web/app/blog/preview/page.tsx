import type { Metadata } from 'next';
import { headers } from 'next/headers';
import { notFound } from 'next/navigation';
import { PageShell } from '../../site-content';
import BlogArticle from '../BlogArticle';
import type { BlogPost } from '../posts';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Private Blog Studio preview',
  robots: { index: false, follow: false, nocache: true },
};

const studioOrigin = 'https://hocalist-blog-studio-api.vercel.app';
const snapshotHeader = /^([a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}):([a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})$/;

export default async function PrivateBlogPreview() {
  const request = await headers();
  const authorization = request.get('authorization');
  const token = request.get('x-hocalist-draft');
  const snapshot = snapshotHeader.exec(token || '');
  if (!authorization || !/^Bearer [A-Za-z0-9._-]+$/.test(authorization) ||
      !token || (!snapshot && !/^[a-f0-9]{24}$/.test(token))) notFound();

  const endpoint = snapshot
    ? '/api/standalone?path=' + encodeURIComponent('/posts/' + snapshot[1] + '/preview')
    : '/api/studio?preview=' + token;
  const response = await fetch(studioOrigin + endpoint, {
    headers: { authorization },
    cache: 'no-store',
    redirect: 'error',
    signal: AbortSignal.timeout(15000),
  }).catch(() => null);
  if (!response?.ok) notFound();

  const result = await response.json();
  if (snapshot && (result.version !== snapshot[2] || !result.document)) notFound();
  const draft = (snapshot ? { ...result.document, imageData: result.imageData } : result) as {
    title: string;
    description: string;
    slug: string;
    sections: BlogPost['sections'];
    links?: BlogPost['links'] | null;
    next?: BlogPost['next'];
    image?: string | null;
    imageAlt?: string;
    imageData?: string | null;
    datePublished?: string;
    dateModified?: string;
  };
  if (!/^[a-z0-9-]+$/.test(draft.slug) || !draft.title || !Array.isArray(draft.sections)) notFound();
  const image = /^\/images\/[a-z0-9/_-]+\.(?:png|jpe?g)$/i.test(draft.image || '') ? draft.image! :
    /^https:\/\/www\.hocalist\.com\/images\/[a-z0-9/_-]+\.(?:png|jpe?g)$/i.test(draft.image || '')
      ? new URL(draft.image!).pathname : '/images/how-it-works/buyer-seller-coordinate.png';
  const cover = draft.imageData && draft.imageData.length <= 640000 &&
    /^\/9j\/[A-Za-z0-9+/]+={0,2}$/.test(draft.imageData) ? 'data:image/jpeg;base64,' + draft.imageData : undefined;
  if (draft.image?.includes('/images/blog/') && !cover) notFound();
  const post: BlogPost = {
    slug: draft.slug, title: draft.title, description: draft.description,
    sections: draft.sections, links: draft.links ?? undefined,
    next: draft.next ?? { href: '/how-it-works', label: 'See how Hocalist works' },
    image, imageAlt: draft.imageAlt ?? '',
    datePublished: draft.datePublished, dateModified: draft.dateModified,
  };
  return <PageShell><BlogArticle post={post} cover={cover} /></PageShell>;
}

