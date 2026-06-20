import { useNavigate, useParams } from "@solidjs/router";
import { createMemo, createEffect, createUniqueId, Switch, Match } from "solid-js";
import { noteStore, upsertNote, deleteNote, isLoaded } from './stores/note.store';
import { uiStore, setView } from './stores/ui.store';
import { createShortcut } from './hooks/createShortcut';
import Search from './components/Search';
import Help from './components/Help';

export default function Note() {
  const params = useParams<{ id: string }>();
  const navigate = useNavigate();

  const currentNote = createMemo(() => noteStore.notes[params.id]);

  createEffect(() => {
    if (!currentNote() && isLoaded()) {
      upsertNote(params.id, { name: createUniqueId(), content: "" });
    }
  });

  createShortcut("n", () => {
    setView("note");
    navigate(`/${crypto.randomUUID()}`);
  }, { alt: true });

  createShortcut("n", async () => {
    if (window.webui?.isConnected()) {
      await window.webui.call("open_new_window", params.id);
    }
  }, { shift: true, alt: true });

  createShortcut("s", () => {
    setView(uiStore.view === "search" ? "note" : "search");
  }, { alt: true });

  createShortcut("c", () => {
    const note = currentNote();
    if (note?.content) {
      navigator.clipboard.writeText(note.content);
    }
  }, { alt: true });

  createShortcut("x", () => {
    const note = currentNote();
    if (note?.content) {
      navigator.clipboard.writeText(note.content);
    }
    deleteNote(params.id);
    navigate(`/${crypto.randomUUID()}`);
  }, { alt: true });

  createShortcut("h", () => {
    setView(uiStore.view === "help" ? "note" : "help");
  }, { alt: true });

  createShortcut("d", () => {
    deleteNote(params.id);
    // navigate(`/${crypto.randomUUID()}`);
    navigate("/default");

  }, { alt: true });

  // createShortcut("p", () => {
  //   setView(uiStore.view === "config" ? "note" : "config");
  // }, { alt: true });
  //
  createShortcut("q", () => {
    // if (window.webui?.isConnected()) {
    // window.webui.call("close_window");
    // }
    window.close()
  }, { alt: true });

  return (
    <main class="h-screen text-neutral-200 bg-neutral-800 flex flex-col">
      <Switch fallback={<span class="p-4">...</span>}>
        <Match when={uiStore.view === "note"}>
          <input
            class="p-4 bg-neutral-800 text-xl font-bold outline-none"
            type="text"
            placeholder="..."
            value={currentNote()?.name || ""}
            onInput={(e) => upsertNote(params.id, { name: e.currentTarget.value })}
            autofocus
          />
          <textarea
            placeholder="..."
            class="p-4 bg-neutral-900 h-full resize-none outline-none"
            value={currentNote()?.content || ""}
            onInput={(e) => upsertNote(params.id, { content: e.currentTarget.value })}
          />
        </Match>
        <Match when={uiStore.view === "search"}>
          <Search onClose={() => setView("note")} />
        </Match>
        <Match when={uiStore.view === "help"}>
          <Help />
        </Match>
      </Switch>
    </main>
  );
}
