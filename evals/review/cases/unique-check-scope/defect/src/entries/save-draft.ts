import { and, eq } from "drizzle-orm";
import { db } from "../db/client";
import { entryDrafts, publishedEntries } from "../db/schema";

export class SlugTakenError extends Error {
  constructor(slug: string, options?: ErrorOptions) {
    super(`slug already taken: ${slug}`, options);
    this.name = "SlugTakenError";
  }
}

// Check before inserting so that the editor gets a readable error instead of
// a duplicate-key failure from the unique index.
export async function saveDraft(modelId: number, slug: string) {
  const [draft] = await db
    .select({ id: entryDrafts.id })
    .from(entryDrafts)
    .where(and(eq(entryDrafts.modelId, modelId), eq(entryDrafts.slug, slug)))
    .limit(1);
  const [published] = await db
    .select({ id: publishedEntries.id })
    .from(publishedEntries)
    .where(and(eq(publishedEntries.modelId, modelId), eq(publishedEntries.slug, slug)))
    .limit(1);
  if (draft || published) {
    throw new SlugTakenError(slug);
  }
  await db.insert(entryDrafts).values({ modelId, slug });
}
