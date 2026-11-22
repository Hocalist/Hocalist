import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageShell } from '../../../site-content';
import BlogCards from '../../BlogCards';
import { blogPosts } from '../../posts';
import { blogTopicPath, groupBlogPosts } from '../../topics';
import styles from '../../blog.module.css';

type Props = { params: Promise<{ topic: string }> };
const topics = groupBlogPosts(blogPosts);

export const dynamicParams = false;
export const generateStaticParams = () => topics.map(({ slug }) => ({ topic: slug }));

async function getTopic(params: Props['params']) {
  const { topic } = await params;
  return topics.find(entry => entry.slug === topic) ?? notFound();
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const topic = await getTopic(params);
  const url = 'https://www.hocalist.com' + blogTopicPath(topic.slug);
  return { title: topic.title + ' guides', description: topic.description, alternates: { canonical: url },
    openGraph: { title: topic.title + ' guides', description: topic.description, url, type: 'website' } };
}

export default async function BlogTopicPage({ params }: Props) {
  const topic = await getTopic(params);
  return (
    <PageShell>
      <main className={styles.shell}>
        <header className={styles.intro}>
          <Link href="/blog">← All guides</Link>
          <h1>{topic.title}</h1>
          <p>{topic.description}</p>
        </header>
        <BlogCards posts={topic.articles} heading="h2" />
      </main>
    </PageShell>
  );
}
