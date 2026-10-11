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

export type Status =
  | "liked"
  | "already-liked"
  | "not-running"
  | "not-playing"
  | "unavailable"
  | "permission-required"
  | "track-changed"
  | "unconfirmed"
  | "failed";

function rejection(snapshot: Snapshot): Status | undefined {
  if (snapshot.state === "not-running") return "not-running";
  if (snapshot.state === "paused") return "not-playing";
  if (snapshot.state === "permission-required") return "permission-required";
  if (snapshot.state !== "playing" || !snapshot.trackKey?.trim() || typeof snapshot.liked !== "boolean") {
    return "unavailable";
  }
}

export async function likeCurrentTrack(port: Port): Promise<{ status: Status; title?: string }> {
  let first: Snapshot;
  try {
    first = await port.read();
    const invalid = rejection(first);
    if (invalid) return { status: invalid };
    if (first.liked) return { status: "already-liked", title: first.title };

    const current = await port.read();
    const changed = rejection(current);
    if (changed) return { status: changed };
    if (current.trackKey !== first.trackKey) return { status: "track-changed" };
    if (current.liked) return { status: "already-liked", title: current.title };
  } catch {
    return { status: "failed" };
  }

  try {
    const action = await port.pressLike(first.trackKey!);
    if (action === "changed") return { status: "track-changed" };
    if (action === "already-liked") return { status: "already-liked", title: first.title };
    if (action === "unavailable") return { status: "unavailable" };
    if (action !== "pressed") return { status: "unconfirmed" };

    const after = await port.read();
    return !rejection(after) && after.trackKey === first.trackKey && after.liked === true
      ? { status: "liked", title: after.title }
      : { status: "unconfirmed" };
  } catch {
    return { status: "unconfirmed" };
  }
}
