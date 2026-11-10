import { expect, test } from "bun:test";
import { truncateHead, DEFAULT_MAX_BYTES, DEFAULT_MAX_LINES } from "../runtime.ts";

test("truncation respects the line limit without a trailing extra line", () => {
  expect(truncateHead("one\ntwo\nthree", { maxLines: 2 }).content).toBe("one\ntwo");
  expect(truncateHead("one", { maxLines: 0 }).content).toBe("");
  expect(truncateHead("", { maxLines: 0 }).truncated).toBe(false);
});

test("truncation never splits UTF-8 characters", () => {
  for (let maxBytes = 0; maxBytes < 16; maxBytes++) {
    const result = truncateHead("a🧪外部🧪z", { maxBytes });
    expect(Buffer.byteLength(result.content)).toBeLessThanOrEqual(maxBytes);
    expect(result.content).not.toContain("\uFFFD");
    expect("a🧪外部🧪z".startsWith(result.content)).toBe(true);
    expect(Buffer.from(result.content).toString("utf8")).toBe(result.content);
  }
});

test("default limits preserve small text and bound oversized text", () => {
  expect(truncateHead("one\ntwo")).toEqual({ content: "one\ntwo", truncated: false, totalBytes: 7, totalLines: 2 });
  const result = truncateHead("x\n".repeat(3000));
  expect(result.content.split("\n").length).toBeLessThanOrEqual(DEFAULT_MAX_LINES);
  expect(Buffer.byteLength(result.content)).toBeLessThanOrEqual(DEFAULT_MAX_BYTES);
  expect(result.totalLines).toBe(3001);
  expect(result.truncated).toBe(true);
});

test("multi-megabyte output is bounded in linear time", () => {
  const text = "🧪".repeat(1000000);
  const result = truncateHead(text);
  expect(Buffer.byteLength(result.content)).toBe(DEFAULT_MAX_BYTES);
  expect(result.totalBytes).toBe(4000000);
}, 1000);
