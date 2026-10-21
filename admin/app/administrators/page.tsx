import { AdminShell, PageHeader } from '../components';
import { AdministratorAccess } from '../settings/administrator-access';
export const dynamic='force-dynamic';
export default function Administrators(){return <AdminShell><PageHeader title="Administrators" description="Manage who can help run Hocalist."/><AdministratorAccess/></AdminShell>;}
