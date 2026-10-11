export type Snapshot = {
  state: "playing" | "paused" | "not-running" | "unknown" | "permission-required";
  trackKey: string | null;
  liked: boolean | null;
  title?: string;
};

export type Port = {
  read(): Promise<Snapshot>;
  pressLike(expectedTrackKey: string): Promise<"pressed" | "already-liked" | "changed" | "unavailable">;
};
