import { createStore, reconcile } from "solid-js/store";
import { waitForWebUI } from "../lib/webui.bridge";

export type Note = {
  id: string;
  name: string;
  content: string;
  createdAt: string;
};

export type NoteDictionary = Record<string, Note>;

export const [noteStore, setNoteStore] = createStore<{ notes: NoteDictionary }>({ notes: {} });

export const clientSessionId = crypto.randomUUID();

let storeLoaded = false;

export function isLoaded(): boolean {
  return storeLoaded;
}

let ready: Promise<void>;

async function init() {
  const connected = await waitForWebUI();
  if (!connected) {
    console.warn("[Store] WebUI no disponible, operaciones diferidas hasta conexión");
    return;
  }

  const result = await window.webui!.call("get_notes");
  if (typeof result === "string") {
    try {
      const data = JSON.parse(result);
      if (data?.notes) {
        setNoteStore("notes", reconcile(data.notes));
        console.log("[Store] Loaded", Object.keys(data.notes).length, "notes from backend");
      }
    } catch (e) {
      console.error("[Store] Error parsing notes:", e);
    }
  }
  storeLoaded = true;
  console.log("[Store] Initial load complete");

  window.addEventListener("note-event", ((event: CustomEvent) => {
    const { type, id, name, content, clientId } = event.detail ?? {};
    if (!id) return;

    // Ignore events that were initiated by this window/tab to prevent overwriting active typing
    if (clientId === clientSessionId) {
      return;
    }

    if (type === "note_updated" || type === "note_created") {
      setNoteStore("notes", id, reconcile({
        id,
        name: name !== undefined ? name : (noteStore.notes[id]?.name ?? ""),
        content: content !== undefined ? content : (noteStore.notes[id]?.content ?? ""),
        createdAt: noteStore.notes[id]?.createdAt ?? new Date().toISOString(),
      }));
    } else if (type === "note_deleted" || type === "note_archived") {
      setNoteStore("notes", (prev: NoteDictionary) => {
        const next = { ...prev };
        delete next[id];
        return next;
      });
    }
  }) as EventListener);
}

ready = init();

async function callBackend(fn: string, ...args: (string | number | boolean | Uint8Array)[]) {
  await ready;
  if (!window.webui?.isConnected()) return;
  return window.webui.call(fn, ...args);
}

export const upsertNote = (id: string, updates: Partial<Note>) => {
  const exists = !!noteStore.notes[id];
  if (!exists) {
    const now = new Date().toISOString();
    setNoteStore("notes", id, {
      id,
      createdAt: now,
      name: updates.name ?? "",
      content: updates.content ?? "",
      ...updates,
    });
  } else {
    setNoteStore("notes", id, updates);
  }

  if (!storeLoaded && exists) {
    console.log("[Store] Skipping backend upsert (still loading) for existing note", id);
    return;
  }

  const payload: Record<string, string> = { id };
  if (updates.name !== undefined) payload.name = updates.name;
  if (updates.content !== undefined) payload.content = updates.content;
  if (updates.createdAt !== undefined) payload.createdAt = updates.createdAt;
  payload.clientId = clientSessionId;

  callBackend("upsert_note", JSON.stringify(payload)).catch((err) =>
    console.error("[Store] upsert command error:", err)
  );
};

export const deleteNote = (id: string) => {
  setNoteStore("notes", (prev: NoteDictionary) => {
    const next = { ...prev };
    delete next[id];
    return next;
  });

  if (!storeLoaded) return;
  callBackend("delete_note", JSON.stringify({ id, clientId: clientSessionId })).catch((err) =>
    console.error("[Store] delete_note command error:", err)
  );
};

export const archiveNote = (id: string) => {
  setNoteStore("notes", (prev: NoteDictionary) => {
    const next = { ...prev };
    delete next[id];
    return next;
  });

  if (!storeLoaded) return;
  callBackend("archive_note", JSON.stringify({ id, clientId: clientSessionId })).catch((err) =>
    console.error("[Store] archive_note command error:", err)
  );
};
