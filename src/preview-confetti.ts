import { environment, showHUD } from "@raycast/api";
import { join } from "node:path";
import { celebrate } from "./confetti";
import { readReduceMotion } from "./reduce-motion";

export default async function Command() {
  await showHUD("Likeit 彩带预览（不操作音乐）");
  const nativeDirectory = join(environment.assetsPath, "native");
  if ((await readReduceMotion(nativeDirectory)) === false) await celebrate(nativeDirectory, environment.supportPath);
}
