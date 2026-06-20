import { createStore } from "solid-js/store";

export type ViewMode = "note" | "search" | "config" | "help";

interface UIState {
  view: ViewMode;
}

export const [uiStore, setUIStore] = createStore<UIState>({ view: "note" });

export const setView = (view: ViewMode) => setUIStore("view", view);

export const toggleView = (view: ViewMode) =>
  setUIStore("view", (prev) => (prev === view ? "note" : view));
