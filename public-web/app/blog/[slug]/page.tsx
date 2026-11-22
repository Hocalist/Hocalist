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
  const editorialLinks = (post as typeof post & {
    links?: { href: string; label: string }[];
  }).links?.slice(0, 2).filter(({ href }) =>
    /^\/(?:blog\/[a-z0-9-]+|how-it-works|safety|downloads?)$/.test(href) ||
    /^https:\/\/[a-z0-9][a-z0-9.-]+\.[a-z]{2,}(?:[/?#][^\s<>"'\\]*)?$/i.test(href)
  );
  const related = editorialLinks === undefined && blogPosts.find(
    (entry) => entry.slug !== post.slug && blogPostPath(entry.slug) !== post.next.href
  );
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
        <article className={styles.article} data-editorial-version={post.version}>
          <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, '\\u003c') }} />
          <script type="application/json" id="hocalist-editorial-article" dangerouslySetInnerHTML={{ __html: JSON.stringify(post).replace(/</g, '\\u003c') }} />
          <header className={styles.intro}>
            <Link href="/blog">← All guides</Link>
            <h1>{post.title}</h1>
            <p>{post.description}</p>
          </header>
          <Image className={styles.heroImage} src={post.image} alt={post.imageAlt} width={1040} height={560} sizes="(max-width: 800px) 100vw, 760px" priority />
          {post.sections.map(({ heading, body }, sectionIndex) => (
            <section key={`${sectionIndex}-${heading}`}>
              <h2>{heading}</h2>
              {body.split(/\r?\n[ \t]*\r?\n+|\r?\n(?=### )/).flatMap((block, index) => {
                const text = block.trim();
                if (!text) return [];
                const heading = /^### +([^\r\n]+)(?:\r?\n([\s\S]*))?$/.exec(text);
                if (!heading) return [<p key={index}>{text}</p>];
                return [<h3 key={index}>{heading[1]}</h3>,
                  ...(heading[2]?.trim() ? [<p key={`${index}-text`}>{heading[2].trim()}</p>] : [])];
              })}
            </section>
          ))}
          {editorialLinks === undefined
            ? <p><Link href={post.next.href}>{post.next.label} →</Link></p>
            : editorialLinks.map(({ href, label }) => <p key={href}><Link href={href}>{label} →</Link></p>)}
        </article>
        {related && (
          <aside className={styles.related} aria-label="Related guides">
            <h2>Related guides</h2>
            <p><Link href={blogPostPath(related.slug)}>{related.title}</Link></p>
          </aside>
        )}
      </main>
    </PageShell>
  );
}
