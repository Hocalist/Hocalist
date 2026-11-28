import 'server-only';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parseFinanceReport } from './finance-report';

export async function loadFinanceReview() {
  if (process.env.NODE_ENV !== 'development' || process.env.HOCALIST_ADMIN_FINANCE_PREVIEW !== 'true') return null;
  try {
    const file = await readFile(join(process.cwd(), '.finance-review.local.json'), 'utf8');
    const data = JSON.parse(file);
    const report = parseFinanceReport(data.report);
    if (!report || typeof data.capturedAt !== 'string' || !Number.isFinite(Date.parse(data.capturedAt)) ||
      !Number.isSafeInteger(data.sandboxPaidPayouts) || data.sandboxPaidPayouts < 0) return null;
    return { report, capturedAt: data.capturedAt as string, sandboxPaidPayouts: data.sandboxPaidPayouts as number };
  } catch {
    return null;
  }
}
