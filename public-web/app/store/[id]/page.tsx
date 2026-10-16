import Link from 'next/link';
import { OfflineNotice, PageShell } from '../../site-content';
import { loadPublicStore } from '../../lib/public-store';
import { siteConfig } from '../../lib/website-session';

export const dynamic='force-dynamic';
export const metadata={title:'Seller Store | Hocalist',robots:{index:false,follow:false}};
export default async function StorePage({params}:{params:Promise<{id:string}>}) {
  const {id}=await params;
  const store=await loadPublicStore(id,siteConfig());
  return <PageShell><main>
    <section className="subpage-hero">
      <p className="eyebrow">Hocalist seller Store</p>
      <h1>{store?.available?store.name:'Seller Store'}</h1>
      <p>{store===null?'This Store could not be loaded. Please try again shortly.':store.available?store.area||'Published products and services.':'This Store has no public listings available.'}</p>
      <Link className="button primary" href="/download">Open Hocalist</Link>
    </section>
    {store?.available && <section className="page-section"><div className="feature-grid">{store.items.map(item=><article className="feature-card" key={item.id}>
      <p className="eyebrow">{item.kind==='service'?'Service':'Product'}{item.category_label?` · ${item.category_label}`:''}</p>
      <h2>{item.title}</h2><p>{item.description}</p><strong>{item.price_label}</strong>{item.service_area&&<p>{item.service_area}</p>}
    </article>)}</div></section>}
    <section className="page-section"><OfflineNotice/></section>
  </main></PageShell>;
}
