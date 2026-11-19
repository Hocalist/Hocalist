-- Add real choices without modifying existing requests or their historical labels.
INSERT INTO hocalist.catalogue_categories(label,slug,scope,sort_order)
SELECT v.label,v.slug,v.scope,v.ord FROM (VALUES
 ('Electronics','electronics','product',10),('Home & furniture','home-furniture','product',20),
 ('Clothing & accessories','clothing-accessories','product',30),('Sports & outdoors','sports-outdoors','product',40),
 ('Tools & equipment','tools-equipment','product',50),('Cleaning','cleaning','service',10),
 ('Home repairs','home-repairs','service',20),('Lawn & garden care','lawn-garden-care','service',30),
 ('Moving & delivery','moving-delivery','service',40),('Tech support','tech-support','service',50)
) v(label,slug,scope,ord)
WHERE NOT EXISTS (SELECT 1 FROM hocalist.catalogue_categories c WHERE lower(c.label)=lower(v.label) AND c.scope IN (v.scope,'both'))
ON CONFLICT (slug) WHERE slug IS NOT NULL DO NOTHING;

-- Keep historical category IDs available to requests already using them.
UPDATE hocalist.catalogue_categories SET status = 'retired'
WHERE status = 'active' AND (label, scope) IN
  (('TEST - Home products', 'product'), ('TEST - Home services', 'service'));
