import { execFile } from "node:child_process";
import { join } from "node:path";

export function readReduceMotion(nativeDirectory: string): Promise<boolean | undefined> {
  return new Promise((resolve) => {
    execFile(
      join(nativeDirectory, "likeit-reduce-motion"),
      { timeout: 1_000, killSignal: "SIGKILL", maxBuffer: 64, encoding: "utf8" },
      (error, stdout) =>
        resolve(error ? undefined : stdout === "false\n" ? false : stdout === "true\n" ? true : undefined),
    );
  });
}
