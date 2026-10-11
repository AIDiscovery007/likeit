import type { Status } from "./like-current-track";

export type FeedbackStatus = Status | "busy";
export type FeedbackPort = {
  showHUD(status: FeedbackStatus): Promise<void>;
  readReduceMotion(): Promise<boolean | undefined>;
  celebrate(): Promise<void>;
};

export async function presentResult(status: FeedbackStatus, enabled: boolean, port: FeedbackPort): Promise<void> {
  await port.showHUD(status);
  if (status !== "liked" || !enabled) return;
  try {
    if ((await port.readReduceMotion()) === false) await port.celebrate();
  } catch {
    // Optional animation must not change an already reported music result.
  }
}
