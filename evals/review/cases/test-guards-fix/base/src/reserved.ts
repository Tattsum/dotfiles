const RESERVED = ["admin", "api", "login"];

export function isReservedSlug(slug: string): boolean {
  return RESERVED.includes(slug);
}
