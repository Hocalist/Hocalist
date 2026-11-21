import type { Metadata } from 'next';
import Image from 'next/image';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageShell } from '../../site-content';
import { blogPostPath, blogPosts } from '../posts';
import styles from '../blog.module.css';

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
  return {
    title: post.title,
    description: post.description,
    alternates: { canonical },
    openGraph: {
      title: post.title,
      description: post.description,
      url: canonical,
      type: 'article',
      images: [{ url: siteUrl + post.image, alt: post.imageAlt }]
    }
  };
}

export default async function BlogPostPage({ params }: Props) {
  const post = await getPost(params);
  const related = blogPosts.filter((entry) => entry.slug !== post.slug);
  const structuredData = {
    '@context': 'https://schema.org',
    '@type': 'BlogPosting',
    headline: post.title,
    description: post.description,
    image: siteUrl + post.image,
    mainEntityOfPage: siteUrl + blogPostPath(post.slug),
    author: { '@type': 'Organization', name: 'Hocalist', url: siteUrl }
  };
  return (
    <PageShell>
      <main className={styles.shell}>
        <article className={styles.article}>
          <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, '\\u003c') }} />
          <header className={styles.intro}>
            <Link href="/blog">← All guides</Link>
            <h1>{post.title}</h1>
            <p>{post.description}</p>
          </header>
          <Image className={styles.heroImage} src={post.image} alt={post.imageAlt} width={1040} height={560} sizes="(max-width: 800px) 100vw, 760px" priority />
          {post.sections.map(({ heading, body }) => (
            <section key={heading}>
              <h2>{heading}</h2>
              <p>{body}</p>
            </section>
          ))}
          <p><Link href={post.next.href}>{post.next.label} →</Link></p>
        </article>
        <aside className={styles.related} aria-label="Related guides">
          <h2>Related guides</h2>
          {related.map((entry) => <p key={entry.slug}><Link href={blogPostPath(entry.slug)}>{entry.title}</Link></p>)}
        </aside>
      </main>
    </PageShell>
  );
}
