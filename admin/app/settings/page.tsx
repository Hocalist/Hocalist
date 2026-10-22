import Link from 'next/link';
import { AdminShell, PageHeader } from '../components';
import { CallAuditPanel } from '../call-audit-panel';
import { ReasonSettings } from './reason-settings';
import { CallSettings } from './call-settings';
import { SectionTabs } from '../section-tabs';
export const dynamic='force-dynamic';
export default function Settings(){return <AdminShell><PageHeader title="Settings" description="Manage account security and support settings."/><SectionTabs label="Settings sections" sections={[{title:"Account security",content:<section className="panel administrator-access"><h2>Account security</h2><p>Your sign-in is protected by your password and an authenticator code. You do not need to set up your authenticator again here.</p><p>To give someone access to this portal, go to <Link href="/administrators">Administrators</Link>.</p></section>},{title:"Report reasons",content:<ReasonSettings/>},{title:"Call & support",content:<><CallSettings/><CallAuditPanel/></>}]} /></AdminShell>;}
