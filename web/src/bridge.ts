import { snapshotSchema, type Snapshot } from "./model";
export type NativeEvent =
  { type: "snapshot"; snapshot: Snapshot } | { type: "error"; message: string };
declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        portMap?: {
          postMessage: (message: {
            type: "ready" | "refresh";
            schemaVersion: 1;
          }) => void;
        };
      };
    };
    portMap?: { receive: (event: unknown) => void };
  }
}
export const isNative = () => !!window.webkit?.messageHandlers?.portMap;
export function requestNative(type: "ready" | "refresh") {
  window.webkit?.messageHandlers?.portMap?.postMessage({
    type,
    schemaVersion: 1,
  });
}
export function connectNative(
  onEvent: (event: NativeEvent) => void,
): () => void {
  const receive = (input: unknown) => {
    try {
      if (!input || typeof input !== "object") throw new Error("Invalid event");
      const event = input as Record<string, unknown>;
      if (event.type === "snapshot")
        onEvent({
          type: "snapshot",
          snapshot: snapshotSchema.parse(event.snapshot),
        });
      else if (event.type === "error" && typeof event.message === "string")
        onEvent({ type: "error", message: event.message });
      else throw new Error("Unknown event");
    } catch {
      onEvent({
        type: "error",
        message:
          "The connection report could not be read. Check the report format and try again.",
      });
    }
  };
  window.portMap = { receive };
  requestNative("ready");
  return () => {
    if (window.portMap?.receive === receive) delete window.portMap;
  };
}
