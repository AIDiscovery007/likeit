import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

export async function celebrate(nativeDirectory: string, supportPath: string): Promise<void> {
  await mkdir(supportPath, { recursive: true });
  return new Promise((resolve, reject) => {
    const child = spawn(join(nativeDirectory, "likeit-confetti"), [join(supportPath, "confetti.lock")], {
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let settled = false;
    let output = "";
    let bytes = 0;
    const kill = () => child.kill("SIGKILL");
    const finish = (error?: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      process.removeListener("exit", kill);
      if (error) kill();
      child.stdout.destroy();
      child.stderr.destroy();
      child.unref();
      if (error) reject(error);
      else resolve();
    };
    const timeout = setTimeout(() => finish(new Error("Confetti startup timed out")), 1_000);
    process.once("exit", kill);
    child.on("error", (error) => finish(error));
    child.on("exit", () => finish(new Error("Confetti exited before startup acknowledgement")));
    child.stdout.on("data", (chunk: Buffer) => {
      bytes += chunk.length;
      if (bytes > 64) finish(new Error("Confetti output exceeded limit"));
      else output += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk: Buffer) => {
      bytes += chunk.length;
      if (bytes > 64) finish(new Error("Confetti output exceeded limit"));
    });
    child.stdout.on("end", () =>
      finish(output === "started\n" || output === "skipped\n" ? undefined : new Error("Invalid confetti response")),
    );
  });
}
