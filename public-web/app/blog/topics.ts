const topics = [
  { slug: 'buying-requests', title: 'Buying requests', description: 'Describe what you need and get useful offers from local sellers.', pattern: /\b(buying request|buyer request|write a request|post a request)\b/ },
  { slug: 'comparing-offers', title: 'Comparing offers', description: 'Compare prices, condition, and pickup details before you choose an offer.', pattern: /\b(compare|comparing|seller offer|seller offers|price comparison)\b/ },
  { slug: 'safe-meetups', title: 'Safe meetups', description: 'Plan local pickups, payments, and meetups with confidence.', pattern: /\b(safe|safety|meetup|meetups|scam|scams|pickup|payment)\b/ },
  { slug: 'selling-locally', title: 'Selling locally', description: 'Respond to buyer requests and prepare items for local sale.', pattern: /\b(sell|selling|listing|respond to buyers)\b/ },
] as const;

const general = {
  slug: 'secondhand-shopping',
  title: 'Secondhand shopping',
  description: 'Practical guides for choosing, inspecting, and buying secondhand items.',
};

export function topicForPost(post: { slug: string }) {
  const subject = post.slug.replaceAll('-', ' ');
  return topics.find(topic => topic.pattern.test(subject)) ?? general;
}

export function blogTopicPath(slug: string) {
  return `/blog/topics/${slug}`;
}

export function groupBlogPosts<Post extends { slug: string }>(posts: Post[]) {
  return [...topics, general].flatMap(topic => {
    const articles = posts.filter(post => topicForPost(post).slug === topic.slug);
    return articles.length ? [{ ...topic, articles }] : [];
  });
}

export function articleDates(post: { datePublished?: string; dateModified?: string }) {
  const valid = (date?: string) => date && /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)?$/.test(date) &&
    Number.isFinite(Date.parse(date));
  const datePublished = valid(post.datePublished) ? post.datePublished : undefined;
  const dateModified = valid(post.dateModified) &&
    (!datePublished || Date.parse(post.dateModified!) > Date.parse(datePublished)) ? post.dateModified : undefined;
  return { datePublished, dateModified };
}
