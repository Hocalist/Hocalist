import { AdminShell, PageHeader } from '../components';
import { SupportPanel } from './support-panel';
export const dynamic = 'force-dynamic';
export default function Reports(){return <AdminShell><PageHeader title="Reports & support" description="Review submitted concerns and send a response visible to the reporter. Reports do not automatically penalize accounts."/><SupportPanel/></AdminShell>;}
