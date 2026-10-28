import { db } from "../db/client";
import { entryDrafts } from "../db/schema";

export class SlugTakenError extends Error {
  constructor(slug: string, options?: ErrorOptions) {
    super(`slug already taken: ${slug}`, options);
    this.name = "SlugTakenError";
  }
}

// Published entries are not checked: a draft keeps the slug of the published entry it edits.
export async function saveDraft(modelId: number, slug: string) {
  try {
    await db.insert(entryDrafts).values({ modelId, slug });
  } catch (error) {
    if (isDuplicateKey(error)) {
      throw new SlugTakenError(slug, { cause: error });
    }
    throw error;
  }
}

function isDuplicateKey(error: unknown): boolean {
  return hasCode(error, "ER_DUP_ENTRY") || (error instanceof Error && hasCode(error.cause, "ER_DUP_ENTRY"));
}

function hasCode(value: unknown, code: string): boolean {
  return typeof value === "object" && value !== null && "code" in value && value.code === code;
}
