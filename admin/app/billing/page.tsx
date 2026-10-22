import Link from "next/link";
import { AdminShell, PageHeader } from "../components";
import { LedgerPanel } from "../ledger-panel";
import { RecordsPanel } from "../records-panel";
import { RECORDS } from "../lib/admin-records";
import { SectionTabs } from "../section-tabs";
export const dynamic = "force-dynamic";
export default function Page() {
 const definition=RECORDS.billing;
 return <AdminShell><PageHeader title={definition.title} description={definition.description}/><p><Link href="/billing/config">Deposit options and buyer reward policy →</Link></p><SectionTabs label="Billing sections" sections={[{title:"Subscriptions",content:<RecordsPanel resource="billing"/>},{title:"Credits & rewards",content:<LedgerPanel/>}]}/></AdminShell>;
}
