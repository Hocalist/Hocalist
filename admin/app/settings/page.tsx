import { AdministratorAccess } from './administrator-access';
import { AuthenticatorSetup } from './authenticator-setup';
import { AdminShell, PageHeader } from '../components';
import { CallAuditPanel } from '../call-audit-panel';
import { ReasonSettings } from './reason-settings';
import { CallSettings } from './call-settings';
export const dynamic='force-dynamic';
export default function Settings(){return <AdminShell><PageHeader title="Settings" description="Protect administrator access and manage support settings."/><AuthenticatorSetup/><AdministratorAccess/><CallSettings/><CallAuditPanel/><ReasonSettings/></AdminShell>;}
