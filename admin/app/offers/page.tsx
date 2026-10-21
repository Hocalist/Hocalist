import { AdminShell, PageHeader } from "../components";
import { RecordsPanel } from "../records-panel";
import { RECORDS } from "../lib/admin-records";
export const dynamic = "force-dynamic";
export default function Page() {
 const definition=RECORDS.offers;
 return <AdminShell><PageHeader title={definition.title} description={definition.description}/><RecordsPanel resource="offers"/></AdminShell>;
}
