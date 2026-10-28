import { db } from "./db";

// Any site editor (a customer-side account, not an operator) changes these values from the settings screen.
export type SiteSettings = { locale: string; analyticsTagId: string | null };

export async function getSiteSettings(): Promise<SiteSettings> {
  return db.siteSettings.findFirstOrThrow({
    select: { locale: true, analyticsTagId: true },
  });
}
