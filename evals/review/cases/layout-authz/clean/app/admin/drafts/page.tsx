import { requireAdmin } from "@/lib/auth";
import { listDrafts } from "@/lib/drafts";

export default async function DraftsPage() {
  const session = await requireAdmin();
  const drafts = await listDrafts(session.orgId);
  return (
    <ul>
      {drafts.map((draft) => (
        <li key={draft.id}>
          {draft.title} ({draft.authorEmail})
        </li>
      ))}
    </ul>
  );
}
