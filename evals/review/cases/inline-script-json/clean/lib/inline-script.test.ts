import { describe, expect, it } from "vitest";
import { toInlineScriptString } from "./inline-script";

describe("toInlineScriptString", () => {
  it.each(["</script><script>alert(1)</script>", "<!--", "GTM-<b>"])("leaves no raw < in %s", (value) => {
    const literal = toInlineScriptString(value);
    expect(literal).not.toContain("<");
    expect(JSON.parse(literal)).toBe(value);
  });

  it("keeps an ordinary tag ID as a quoted string", () => {
    expect(toInlineScriptString("GTM-ABC123")).toBe('"GTM-ABC123"');
  });
});
