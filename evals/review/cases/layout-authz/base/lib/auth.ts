import { cookies } from "next/headers";
import { notFound } from "next/navigation";
import { verifySessionToken } from "./session";

export type Session = { userId: string; orgId: string; roles: string[] };

export async function getSession(): Promise<Session | null> {
  const token = (await cookies()).get("session")?.value;
  return token ? verifySessionToken(token) : null;
}

export async function requireAdmin(): Promise<Session> {
  const session = await getSession();
  if (!session || !session.roles.includes("admin")) {
    notFound();
  }
  return session;
}
