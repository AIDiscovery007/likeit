import { closeMainWindow, environment, getPreferenceValues, showHUD } from "@raycast/api";
import { join } from "node:path";
import { likeCurrentTrack, type Status } from "./like-current-track";
import { BusyError, openNetease } from "./netease";
import { presentResult, type MotionMode } from "./result-feedback";
import { readReduceMotion } from "./reduce-motion";
import { celebrate } from "./confetti";

const messages: Record<Status | "busy", string> = {
  liked: "网易云客户端已确认喜欢；云端同步以客户端为准",
  "already-liked": "这首歌已在我喜欢的音乐中",
  "not-running": "网易云音乐未运行；Likeit 仅支持网易云",
  "not-playing": "网易云未在播放，未执行收藏",
  unavailable: "无法确认歌曲或收藏状态，未执行收藏",
  "permission-required": "请在系统设置 → 隐私与安全性 → 辅助功能中检查 Raycast 权限",
  "track-changed": "歌曲已变化，已停止收藏",
  unconfirmed: "收藏结果未确认，请在网易云检查；未重复点击",
  failed: "读取网易云状态失败或超时，未执行收藏",
  busy: "已有收藏命令正在处理，请稍后再试",
};

export default async function Command() {
  await closeMainWindow();
  let status: Status | "busy" = "failed";
  let session: Awaited<ReturnType<typeof openNetease>> | undefined;
  try {
    session = await openNetease(join(environment.assetsPath, "native"), environment.supportPath);
    status = (await likeCurrentTrack(session.port)).status;
  } catch (error) {
    if (error instanceof BusyError) status = "busy";
  } finally {
    if (session) {
      try {
        await session.close();
      } catch {
        status = status === "liked" || status === "unconfirmed" ? "unconfirmed" : "failed";
      }
    }
  }
  let mode: MotionMode = "off";
  try {
    const preference = getPreferenceValues<Preferences>().motionMode;
    if (preference === "system" || preference === "always") mode = preference;
  } catch {
    // An unreadable optional preference must not hide the music result.
  }
  const nativeDirectory = join(environment.assetsPath, "native");
  await presentResult(status, mode, {
    showHUD: (result) => showHUD(messages[result]),
    readReduceMotion: () => readReduceMotion(nativeDirectory),
    celebrate: (policy) => celebrate(nativeDirectory, environment.supportPath, policy),
  });
}
