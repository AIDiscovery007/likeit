import type { Status } from "./like-current-track";

export type FeedbackStatus = Status | "busy";
export type MotionMode = "system" | "always" | "off";
export type FeedbackPort = {
  showHUD(status: FeedbackStatus): Promise<void>;
  readReduceMotion(): Promise<boolean | undefined>;
  celebrate(mode: "system" | "always"): Promise<void>;
};

export async function presentResult(
  status: FeedbackStatus,
  mode: boolean | MotionMode,
  port: FeedbackPort,
): Promise<void> {
  await port.showHUD(status);
  const policy = mode === true ? "system" : mode;
  if (status !== "liked" || (policy !== "system" && policy !== "always")) return;
  try {
    if (policy === "always" || (await port.readReduceMotion()) === false) await port.celebrate(policy);
  } catch {
    // Optional animation must not change an already reported music result.
  }
}
