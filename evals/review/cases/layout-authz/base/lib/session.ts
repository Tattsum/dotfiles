import { jwtVerify } from "jose";
import type { Session } from "./auth";

const secret = new TextEncoder().encode(process.env.SESSION_SECRET);

export async function verifySessionToken(token: string): Promise<Session | null> {
  try {
    const { payload } = await jwtVerify(token, secret, { algorithms: ["HS256"] });
    if (typeof payload.sub !== "string" || typeof payload.org !== "string" || !Array.isArray(payload.roles)) {
      return null;
    }
    const roles = payload.roles.filter((role): role is string => typeof role === "string");
    return { userId: payload.sub, orgId: payload.org, roles };
  } catch {
    return null;
  }
}
