const product = [
  ['Electronics', 'electronics', 'Phones & tablets|Computers & monitors|TVs & audio|Audio equipment|Cameras|Gaming', 'Included accessories', 'Device only|Original accessories|Accessories optional|Not sure'],
  ['Furniture & home décor', 'home-furniture', 'Sofas & chairs|Chairs & recliners|Beds & mattresses|Tables & desks|Storage|Lighting & décor', 'Preferred size', 'Compact|Standard|Large|Flexible'],
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
  'TVs & audio': [
    ['Screen size', '32–43 inches|50–55 inches|60–65 inches|70–75 inches|77 inches or larger'],
    ['Brand', 'Samsung|LG|Sony|TCL|Hisense|Vizio|Other brand'],
    ['Resolution', '1080p|4K|8K'],
    ['Smart TV', 'Yes|No'],
  ],
  'Audio equipment': [['Equipment type', 'Soundbar|Speakers|Headphones|Stereo or receiver'], ['Connection', 'Wired|Bluetooth|Wi-Fi']],
  'Sofas & chairs': [
    ['Couch type', 'Sofa|Sectional|Loveseat|Sleeper sofa|Reclining sofa'],
    ['Width', 'Under 70 inches|70–89 inches|90–109 inches|110 inches or wider'],
    ['Color', 'Gray|Beige|Black|Brown|Blue|Green|Other color'],
    ['Upholstery', 'Fabric|Leather|Faux leather|Velvet|Microfiber'],
  ],
  'Chairs & recliners': [['Chair type', 'Armchair|Recliner|Accent chair|Dining chair'], ['Upholstery', 'Fabric|Leather|Wood or metal|Other']],
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
  'Computers & monitors': [['Computer or display', 'Laptop|Desktop|Monitor'], ['Intended use', 'School or office|Gaming|Creative work']],
  Cameras: [['Camera type', 'DSLR|Mirrorless|Compact|Action camera|Video camera']],
  Gaming: [['Platform', 'PlayStation|Xbox|Nintendo|PC|Other']],
  'Beds & mattresses': [['Bed size', 'Twin|Full|Queen|King|California king']],
  'Tables & desks': [['Table type', 'Dining table|Desk|Coffee table|Side table|TV stand']],
  Storage: [['Storage type', 'Dresser|Bookcase|Cabinet|Shelving|Wardrobe']],
  'Lighting & décor': [['Décor type', 'Lamp|Ceiling light|Mirror|Wall art|Rug']],
  'Washers & dryers': [['Appliance type', 'Washer|Dryer|Washer and dryer'], ['Layout', 'Front load|Top load|Stackable']],
  'Stoves & ovens': [['Fuel or power', 'Gas|Electric|Induction|Dual fuel']],
  'Small appliances': [['Appliance type', 'Microwave|Air fryer|Blender|Coffee maker|Toaster|Other']],
  'Power tools': [['Power source', 'Corded|Cordless|Pneumatic']],
  'Hand tools': [['Tool format', 'Individual tool|Set|Complete kit']],
  Ladders: [['Ladder type', 'Step ladder|Extension ladder|Multi-position'], ['Height', 'Under 8 feet|8–16 feet|Over 16 feet']],
  'Workshop equipment': [['Workshop task', 'Cutting|Air tools|Welding|Clamping|Work surface']],
  Generators: [['Power source', 'Gasoline|Propane|Dual fuel|Battery or solar']],
  'Mowers & trimmers': [['Equipment type', 'Push mower|Riding mower|String trimmer|Edger'], ['Power source', 'Gas|Corded|Battery']],
  'Gardening tools': [['Garden task', 'Digging|Pruning|Watering|Hauling|Raking']],
  Planters: [['Planter material', 'Ceramic|Plastic|Wood|Metal|Fabric']],
  'Patio furniture': [['Furniture type', 'Dining set|Outdoor seating|Umbrella or shade|Lounger']],
  Grills: [['Fuel type', 'Gas|Charcoal|Pellet|Electric']],
  'Fitness equipment': [['Training type', 'Cardio|Strength training|Mobility|Home gym']],
  'Team sports': [['Sport', 'Baseball or softball|Basketball|Soccer|Hockey|Volleyball|Pickleball|Other']],
  Camping: [['Camping gear', 'Shelter|Sleeping gear|Cooking gear|Other']],
  'Fishing & boating gear': [['Water type', 'Freshwater|Saltwater|Both']],
  'Replacement parts': [['Part system', 'Engine|Brakes|Cooling|Electrical|Other']],
  'Car audio': [['Component', 'Stereo|Speakers|Amplifier|Subwoofer']],
  'Racks & carriers': [['Mounting style', 'Roof|Hitch|Trunk|Truck bed']],
  'Interior accessories': [['Accessory type', 'Floor mats|Seat covers|Cargo liner|Other']],
  Strollers: [['Stroller type', 'Single|Double|Jogging|Travel system']],
  'Nursery furniture': [['Furniture type', 'Crib|Bassinet|Changing table|Toddler bed']],
  'Toys & games': [['Age range', 'Baby|Toddler|School age|Teen']],
  'School supplies': [['Supply type', 'Writing supplies|Notebooks|Classroom materials|Other']],
  'Kids’ clothing': [['Age range', 'Baby|Toddler|School age|Teen']],
  Clothing: [['Clothing size', 'XS|S|M|L|XL|2XL or larger|Other']],
  Bags: [['Bag type', 'Backpack|Handbag|Duffel|Suitcase|Other']],
  'Watches & jewelry': [['Item type', 'Watch|Ring|Necklace|Earrings|Bracelet']],
  Workwear: [['Workwear type', 'Uniform|Scrubs|Safety apparel|Work boots']],
  'Musical instruments': [['Instrument family', 'Strings|Keys|Percussion|Brass or woodwind']],
  'Books & media': [['Format', 'Book|DVD or Blu-ray|Vinyl|CD|Other']],
  'Arts & crafts': [['Craft type', 'Drawing or painting|Knitting or crochet|Paper crafts|Other']],
  Collectibles: [['Collectible type', 'Cards|Figures|Coins or stamps|Memorabilia|Other']],
  'House cleaning': [['How many rooms?', '1 room|2–3 rooms|4–5 rooms|6+ rooms']],
  'Deep cleaning': [['Priority areas', 'Kitchen and baths|Bedrooms and living areas|Whole property']],
  'Move-in or move-out cleaning': [['Move timing', 'Before move-in|After move-out'], ['Property type', 'Apartment or condo|House|Other']],
  'Office cleaning': [['Office size', 'Small office|Several rooms|Multiple floors'], ['Frequency', 'One time|Weekly|Other recurring']],
  Handyman: [['Job type', 'Small repairs|Install fixtures|Maintenance|Several tasks']],
  Painting: [['Paint area', 'Interior|Exterior|Both']],
  Drywall: [['Drywall work', 'Patch a hole|Repair water damage|Hang new drywall']],
  'Furniture assembly': [['Furniture type', 'Table or desk|Bed|Storage or shelving|Other']],
  Plumbing: [['Plumbing issue', 'Leak|Clog|Fixture installation|Water heater|Other']],
  'Electrical work': [['Electrical task', 'Outlet or switch|Lighting|Wiring|Other']],
  'Air conditioning & heating': [['HVAC task', 'Cooling repair|Heating repair|Maintenance|New installation']],
  'Appliance repair': [['Appliance', 'Refrigerator|Washer or dryer|Stove or oven|Dishwasher|Other']],
  'Lawn mowing': [['Mowing frequency', 'One time|Weekly|Every other week']],
  Landscaping: [['Landscaping work', 'Planting|Sod|Garden design|Hardscape|Other']],
  'Tree trimming': [['Tree work', 'Pruning|Tree removal|Stump grinding|Estimate']],
  'Pressure washing': [['Surface', 'Driveway or walkway|Siding|Deck or patio|Other']],
  'Yard cleanup': [['Clean-up type', 'Leaves|Brush|Storm debris|General cleanup']],
  'Furniture pickup': [['Pickup size', 'One small item|One large item|Multiple items']],
  Delivery: [['Delivery size', 'Envelope or package|Bulky item|Multiple items']],
  'Donation hauling': [['Donation type', 'Furniture|Clothing or boxes|Appliances|Mixed items']],
  'Mobile mechanic': [['Vehicle service', 'Diagnostic|Battery|Brakes|Routine maintenance|Other']],
  'Tire service': [['Tire work', 'Repair|Replace|Rotate|Balance']],
  'Bicycle repair': [['Bike work', 'Tune-up|Flat tire|Brakes|Gears or chain']],
  'Computer repair': [['Computer issue', 'Power or startup|Screen|Slow performance|Software|Other']],
  'Phone repair': [['Phone issue', 'Screen|Battery|Charging port|Water damage|Other']],
  'Smart-home installation': [['Device type', 'Doorbell or camera|Thermostat|Lighting|Smart speaker|Other']],
  Photography: [['Photo session', 'Portrait|Event|Product|Real estate']],
  Videography: [['Video work', 'Film an event|Business video|Editing only|Other']],
  DJs: [['Event type', 'Wedding|Private party|Corporate event|Other']],
  'Event setup': [['Setup needs', 'Tables and chairs|Décor|Tent|Full setup']],
  Tutoring: [['Subject', 'Math|Reading or writing|Science|Test prep|Other']],
  'Music lessons': [['Instrument', 'Piano|Guitar|Voice|Drums|Other']],
  'Language lessons': [['Language', 'English|Spanish|French|Other']],
  'Fitness coaching': [['Training goal', 'Strength|General fitness|Mobility|Sport-specific']],
  'Dog walking': [['Walk duration', '15 minutes|30 minutes|60 minutes']],
  Grooming: [['Grooming service', 'Bath|Haircut|Nail trim|Full grooming']],
  'Pet training': [['Training goal', 'Basic obedience|Puppy training|Leash skills|Behavior support']],
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
