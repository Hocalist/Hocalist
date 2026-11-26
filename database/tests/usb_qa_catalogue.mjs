const product = [
  ['Electronics', 'electronics', 'Phones & tablets|Computers & monitors|TVs & audio|Cameras|Gaming', 'Included accessories', 'Device only|Original accessories|Accessories optional|Not sure'],
  ['Furniture & home décor', 'home-furniture', 'Sofas & chairs|Beds & mattresses|Tables & desks|Storage|Lighting & décor', 'Preferred size', 'Compact|Standard|Large|Flexible'],
  ['Appliances & kitchen', 'appliances-kitchen', 'Refrigerators & freezers|Washers & dryers|Stoves & ovens|Small appliances|Cookware', 'Installation style', 'Freestanding|Built-in|Countertop|Flexible'],
  ['Tools & equipment', 'tools-equipment', 'Power tools|Hand tools|Ladders|Workshop equipment|Generators', 'What should be included?', 'Item only|Accessories or attachments|Complete kit|Flexible'],
  ['Lawn & garden', 'lawn-garden', 'Mowers & trimmers|Gardening tools|Planters|Patio furniture|Grills', 'How much space do you have?', 'Small yard or balcony|Medium yard|Large yard|Flexible'],
  ['Sports & outdoors', 'sports-outdoors', 'Bikes|Fitness equipment|Team sports|Camping|Fishing & boating gear', 'Intended use', 'Beginner or casual|Regular use|Competitive or specialist|Flexible'],
  ['Auto parts & accessories', 'auto-parts-accessories', 'Tires & wheels|Replacement parts|Car audio|Racks & carriers|Interior accessories', 'Fit requirements', 'Exact vehicle fit|Universal fit|Help checking fit'],
  ['Baby & kids', 'baby-kids', 'Strollers|Nursery furniture|Toys & games|School supplies|Kids’ clothing', 'Age range', 'Baby|Toddler|School age|Teen|Flexible'],
  ['Clothing & accessories', 'clothing-accessories', 'Clothing|Shoes|Bags|Watches & jewelry|Workwear', 'Preferred style', 'Everyday|Dressy|Sport or outdoor|Work|Flexible'],
  ['Hobbies & collectibles', 'hobbies-collectibles', 'Musical instruments|Books & media|Arts & crafts|Collectibles|Sewing equipment', 'What are you looking for?', 'Starter item|Specific model or edition|Set or bundle|Flexible'],
  ['Other product', 'other-product', '', 'Brand or model preference', 'Specific item|Comparable alternatives welcome|Any brand or model'],
];

const service = [
  ['Cleaning', 'cleaning', 'House cleaning|Deep cleaning|Move-in or move-out cleaning|Office cleaning|Carpet & upholstery cleaning', 'How many rooms?', '1 room|2–3 rooms|4–5 rooms|6+ rooms'],
  ['Home repairs & installation', 'home-repairs', 'Handyman|Painting|Drywall|Furniture assembly|TV mounting', 'Job size', 'One item or area|Several items or areas|Whole project|Need an estimate'],
  ['Plumbing, electrical & HVAC', 'plumbing-electrical-hvac', 'Plumbing|Electrical work|Air conditioning & heating|Appliance repair', 'What kind of help?', 'Diagnose a problem|Repair|Replace or install|Routine maintenance'],
  ['Lawn & outdoor care', 'lawn-garden-care', 'Lawn mowing|Landscaping|Tree trimming|Pressure washing|Yard cleanup', 'Outdoor area size', 'Small|Medium|Large|Need an estimate'],
  ['Moving, delivery & junk removal', 'moving-delivery', 'Local moving|Furniture pickup|Delivery|Junk removal|Donation hauling', 'How much needs to be moved?', 'One item|A few items|One room|Multiple rooms'],
  ['Auto & bike services', 'auto-bike-services', 'Auto detailing|Mobile mechanic|Tire service|Bicycle repair', 'Where should the service happen?', 'At my location|At the shop|Either works'],
  ['Tech support & setup', 'tech-support', 'Computer repair|Phone repair|Wi-Fi setup|Smart-home installation', 'What kind of help?', 'Set up something new|Fix a problem|Improve an existing setup|Help figuring it out'],
  ['Events & creative services', 'events-creative-services', 'Photography|Videography|DJs|Event setup|Graphic design', 'Project type', 'Personal event or project|Business event or project|Community event or project|Other'],
  ['Lessons & coaching', 'lessons-coaching', 'Tutoring|Music lessons|Language lessons|Fitness coaching', 'Experience level', 'Beginner|Intermediate|Advanced|Mixed or unsure'],
  ['Pet care', 'pet-care', 'Dog walking|Pet sitting|Grooming|Pet training', 'Which pet needs care?', 'Dog|Cat|More than one pet|Other pet'],
  ['Other service', 'other-service', '', 'How often do you need it?', 'One time|Recurring|Still deciding'],
];

