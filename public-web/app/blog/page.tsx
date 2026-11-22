import type { Metadata } from 'next';
import Link from 'next/link';
import { PageShell } from '../site-content';
import { blogPosts } from './posts';
import BlogCards from './BlogCards';
import { blogTopicPath, groupBlogPosts } from './topics';
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
  const topics = groupBlogPosts(blogPosts);
  return (
    <PageShell>
      <main className={styles.shell}>
        <header className={styles.intro}>
          <p className="eyebrow">Hocalist Blog</p>
          <h1>Buying and selling locally</h1>
          <p>{description}</p>
        </header>
        <nav className={styles.topicNav} aria-label="Browse blog topics">
          {topics.map(topic => <Link key={topic.slug} href={blogTopicPath(topic.slug)}>{topic.title}</Link>)}
        </nav>
        {topics.map(topic => (
          <section className={styles.topic} key={topic.slug}>
            <h2><Link href={blogTopicPath(topic.slug)}>{topic.title}</Link></h2>
            <p>{topic.description}</p>
            <BlogCards posts={topic.articles.slice(0, 4)} heading="h3" />
          </section>
        ))}
      </main>
    </PageShell>
  );
}
