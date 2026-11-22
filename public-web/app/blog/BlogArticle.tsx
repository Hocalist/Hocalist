import type { ReactNode } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { blogPostPath, blogPosts, type BlogPost } from './posts';
import { articleDates, blogTopicPath, topicForPost } from './topics';
import styles from './blog.module.css';

export default function BlogArticle({ post, cover, children }: { post: BlogPost; cover?: string; children?: ReactNode }) {
  const dates = articleDates(post);
  const topic = topicForPost(post);
  const editorialLinks = post.links?.slice(0, 2).filter(({ href }) =>
    /^\/(?:blog\/[a-z0-9-]+|how-it-works|safety|downloads?)$/.test(href) ||
    /^https:\/\/[a-z0-9][a-z0-9.-]+\.[a-z]{2,}(?:[/?#][^\s<>"'\\]*)?$/i.test(href)
  );
  const related = editorialLinks === undefined && blogPosts.find(
    (entry) => entry.slug !== post.slug && blogPostPath(entry.slug) !== post.next.href
  );
  return (
    <main className={styles.shell}>
      <article className={styles.article} data-editorial-version={post.version}>
        {children}
        <header className={styles.intro}>
          <nav className={styles.breadcrumbs} aria-label="Blog navigation">
            <Link href="/blog">All guides</Link>
            <span aria-hidden="true">/</span>
            <Link href={blogTopicPath(topic.slug)}>{topic.title}</Link>
          </nav>
          <h1>{post.title}</h1>
          <p>{post.description}</p>
          {dates.datePublished && <p className={styles.date}>
            Published <ArticleDate value={dates.datePublished} />
            {dates.dateModified && <> · Updated <ArticleDate value={dates.dateModified} /></>}
          </p>}
        </header>
        <Image className={styles.heroImage} src={cover ?? post.image} unoptimized={Boolean(cover)} alt={post.imageAlt} width={1040} height={560} sizes="(max-width: 792px) calc(100vw - 32px), 760px" quality={65} priority />
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
  );
}

function ArticleDate({ value }: { value: string }) {
  return <time dateTime={value}>{new Intl.DateTimeFormat('en-US', {
    dateStyle: 'long', timeZone: /^\d{4}-\d{2}-\d{2}$/.test(value) ? 'UTC' : 'America/New_York'
  }).format(new Date(value))}</time>;
}
