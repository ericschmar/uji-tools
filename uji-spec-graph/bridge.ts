import { createInterface } from "node:readline";
import { writeFileSync } from "node:fs";
import { Value } from "typebox/value";
import type { ToolDefinition, ToolRegistry } from "./runtime.ts";
import { registerSpecTools } from "./tools/index.ts";

export const tools = new Map<string, ToolDefinition>();
registerSpecTools({
  registerTool(tool: ToolDefinition) {
    tools.set(tool.name, tool);
  },
} as ToolRegistry);

export const manifest = [...tools.values()].map(({ name, label, description, parameters }) => ({
  name, label, description, parameters,
}));

export async function execute(name: string, params: Record<string, unknown>, cwd: string) {
  const tool = tools.get(name);
  if (!tool) throw new Error(`Unknown spec tool: ${name}`);
  if (!Value.Check(tool.parameters, params)) throw new Error(`Invalid parameters for ${name}`);
  const result = await tool.execute("uji", params, undefined, undefined, { cwd });
  return result.content.map((block) => block.text).join("\n");
}

if (import.meta.main) {
  if (process.argv.includes("--manifest")) {
    writeFileSync(new URL("./tools.json", import.meta.url), JSON.stringify(manifest, null, 2) + "\n");
  } else {
    const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
    for await (const line of input) {
      let id: unknown = null;
      let text: string;
      try {
        const request = JSON.parse(line);
        id = request.id;
        text = await execute(request.name, request.params, process.cwd());
      } catch (error) {
        text = `Error: ${error instanceof Error ? error.message : String(error)}`;
      }
      const characters = Array.from(text);
      for (let offset = 0; offset < characters.length; offset += 2048) {
        console.log(JSON.stringify({ id, text: characters.slice(offset, offset + 2048).join("") }));
      }
      console.log(JSON.stringify({ id, done: true }));
    }
  }
}
