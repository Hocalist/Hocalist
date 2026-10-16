import type { Metadata } from 'next';
import './globals.css';
import './illustrated-site.css';
import { ScrollReveal } from './ScrollReveal';

export const metadata: Metadata = {
  metadataBase: new URL('https://hocalist.com'),
  title: {
    default: 'Hocalist | Post What You Need and Compare Local Seller Offers',
    template: '%s | Hocalist'
  },
  description:
    'Hocalist helps buyers post item requests and receive competing offers from nearby sellers. Compare price, condition and availability before choosing a seller.',
  icons: { icon: '/brand/hocalist-icon.png', apple: '/brand/hocalist-icon.png' },
  openGraph: {
    title: 'Hocalist | Post What You Need and Compare Local Seller Offers',
    description:
      'Post item requests, compare nearby seller offers, and choose who to chat with before arranging details directly.',
    url: 'https://hocalist.com',
    siteName: 'Hocalist',
    type: 'website',
    images: ['/brand/hocalist-wordmark.png']
  },
  alternates: {
    canonical: 'https://hocalist.com'
  }
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&amp;family=Manrope:wght@400;500;600;700;800&amp;display=swap" /></head>
      <body>
        <ScrollReveal />
        {children}
      </body>
    </html>
  );
}
