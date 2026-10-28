import { db } from "./db";

export async function listDrafts(orgId: string) {
  return db.draft.findMany({
    where: { orgId },
    select: { id: true, title: true, authorEmail: true },
    orderBy: { id: "asc" },
    take: 50,
  });
}
