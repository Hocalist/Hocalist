import { AdminShell, PageHeader } from "../components";
import { OverviewPanel } from "../overview-panel";
export const dynamic="force-dynamic";
export default function Dashboard(){return <AdminShell><PageHeader title="Dashboard overview" description="Current Hocalist marketplace records and review queues."/><OverviewPanel/></AdminShell>;}
