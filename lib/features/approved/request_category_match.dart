import '../../data/local_marketplace_repository.dart';

// Helpful search terms for the current catalogue. A term can only select an
// active category returned by the server. New categories also match by label.
const _aliases = <String, String>{
  'phones tablets': 'phone|tablet|iphone|ipad|galaxy tab|smartphone|cellphone|android',
  'computers monitors': 'computer|laptop|macbook|desktop|monitor|chromebook',
  'tvs audio': 'tv|television|smart tv',
  'audio equipment': 'soundbar|speaker|headphones|stereo|receiver',
  'cameras': 'camera|dslr|mirrorless|gopro|camcorder',
  'gaming': 'console|playstation|xbox|nintendo switch|game controller',
  'sofas chairs': 'sofa|couch|loveseat|sectional|sleeper sofa',
  'chairs recliners': 'chair|recliner|armchair|accent chair|dining chair',
  'beds mattresses': 'bed|mattress|bed frame|bunk bed|box spring',
  'tables desks': 'table|desk|end table|tv stand|dining table',
  'storage': 'dresser|bookcase|bookshelf|cabinet|shelving|wardrobe',
  'lighting decor': 'lamp|chandelier|mirror|wall art|rug',
  'refrigerators freezers': 'fridge|freezer|refrigerator|mini fridge',
  'washers dryers': 'washer|dryer|washing machine|laundry machine',
  'stoves ovens': 'stove|oven|cooktop|range hood',
  'small appliances': 'air fryer|microwave|blender|toaster|coffee maker|mixer',
  'cookware': 'frying pan|skillet|pot|saucepan|dutch oven',
  'power tools': 'power drill|drill|impact driver|circular saw|sander|jigsaw',
  'hand tools': 'hammer|wrench|screwdriver|pliers|socket set',
  'ladders': 'ladder|stepladder',
  'workshop equipment': 'workbench|air compressor|vise|table saw|welder',
  'generators': 'generator|power station',
  'mowers trimmers': 'mower|lawnmower|weed eater|string trimmer',
  'gardening tools': 'shovel|rake|pruner|garden hose|wheelbarrow',
  'planters': 'planter|plant pot|raised garden bed',
  'patio furniture': 'patio set|outdoor sofa|outdoor chair|patio umbrella',
  'grills': 'grill|barbecue|smoker|bbq',
  'bikes': 'bike|bicycle|ebike|mountain bike|road bike',
  'fitness equipment':
      'treadmill|dumbbell|kettlebell|exercise bike|weight bench',
  'team sports':
      'baseball glove|hockey skates|volleyball net|pickleball paddle|basketball|soccer ball',
  'camping': 'tent|sleeping bag|camp stove|camping chair',
  'fishing boating gear': 'fishing rod|tackle box|kayak|canoe|life jacket',
  'tires wheels': 'tire|tyre|rim|car wheels',
  'replacement parts': 'alternator|brake pads|radiator|spark plugs|car battery',
  'car audio': 'car stereo|car speaker|car subwoofer',
  'racks carriers': 'roof rack|bike rack|cargo carrier|hitch rack',
  'interior accessories':
      'floor mat|seat cover|cargo liner|steering wheel cover',
  'strollers': 'stroller|pram|pushchair',
  'nursery furniture': 'crib|bassinet|changing table|toddler bed',
  'toys games': 'toy|lego|doll|board game|puzzle',
  'school supplies': 'notebook|pencil case|school supplies',
  'kids clothing': 'kids clothes|baby clothes|onesie|school uniform',
  'clothing': 'shirt|dress|jeans|jacket|coat|pants|blouse',
  'shoes': 'shoe|sneakers|boots|sandals|heels',
  'bags': 'bag|backpack|handbag|purse|suitcase',
  'watches jewelry': 'watch|ring|necklace|earrings|bracelet|jewellery',
  'workwear': 'work boots|scrubs|work uniform|safety vest',
  'musical instruments': 'guitar|piano|violin|drum kit|trumpet',
  'books media': 'book|novel|dvd|vinyl record|comic book',
  'arts crafts': 'paintbrush|knitting needles|yarn|art supplies|craft kit',
  'collectibles':
      'trading cards|collectible figures|pokemon cards|coins|stamps',
  'sewing equipment': 'sewing machine|serger|embroidery machine',
  'house cleaning': 'house cleaner|home cleaning|clean my house|maid',
  'deep cleaning': 'deep clean|deep cleaner',
  'move in or move out cleaning':
      'move out cleaning|move in cleaning|end of lease cleaning',
  'office cleaning': 'office cleaner|janitorial|commercial cleaning',
  'carpet upholstery cleaning':
      'carpet cleaning|couch cleaning|sofa cleaning|rug cleaning',
  'handyman': 'handyperson|general repairs|odd jobs',
  'painting': 'painter|house painting|paint a room|exterior paint',
  'drywall': 'drywall repair|sheetrock|patch a wall',
  'furniture assembly':
      'assemble furniture|ikea assembly|put furniture together',
  'tv mounting':
      'mount tv|mount a tv|mount my tv|tv installation|wall mount tv',
  'plumbing': 'plumber|leaky faucet|clogged drain|toilet repair',
  'electrical work': 'electrician|outlet repair|light fixture installation',
  'air conditioning heating':
      'hvac|ac repair|furnace repair|air conditioner repair',
  'appliance repair':
      'fix my washer|washer repair|refrigerator repair|fridge repair',
  'lawn mowing': 'mow lawn|cut grass|grass cutting|lawn service',
  'landscaping': 'landscaper|garden design|lay sod',
  'tree trimming': 'tree removal|arborist|tree pruning',
  'pressure washing': 'power washing|pressure wash|power wash',
  'yard cleanup': 'leaf removal|yard waste|yard clean up',
  'local moving': 'movers|moving help|moving truck|apartment move',
  'furniture pickup': 'pick up furniture|couch pickup|sofa pickup',
  'delivery': 'courier|same day delivery|package delivery',
  'junk removal': 'haul junk|trash hauling|remove junk|junk hauling|haul away|furniture disposal',
  'donation hauling': 'donation pickup|donate furniture',
  'auto detailing': 'car detailing|detail my car|car cleaning|mobile detailing',
  'mobile mechanic': 'mechanic|car repair|auto repair',
  'tire service': 'tire repair|flat tire|tire installation|wheel alignment',
  'bicycle repair': 'bike repair|bike tune up|fix my bike',
  'computer repair': 'laptop repair|fix my computer|pc repair',
  'phone repair': 'screen repair|iphone repair|fix my phone',
  'wi fi setup': 'wifi setup|wi fi installation|router setup|home internet',
  'smart home installation':
      'smart home setup|smart doorbell|smart thermostat installation',
  'photography': 'photographer|photo shoot|family photos',
  'videography': 'videographer|video shoot|video editing',
  'djs': 'dj|disc jockey',
  'event setup': 'party setup|event decorating|party decorating',
  'graphic design': 'graphic designer|logo design|design a logo|flyer design',
  'tutoring': 'tutor|math help|test prep',
  'music lessons': 'guitar lessons|piano lessons|voice lessons',
  'language lessons': 'spanish lessons|english lessons|language tutor',
  'fitness coaching': 'personal trainer|fitness trainer|workout coach',
  'dog walking': 'dog walker|walk my dog',
  'pet sitting': 'pet sitter|dog sitter|cat sitting|dog boarding',
  'grooming': 'groomer|dog grooming|cat grooming',
  'pet training': 'dog trainer|dog training|obedience training',
};

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('é', 'e')
    .replaceAll(RegExp(r'[’\x27]'), '')
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .trim();

