import { PolicyPage } from '../site-content';

export const metadata = {
  title: 'Hocalist Privacy Policy',
  description:
    'Privacy policy for Hocalist, including account data, seller billing, support, and safety information.'
};

export default function PrivacyPage() {
  return (
    <PolicyPage
      title="Privacy Policy"
      updated="Last updated: September 19, 2026"
      lead="This policy explains how Hocalist may collect, use, and protect information for buyer requests, seller offers, chat coordination, seller billing, support, and safety workflows."
      sections={[
        {
          title: 'Overview',
          body: [
            'Hocalist is a local reverse marketplace platform where buyers can post buying requests and sellers can send offers. Hocalist supports discovery, offer review, chat, and deal coordination.',
            'Buyer-to-seller item payments are arranged directly between users outside Hocalist. Seller plan payments, credits, and related seller service payments may be handled by a secure billing provider.'
          ]
        },
        {
          title: 'Information we collect',
          body: [
            'We may collect account information, profile details, contact information, buyer request details, seller offer information, support messages, safety reports, and usage information related to the app or website.',
            'For seller billing, a secure billing provider may collect the payment information needed for seller subscriptions, credits, or related seller service fees.'
          ]
        },
        {
          title: 'Google sign-in',
          body: [
            'When Google sign-in becomes available and you choose it, Hocalist will use your Google account identifier, email address and basic profile information, such as your name and profile image, to authenticate you and set up your Hocalist profile.',
            'Google sign-in is intended for account access. It does not require access to your Gmail messages, Google Drive files or contacts. Your Google password is not shared with Hocalist.',
            'Authentication information is handled by our authentication service provider to establish and protect your session. You can remove Hocalist access in your Google account settings; to request deletion of your Hocalist account and associated data, contact privacy@hocalist.com. Removing Google access alone does not delete your Hocalist account.'
          ]
        },
        {
          title: 'Seller plan billing',
          body: [
            'Hocalist may use a secure billing provider for seller subscriptions, credits, and related seller service payments. Hocalist does not store full payment card numbers on its own systems.',
            'The billing provider may handle billing details, payment method information, invoices, and related seller plan records according to its own terms and privacy practices.'
          ]
        },
        {
          title: 'How we use information',
          body: [
            'We use information to provide account access, display buyer requests and seller offers, support chat and deal coordination, operate safety and reporting workflows, improve the service, and respond to support requests.',
            'Seller billing information is used to manage invoices, subscription status, credits, promoted visibility, and related seller services.'
          ]
        },
        {
          title: 'Sharing and service providers',
          body: [
            'We may share information with service providers that help operate hosting, analytics, support, security, and billing workflows. We do not sell personal information as a core business model.',
            'We may disclose information when required by law, to protect users, to investigate abuse, or to enforce terms and safety rules.'
          ]
        },
        {
          title: 'Data retention and security',
          body: [
            'We retain information for as long as needed to provide the service, meet legal obligations, resolve disputes, prevent abuse, and maintain business records.',
            'We use reasonable technical and organizational safeguards, but no internet service can guarantee absolute security.'
          ]
        },
        {
          title: 'User choices and contact',
          body: [
            'Users may contact Hocalist to request support with account information, privacy questions, or billing questions.',
            'Privacy contact: privacy@hocalist.com. For written notices, email support@hocalist.com for current mailing details.'
          ]
        }
      ]}
    />
  );
}
