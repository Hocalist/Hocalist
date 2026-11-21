import type { Metadata } from 'next';
import Link from 'next/link';
import Image from 'next/image';
import { PageShell } from '../site-content';
import { blogPostPath, blogPosts } from './posts';
import styles from './blog.module.css';

const title = 'Blog and local marketplace guides';
const description = 'Practical Hocalist guides for writing buying requests, comparing seller offers, and coordinating local purchases.';
const canonical = 'https://www.hocalist.com/blog';

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical },
  openGraph: { title, description, url: canonical, type: 'website' }
};

export default function BlogPage() {
  return (
    <PageShell>
      <main className={styles.shell}>
        <header className={styles.intro}>
          <p className="eyebrow">Hocalist Blog</p>
          <h1>Buying and selling locally</h1>
          <p>{description}</p>
        </header>
        <div className={styles.grid}>
          {blogPosts.map((post) => (
            <article className={styles.card} key={post.slug}>
              <Image src={post.image} alt={post.imageAlt} width={768} height={440} sizes="(max-width: 640px) 100vw, 520px" />
              <div>
                <h2><Link href={blogPostPath(post.slug)}>{post.title}</Link></h2>
                <p>{post.description}</p>
              </div>
            </article>
          ))}
        </div>
      </main>
    </PageShell>
  );
}
