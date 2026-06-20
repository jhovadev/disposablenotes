import { createMemo, createSignal, For, type Component } from "solid-js";
import { A } from "@solidjs/router";
import { noteStore } from "../stores/note.store";

interface SearchProps {
  onClose: () => void;
}

const Search: Component<SearchProps> = (props) => {
  const [search, setSearch] = createSignal("");

  const filteredNotes = createMemo(() => {
    const allNotes = Object.values(noteStore.notes);
    const searchTerm = search().toLowerCase();
    if (!searchTerm) return allNotes;
    return allNotes.filter(note =>
      note.name.toLowerCase().includes(searchTerm)
    );
  });

  return (
    <main class="h-screen text-neutral-200 bg-neutral-800 flex flex-col">
      <input
        class="p-4 bg-neutral-800 text-xl font-bold outline-none border-b border-neutral-700"
        type="text"
        placeholder="Buscar notas..."
        value={search()}
        onInput={(e) => setSearch(e.currentTarget.value)}
        autofocus
      />
      <div class="flex-1 overflow-y-auto p-4 flex flex-col gap-2">
        <For each={filteredNotes()} fallback={<div class="text-neutral-500">No se encontraron notas.</div>}>
          {(note) => (
            <A
              href={`/${note.id}`}
              onClick={() => props.onClose()}
              class="p-3 bg-neutral-900 rounded hover:bg-neutral-700 transition-colors cursor-pointer block"
            >
              <span class="text-xs font-light text-neutral-600">{note.id}</span>
              <h3 class="font-bold">{note.name || "Sin título"}</h3>
              <p class="text-sm text-neutral-400 truncate">{note.content || "Sin contenido"}</p>
            </A>
          )}
        </For>
      </div>
    </main>
  );
};

export default Search;
