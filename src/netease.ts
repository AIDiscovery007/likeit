import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import type { Port, Snapshot } from "./like-current-track";

export class BusyError extends Error {}

type Reply = { ready?: boolean; busy?: boolean; error?: string; snapshot?: Snapshot; action?: string };

export async function openNetease(nativeDirectory: string, supportPath: string) {
  await mkdir(supportPath, { recursive: true });
  const child = spawn(join(nativeDirectory, "likeit-controller"), [join(supportPath, "netease.lock")], {
    detached: true,
    stdio: ["pipe", "pipe", "pipe"],
  });
  let failure: Error | undefined;
  let pending: { resolve: (reply: Reply) => void; reject: (error: Error) => void } | undefined;
  let buffer = "";
  let errorBytes = 0;
  let exited = false;

  function killGroup() {
    if (child.pid) {
      try {
        process.kill(-child.pid, "SIGKILL");
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ESRCH") child.kill("SIGKILL");
      }
    }
  }

  function fail(error: Error) {
    failure ??= error;
    pending?.reject(failure);
    pending = undefined;
    killGroup();
  }

  function cancel() {
    killGroup();
    process.exit(0);
  }
  process.once("exit", killGroup);
  process.once("SIGTERM", cancel);
  process.once("SIGINT", cancel);

  const closed = new Promise<void>((resolve) => {
    child.once("exit", () => {
      exited = true;
      killGroup(); // Also reap any read-only Perl process after an abnormal controller exit.
    });
    child.once("close", () => {
      exited = true;
      failure ??= new Error("Native controller closed");
      pending?.reject(failure);
      pending = undefined;
      resolve();
    });
  });
  child.on("error", fail);
  child.stdin.on("error", fail);
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => {
    buffer += chunk;
    if (Buffer.byteLength(buffer) > 64 * 1024) return fail(new Error("Native response exceeded limit"));
    let newline: number;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      try {
        const response: Reply = JSON.parse(line);
        if (!response || typeof response !== "object" || !pending) throw new Error("Unexpected native response");
        const recipient = pending;
        pending = undefined;
        if (response.error) recipient.reject(new Error("Native operation failed"));
        else recipient.resolve(response);
      } catch {
        fail(new Error("Invalid native response"));
      }
    }
  });
  child.stderr.on("data", (chunk: Buffer) => {
    errorBytes += chunk.length;
    if (errorBytes > 64 * 1024) fail(new Error("Native error output exceeded limit"));
  });
  const lifetime = setTimeout(() => fail(new Error("Native command timed out")), 25_000);

  async function request(command?: { command: string; trackKey?: string }): Promise<Reply> {
    if (failure) throw failure;
    if (pending) throw new Error("Concurrent native request");
    let timer: NodeJS.Timeout | undefined;
    try {
      return await new Promise<Reply>((resolve, reject) => {
        pending = { resolve, reject };
        timer = setTimeout(() => fail(new Error("Native request timed out")), command ? 9000 : 2000);
        if (command) child.stdin.write(JSON.stringify(command) + "\n");
      });
    } finally {
      clearTimeout(timer);
    }
  }

  async function close() {
    clearTimeout(lifetime);
    child.stdin.end();
    let grace: NodeJS.Timeout | undefined;
    await Promise.race([closed, new Promise<void>((resolve) => (grace = setTimeout(resolve, 500)))]);
    clearTimeout(grace);
    if (!exited) killGroup();
    let deadline: NodeJS.Timeout | undefined;
    try {
      await Promise.race([
        closed,
        new Promise<never>((_, reject) => {
          deadline = setTimeout(() => reject(new Error("Native controller did not exit")), 1000);
        }),
      ]);
    } finally {
      clearTimeout(deadline);
      process.removeListener("exit", killGroup);
      process.removeListener("SIGTERM", cancel);
      process.removeListener("SIGINT", cancel);
    }
  }

  try {
    const hello = await request();
    if (hello.busy) throw new BusyError("Another like command is running");
    if (!hello.ready) throw new Error("Native controller did not become ready");
  } catch (error) {
    await close();
    throw error;
  }

  const port: Port = {
    async read() {
      const { snapshot } = await request({ command: "read" });
      if (
        !snapshot ||
        !["playing", "paused", "not-running", "unknown", "permission-required"].includes(snapshot.state) ||
        !(snapshot.trackKey === null || typeof snapshot.trackKey === "string") ||
        !(snapshot.liked === null || typeof snapshot.liked === "boolean") ||
        !(snapshot.title === undefined || typeof snapshot.title === "string")
      ) {
        throw new Error("Invalid native snapshot");
      }
      return snapshot;
    },
    async pressLike(trackKey) {
      const { action } = await request({ command: "press", trackKey });
      if (action !== "pressed" && action !== "already-liked" && action !== "changed" && action !== "unavailable") {
        throw new Error("Invalid native action response");
      }
      return action;
    },
  };
  return { port, close };
}
