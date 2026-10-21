// Server-side typed loaders for the admin configuration pages.
//
// Every loader passes the centralized session admission (policy enforcement and
// provider validation when required) before it reads. Rotation is not attempted
// during a render: a single-use refresh token must not be consumed without a
// response that can persist its replacement. The middleware refresh route
// performs that recovery before the page is rendered.
import { cookies } from "next/headers";

import { loadAdminDataCore, type SessionLoad } from "./admin-http";
import { adminMfaPolicy } from "./admin-rules";
import { adminConfig, SESSION_COOKIE } from "./admin-session";

export type AdminLoad<T> = SessionLoad<T>;

export type AdminCatalogueOption = {
  id: string;
  group_id: string;
  label: string;
  status: string;
  sort_order: number;
  revision: number;
};

export type AdminCatalogueGroup = {
  id: string;
  category_id: string;
  label: string;
  selection_mode: string;
  is_required: boolean;
  status: string;
  sort_order: number;
  revision: number;
  options: AdminCatalogueOption[];
};

export type AdminCatalogueCategory = {
  id: string;
  parent_id: string | null;
  label: string;
  slug: string | null;
  scope: string;
  status: string;
  sort_order: number;
  revision: number;
  groups: AdminCatalogueGroup[];
};

export type AdminLocation = {
  id: string;
  country_code: string;
  region: string | null;
  city: string | null;
  label: string;
  status: string;
  sort_order: number;
  revision: number;
  timezone_id: string | null;
};

export type AdminListing = {
  id: string;
  seller_user_id: string;
  kind: string;
  title: string;
  category_label: string;
  price_label: string;
  status: string;
  moderation_status: string;
  revision: number;
  created_at: string;
};

async function sessionToken(): Promise<string | null> {
  const store = await cookies();
  return store.get(SESSION_COOKIE)?.value ?? null;
}

async function load<T>(
  functionName: string,
  params: Record<string, unknown>,
): Promise<AdminLoad<T>> {
  const config = adminConfig();
  if (!config) return { state: "unconfigured" };
  const token = await sessionToken();
  if (!token) return { state: "signed_out" };
  return loadAdminDataCore<T>({
    config,
    policy: adminMfaPolicy(process.env.HOCALIST_ADMIN_MFA),
    accessToken: token,
    functionName,
    params,
    nowSeconds: Math.floor(Date.now() / 1000),
  });
}

export async function loadCatalogue(): Promise<
  AdminLoad<AdminCatalogueCategory[]>
> {
  const result = await load<{ categories: AdminCatalogueCategory[] }>(
    "marketplace_catalogue",
    { p_scope: null, p_include_retired: true },
  );
  if (result.state !== "ok") return result;
  return { state: "ok", data: result.data.categories ?? [] };
}

export async function loadLocations(): Promise<AdminLoad<AdminLocation[]>> {
  const result = await load<{ items: AdminLocation[] }>(
    "marketplace_locations",
    { p_country: null, p_include_retired: true },
  );
  if (result.state !== "ok") return result;
  return { state: "ok", data: result.data.items ?? [] };
}

export async function loadTimezones(): Promise<AdminLoad<string[]>> {
  const result = await load<{ items: string[] }>("marketplace_timezones", {});
  if (result.state !== "ok") return result;
  if (!Array.isArray(result.data?.items) || result.data.items.some(zone => typeof zone !== "string")) {
    return { state: "error", message: "Timezones could not be loaded." };
  }
  return { state: "ok", data: result.data.items };
}

export async function loadModerationQueue(): Promise<AdminLoad<AdminListing[]>> {
  const result = await load<{ items: AdminListing[] }>(
    "marketplace_admin_moderation_queue",
    { p_limit: 50, p_cursor: null },
  );
  if (result.state !== "ok") return result;
  return { state: "ok", data: result.data.items ?? [] };
}

export async function loadCommercialConfig(): Promise<AdminLoad<unknown>> {
  return load<unknown>("admin_commercial_config", {});
}
