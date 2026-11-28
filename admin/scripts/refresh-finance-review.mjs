import { randomUUID } from 'node:crypto';
import { readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { parseFinanceReport } from '../app/lib/finance-report.ts';

const snapshot = new URL('../.finance-review.local.json', import.meta.url);
process.stdin.setEncoding('utf8');
let payload = '';
for await (const chunk of process.stdin) payload += chunk;
const incoming = JSON.parse(payload);
const previous = JSON.parse(await readFile(snapshot, 'utf8'));
const report = parseFinanceReport(incoming.report);
if (!report || !Number.isFinite(Date.parse(incoming.capturedAt)) ||
    !/^[0-9a-f]{32}$/.test(incoming.invoiceFingerprint ?? '') ||
    !Number.isSafeInteger(incoming.sandboxPaidPayouts) || incoming.sandboxPaidPayouts < 0) {
  throw new Error('Unexpected finance review response.');
}
if (Date.parse(incoming.capturedAt) <= Date.parse(previous.capturedAt)) {
  console.log('The current finance snapshot is already up to date.');
  process.exit(0);
}

if (incoming.invoiceFingerprint === previous.invoiceFingerprint) {
  for (const month of report.months) {
    const reconciled = previous.report.months.find(row => row.month === month.month);
    if (reconciled?.totals?.subscriptions == null) continue;
    month.totals = {
      subscriptions: reconciled.totals.subscriptions,
      targeting: null, confirmation: null, stripeFees: null,
      refunds: null, rewardsEarned: null, overhead: null,
    };
    month.note = reconciled.note;
  }
}

const temporary = new URL(`../.finance-review.${randomUUID()}.tmp`, import.meta.url);
try {
  await writeFile(temporary, JSON.stringify({
    capturedAt: incoming.capturedAt, invoiceFingerprint: incoming.invoiceFingerprint,
    sandboxPaidPayouts: incoming.sandboxPaidPayouts, report,
  }), { encoding: 'utf8', flag: 'wx' });
  await rename(temporary, snapshot);
} finally {
  await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
}
