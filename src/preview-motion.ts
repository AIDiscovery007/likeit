import { environment, showHUD, type LaunchProps } from "@raycast/api";
import { join } from "node:path";
import { celebrate } from "./confetti";
import { readReduceMotion } from "./reduce-motion";
import { presentResult, type MotionMode } from "./result-feedback";

export default async function Command({ arguments: args }: LaunchProps<{ arguments: { motionMode: MotionMode } }>) {
  const nativeDirectory = join(environment.assetsPath, "native");
  const mode = args.motionMode === "system" || args.motionMode === "always" ? args.motionMode : "off";
  await presentResult("liked", mode, {
    showHUD: () => showHUD("Likeit 动效预览（不操作音乐）"),
    readReduceMotion: () => readReduceMotion(nativeDirectory),
    celebrate: (mode) => celebrate(nativeDirectory, environment.supportPath, mode),
  });
}
