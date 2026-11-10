import { expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { manifest } from "../bridge.ts";

test("committed tool schemas match the registered tools", async () => {
  expect(await Bun.file(new URL("../tools.json", import.meta.url)).json()).toEqual(manifest);
});

test("real uji loads the Lua pack and runs all seven tools without a model", async () => {
  const cwd = mkdtempSync(join(tmpdir(), "uji-spec-integration-"));
  try {
    const child = Bun.spawn([
      "uji", "run", "--config-dir", new URL("./config", import.meta.url).pathname,
      "--data-dir", join(cwd, "data"), "test",
    ], { cwd, stdout: "pipe", stderr: "pipe" });
    const [stdout, stderr, code] = await Promise.all([
      new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited,
    ]);
    expect({ stdout, stderr, code }).toMatchObject({ code: 0 });
    expect(stdout).toContain("passed real uji:");
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
}, 30000);
