import { int, mysqlTable, uniqueIndex, varchar } from "drizzle-orm/mysql-core";

export const entryDrafts = mysqlTable(
  "entry_drafts",
  {
    id: int("id").primaryKey().autoincrement(),
    modelId: int("model_id").notNull(),
    slug: varchar("slug", { length: 255 }).notNull(),
  },
  (table) => [uniqueIndex("entry_drafts_model_slug").on(table.modelId, table.slug)],
);

// A published entry keeps its slug while its next draft is edited, so the
// same (model_id, slug) appears in both tables by design.
export const publishedEntries = mysqlTable("published_entries", {
  id: int("id").primaryKey().autoincrement(),
  modelId: int("model_id").notNull(),
  slug: varchar("slug", { length: 255 }).notNull(),
});
