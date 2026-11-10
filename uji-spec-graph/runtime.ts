import type { Static, TSchema } from "typebox";

export const DEFAULT_MAX_BYTES = 50 * 1024;
export const DEFAULT_MAX_LINES = 2000;

export interface ToolResult<T> {
	content: { type: "text"; text: string }[];
	details: T;
	isError?: boolean;
}

export interface ToolContext {
	cwd: string;
}

export interface ToolDefinition<S extends TSchema = TSchema, R = unknown> {
	name: string;
	label: string;
	description: string;
	promptSnippet?: string;
	parameters: S;
	execute(
		callId: string,
		params: Static<S>,
		signal: AbortSignal | undefined,
		onUpdate: ((result: ToolResult<R>) => void) | undefined,
		ctx: ToolContext,
	): Promise<ToolResult<R>>;
}

export interface ToolRegistry {
	registerTool<S extends TSchema, R>(tool: ToolDefinition<S, R>): void;
}

export function truncateHead(text: string, options: { maxBytes?: number; maxLines?: number } = {}) {
	const maxBytes = options.maxBytes ?? DEFAULT_MAX_BYTES;
	const maxLines = options.maxLines ?? DEFAULT_MAX_LINES;
	const totalBytes = Buffer.byteLength(text, "utf8");
	const totalLines = text.length === 0 ? 0 : text.split("\n").length;
	const bytes = Buffer.from(text, "utf8");
	let end = Math.min(bytes.length, Math.max(0, maxBytes));
	while (end > 0 && end < bytes.length && (bytes[end] & 0xc0) === 0x80) end--;
	if (maxLines <= 0) end = 0;
	else if (totalLines > maxLines) {
		let lines = 1;
		for (let index = 0; index < end; index++) {
			if (bytes[index] === 10 && lines++ === maxLines) {
				end = index;
				break;
			}
		}
	}
	const content = bytes.subarray(0, end).toString("utf8");
	return { content, truncated: end < bytes.length, totalBytes, totalLines };
}
