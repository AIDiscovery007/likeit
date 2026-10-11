import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { Snapshot } from "./like-current-track";

const execute = promisify(execFile);

export async function readNetease(scriptPath: string): Promise<Snapshot> {
  const { stdout } = await execute("/usr/bin/osascript", ["-l", "JavaScript", scriptPath], {
    timeout: 4000,
    killSignal: "SIGKILL",
    maxBuffer: 64 * 1024,
  });
  const result = JSON.parse(stdout);
  if (!["unknown", "not-running", "permission-required"].includes(result.state) || result.trackKey !== null) {
    throw new Error("Unexpected NetEase reader response");
  }
  return { state: result.state, trackKey: null, liked: typeof result.liked === "boolean" ? result.liked : null };
}
