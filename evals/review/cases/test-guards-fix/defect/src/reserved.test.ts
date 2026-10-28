import { describe, expect, it } from "vitest";
import { isReservedSlug } from "./reserved";

describe("isReservedSlug", () => {
  it("rejects a reserved slug", () => {
    expect(isReservedSlug("admin")).toBe(true);
  });

  it("accepts an ordinary slug", () => {
    expect(isReservedSlug("news")).toBe(false);
  });

  it("rejects a reserved slug regardless of case", () => {
    expect(isReservedSlug("api")).toBe(true);
  });
});
