import { db } from "../db/client";
import { entryDrafts } from "../db/schema";

export async function saveDraft(modelId: number, slug: string) {
  await db.insert(entryDrafts).values({ modelId, slug });
}
