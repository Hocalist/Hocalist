export const blogPosts = [
  {
    slug: 'how-to-write-a-local-buying-request',
    title: 'How to write a local buying request that gets useful offers',
    description: 'Learn what to include in a local buying request so sellers can tell whether they have what you need and send an offer you can compare.',
    image: '/images/how-it-works/buyer-request.png',
    imageAlt: 'A buyer writing a local buying request on a phone',
    sections: [
      {
        heading: 'Name the item and what it needs to do',
        body: 'Put the item and the main requirement in the title. “Compact dining table for four” helps a seller respond more precisely than “Looking for furniture.” In the description, add the dimensions, condition, or compatibility you need, and say where you can be flexible.'
      },
      {
        heading: 'Give sellers a budget, area, and timeframe',
        body: 'A budget range gives sellers room to explain why their offer is worth it. Include how far you can travel or a general neighborhood, and tell them when you need the item. Save your exact address and contact details for private coordination once you choose who to continue with.'
      },
      {
        heading: 'Ask for the details you’ll use to decide',
        body: 'Request current photos, relevant measurements, and any known damage. For a dining table, ask for the length, width, and whether the legs come off for transport. Those answers help you compare offers and avoid an unnecessary trip.'
      },
      {
        heading: 'Try this example',
        body: '“I’m looking for a dining table for four, up to 48 inches long, for $100–$150. I can pick it up near East Austin this weekend. Please send a photo of the tabletop, the dimensions, and whether the legs can be removed.”'
      }
    ],
    next: { href: '/how-it-works', label: 'See how requests and offers work' }
  },
  {
    slug: 'how-to-compare-local-seller-offers',
    title: 'How to compare offers from local sellers',
    description: 'Compare condition, total cost, pickup logistics, and seller answers before choosing an offer and arranging a local meetup.',
    image: '/images/how-it-works/seller-offer.png',
    imageAlt: 'A local seller preparing items for buyer requests',
    sections: [
      {
        heading: 'Compare what each offer includes',
        body: 'Check the exact model or dimensions, condition, accessories, and any known faults. If two offers are close in price, ask each seller for the same missing detail. Current photos can help you decide which item is worth seeing in person.'
      },
      {
        heading: 'Factor in the pickup',
        body: 'An offer across town may cost less upfront and still take more time to collect. Check the seller’s availability, distance, and whether you need transport or help moving the item. For a bulky purchase, confirm measurements before arranging pickup.'
      },
      {
        heading: 'Confirm the details before you meet',
        body: 'Use the conversation to agree on the item, price, time, and meetup location. A public location is a good option when practical. Inspect the item before paying and give yourself room to walk away if it differs from what you agreed.'
      },
      {
        heading: 'Keep payment arrangements clear',
        body: 'Buyers and sellers arrange item payment directly outside Hocalist. Confirm how you’ll pay before you meet, and only proceed once you’re comfortable with the condition and terms.'
      }
    ],
    next: { href: '/safety', label: 'Read Hocalist’s meetup and safety guidance' }
  }
];

export function blogPostPath(slug: string) {
  return `/blog/${slug}`;
}