const specific = {
  'Phones & tablets': [
    ['Device type', 'Phone|Tablet|Either'],
    ['Carrier preference', 'Unlocked|Specific carrier|Wi-Fi only|Flexible'],
  ],
  'Refrigerators & freezers': [['Appliance type', 'Refrigerator|Freezer|Refrigerator with freezer|Flexible']],
  Cookware: [['Cooktop compatibility', 'Induction|Gas|Electric|Any']],
  Bikes: [['Bike style', 'Road|Mountain|Hybrid|Electric|Kids|Flexible']],
  'Tires & wheels': [['What do you need?', 'Tires only|Wheels only|Tires and wheels|Flexible']],
  Shoes: [['Size preference', 'Exact size|Nearby sizes may work|Still deciding']],
  'Sewing equipment': [['Equipment type', 'Sewing machine|Serger|Embroidery machine|Tools or supplies']],
  'Carpet & upholstery cleaning': [['What needs cleaning?', 'Carpet or rugs|Upholstery|Both']],
  'TV mounting': [['Wall surface', 'Drywall|Brick or concrete|Other|Not sure']],
  'Local moving': [['Move size', 'A few items|Studio or one bedroom|Two to three bedrooms|Four or more bedrooms']],
  'Junk removal': [['What needs removal?', 'Furniture|Appliances|Yard debris|Mixed items']],
  'Auto detailing': [['Detailing area', 'Interior|Exterior|Both']],
  'Wi-Fi setup': [['What do you need?', 'New network|Better coverage|Troubleshoot connection|Not sure']],
  'Graphic design': [['What do you need designed?', 'Logo or brand assets|Social media graphics|Print materials|Other']],
  'Pet sitting': [['Care arrangement', 'Drop-in visits|Overnight care|Boarding|Flexible']],
};

const slugify = (label) => label.normalize('NFD').replace(/\p{Mark}/gu, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

async function seedQuestions(db, categoryId, questions) {
  for (const [index, [label, values]] of questions.entries()) {
    const { rows: [{ id }] } = await db.query(
      'INSERT INTO hocalist.catalogue_option_groups(category_id,label,selection_mode,sort_order) VALUES($1,$2,$3,$4) RETURNING id',
      [categoryId, label, 'single', index],
    );
    await db.query(
      'INSERT INTO hocalist.catalogue_options(group_id,label,sort_order) SELECT $1, label, position FROM unnest($2::text[]) WITH ORDINALITY AS choices(label,position)',
      [id, values.split('|')],
    );
  }
}

export async function seedUsbQaCatalogue(db) {
  for (const [scope, categories] of [['product', product], ['service', service]]) {
    for (const [index, [label, slug, children, question, values]] of categories.entries()) {
      const { rows: [{ id: parentId }] } = await db.query(
        'INSERT INTO hocalist.catalogue_categories(label,slug,scope,sort_order) VALUES($1,$2,$3,$4) ON CONFLICT (slug) WHERE slug IS NOT NULL DO UPDATE SET label=EXCLUDED.label, sort_order=EXCLUDED.sort_order RETURNING id',
        [label, slug, scope, (index + 1) * 10],
      );
      const leaves = children ? children.split('|') : [label];
      for (const [order, leaf] of leaves.entries()) {
        let categoryId = parentId;
        if (children) {
          const result = await db.query(
            'INSERT INTO hocalist.catalogue_categories(parent_id,label,slug,scope,sort_order) VALUES($1,$2,$3,$4,$5) RETURNING id',
            [parentId, leaf, slug + '-' + slugify(leaf), scope, order + 1],
          );
          categoryId = result.rows[0].id;
        }
        const questions = [...(specific[leaf] ?? [[question, values]])];
        if (scope === 'service') {
          questions.push(['When do you need it?', 'As soon as possible|This week|Next week|Flexible']);
        }
        await seedQuestions(db, categoryId, questions);
      }
    }
  }
}
