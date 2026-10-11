import {
  Action,
  ActionPanel,
  closeMainWindow,
  environment,
  getFrontmostApplication,
  getPreferenceValues,
  Icon,
  launchCommand,
  LaunchType,
  List,
  showToast,
  Toast,
} from "@raycast/api";
import { execFile } from "node:child_process";
import { join } from "node:path";
import { promisify } from "node:util";

async function openDesktop(theme?: "classic" | "glass") {
  try {
    const previous = await getFrontmostApplication();
    const preferences = getPreferenceValues<Preferences>();
    const mode = preferences.desktopMotionMode ?? "system";
    const url = new URL("likeit-desktop://open");
    url.searchParams.set("mode", mode);
    if (theme) url.searchParams.set("theme", theme);
    url.searchParams.set("lyricsSource", preferences.desktopLyricsSource === "community" ? "community" : "netease");
    if (previous.bundleId) url.searchParams.set("returnBundle", previous.bundleId);
    await closeMainWindow();
    await promisify(execFile)(
      "/usr/bin/open",
      ["-a", join(environment.assetsPath, "native", "Likeit Desktop.app"), url.toString()],
      { timeout: 5000 },
    );
  } catch {
    await showToast({
      style: Toast.Style.Failure,
      title: "无法打开音乐桌面",
      message: "沉浸模式需要 macOS 14.2 或更新版本及完整的 Likeit app 包。",
    });
  }
}

export default function Command() {
  return (
    <List searchBarPlaceholder="选择 Likeit 功能">
      <List.Item
        title="沉浸模式"
        subtitle="全屏音乐桌面 · Esc 即可退出"
        icon={Icon.Music}
        actions={
          <ActionPanel>
            <Action title="打开沉浸模式" onAction={() => openDesktop()} />
            <Action title="打开经典音响" onAction={() => openDesktop("classic")} />
            <Action title="打开透明音响" onAction={() => openDesktop("glass")} />
          </ActionPanel>
        }
      />
      <List.Item
        title="收藏当前歌曲"
        subtitle="网易云音乐 · 已喜欢的歌曲不会取消"
        icon={Icon.Heart}
        actions={
          <ActionPanel>
            <Action
              title="收藏当前歌曲"
              onAction={() => launchCommand({ name: "likeit", type: LaunchType.UserInitiated })}
            />
          </ActionPanel>
        }
      />
    </List>
  );
}
