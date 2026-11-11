import { createSignal, createEffect, onSettled, For } from "solid-js";

const stateCities = {
  Utah: ["Salt Lake City", "Provo", "West Valley City"],
  California: ["Los Angeles", "San Francisco", "San Diego"],
  Texas: ["Houston", "Dallas", "Austin"],
  Florida: ["Miami", "Orlando", "Tampa"],
  "New York": ["New York City", "Buffalo", "Rochester"],
};

async function getCities(state) {
  await new Promise((res) => setTimeout(res, 500));
  return stateCities[state] ?? [];
}

async function getStates() {
  await new Promise((res) => setTimeout(res, 500));
  return ["California", "Florida", "New York", "Texas", "Utah"];
}

function Dropdown({ label, items, selected, onSelect, loading }) {
  const [open, setOpen] = createSignal(false);
  return (
    <column style={{ gap: 4 }}>
      <button onClick={() => setOpen(!open())}>
        {label}: {selected() ?? (loading() ? "Loading..." : "None")}
      </button>
      {open() && (
        <column style={{ padding: 4, gap: 2, backgroundColor: "#222222" }}>
          <For each={items()}>
            {(item) => (
              <button
                onClick={() => {
                  onSelect(item);
                  setOpen(false);
                }}
              >
                {item}
              </button>
            )}
          </For>
        </column>
      )}
    </column>
  );
}

export default function States() {
  const [states, setStates] = createSignal([]);
  const [selectedState, setSelectedState] = createSignal(null);
  const [cities, setCities] = createSignal([]);
  const [selectedCity, setSelectedCity] = createSignal(null);
  const [loadingStates, setLoadingStates] = createSignal(true);
  const [loadingCities, setLoadingCities] = createSignal(false);

  onSettled(() => {
    (async () => {
      setLoadingStates(true);
      const s = await getStates();
      setStates(s);
      setSelectedState(s[0]);
      setLoadingStates(false);
    })();
  });

  createEffect(
    () => selectedState(),
    (state) => {
      if (!state) return;
      (async () => {
        setLoadingCities(true);
        const c = await getCities(state);
        setCities(c);
        setSelectedCity(c[0]);
        setLoadingCities(false);
      })();
    },
  );

  return (
    <column style={{ padding: 20, gap: 8 }}>
      <label>Loading states: {loadingStates() ? "yes" : "no"}</label>
      <Dropdown
        label="State"
        items={states}
        selected={selectedState}
        onSelect={setSelectedState}
        loading={loadingStates}
      />
      <label>Loading cities: {loadingCities() ? "yes" : "no"}</label>
      <Dropdown
        label="City"
        items={cities}
        selected={selectedCity}
        onSelect={setSelectedCity}
        loading={loadingCities}
      />
      <label>
        Selection: {selectedCity() ?? ""}, {selectedState() ?? ""}
      </label>
    </column>
  );
}

if (import.meta.hot) import.meta.hot.accept();
