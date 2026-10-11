import { closeMainWindow, environment, showHUD } from "@raycast/api";
import { join } from "node:path";
import { readNetease } from "./netease";

export default async function Command() {
  await closeMainWindow();
  try {
    const snapshot = await readNetease(join(environment.assetsPath, "netease-state.jxa"));
    const message =
      snapshot.state === "not-running"
        ? "网易云音乐未运行；Likeit 仅支持网易云"
        : snapshot.state === "permission-required"
          ? "请检查 Raycast 的辅助功能及自动化 → System Events 权限"
          : "暂无法确认网易云的歌曲身份与播放状态，未执行收藏";
    await showHUD(message);
  } catch {
    await showHUD("读取网易云状态失败或超时，未执行收藏");
  }
}