Iterable<String> _categoryTerms(String label) sync* {
  final normalized = _normalize(label);
  yield normalized;
  yield* label.split(RegExp(r'\s+(?:&|or)\s+|,')).map(_normalize);
  yield* _aliases[normalized]?.split('|') ?? const <String>[];
}

bool requestCategoryMatchesSearch(String label, String search) {
  final query = _normalize(search);
  if (query.isEmpty) return true;
  final terms = _categoryTerms(label).join(' ');
  return query.split(' ').every(terms.contains);
}

CatalogueCategoryOption? matchRequestCategory(
  String title,
  List<CatalogueCategoryOption> categories, {
  required bool product,
}) {
  final query = _normalize(title);
  if (query.length < 2) return null;
  final words = query.split(' ').toSet();
  final eligible = categories
      .where(
        (c) => c.isActive && (product ? c.supportsProduct : c.supportsService),
      )
      .toList();
  final parents = eligible.map((c) => c.parentId).whereType<String>().toSet();
  CatalogueCategoryOption? best;
  var bestScore = 0;
  for (final category in eligible) {
    if (parents.contains(category.id)) continue;
    var score = 0;
    for (final term in _categoryTerms(category.label)) {
      if (term.length < 2) continue;
      final exact = term == query;
      final contains = ' $query '.contains(' $term ');
      final plural =
          !term.contains(' ') &&
          (words.contains('${term}s') || words.contains('${term}es'));
      final candidate = exact
          ? 100 + term.length
          : contains || plural
          ? 20 + term.split(' ').length * 18
          : 0;
      if (candidate > score) score = candidate;
    }
    if (score > bestScore) {
      bestScore = score;
      best = category;
    } else if (score != 0 && score == bestScore) {
      best = null;
    }
  }
  return best;
}
