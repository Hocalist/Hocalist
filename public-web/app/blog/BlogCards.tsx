import Image from 'next/image';
import Link from 'next/link';
import { blogPostPath, type blogPosts } from './posts';
import styles from './blog.module.css';

export default function BlogCards({ posts, heading }: { posts: typeof blogPosts; heading: 'h2' | 'h3' }) {
  const Heading = heading;
  return (
    <div className={styles.grid}>
      {posts.map(post => (
        <article className={styles.card} key={post.slug}>
          <Image src={post.image} alt={post.imageAlt} width={768} height={432} sizes="(max-width: 640px) calc(100vw - 32px), (max-width: 1120px) 47vw, 532px" quality={65} />
          <div>
            <Heading><Link href={blogPostPath(post.slug)}>{post.title}</Link></Heading>
            <p>{post.description}</p>
          </div>
        </article>
      ))}
    </div>
  );
}
