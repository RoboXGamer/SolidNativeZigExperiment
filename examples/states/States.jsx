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

export default function States() {
  const [states, setStates] = createSignal([]);
  const [selectedState, setSelectedState] = createSignal(null);
  const [cities, setCities] = createSignal([]);
  const [selectedCity, setSelectedCity] = createSignal(null);
  const [loadingStates, setLoadingStates] = createSignal(true);
  const [loadingCities, setLoadingCities] = createSignal(false);

  let cityRequestId = 0;

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
      const token = ++cityRequestId;
      if (!state) {
        setCities([]);
        setSelectedCity(null);
        setLoadingCities(false);
        return;
      }
      setLoadingCities(true);
      setCities([]);
      setSelectedCity(null);
      (async () => {
        const c = await getCities(state);
        if (token !== cityRequestId) return;
        setCities(c);
        setSelectedCity(c[0] ?? null);
        setLoadingCities(false);
      })();
    },
  );

  return (
    <column style={{ padding: 20, gap: 8 }}>
      <label>Loading states: {loadingStates() ? "yes" : "no"}</label>
      <label>State:</label>
      <select
        value={selectedState() ?? ""}
        onChange={(e) => setSelectedState(e.target.value)}
        disabled={loadingStates()}
      >
        <For each={states()}>
          {(state) => (
            <option value={state} selected={state === selectedState()}>
              {state}
            </option>
          )}
        </For>
      </select>

      <label>Loading cities: {loadingCities() ? "yes" : "no"}</label>
      <label>City:</label>
      <select
        value={selectedCity() ?? ""}
        onChange={(e) => setSelectedCity(e.target.value)}
        disabled={loadingCities() || cities().length === 0}
      >
        <For each={cities()}>
          {(city) => (
            <option value={city} selected={city === selectedCity()}>
              {city}
            </option>
          )}
        </For>
      </select>

      <label>
        Selection: {selectedCity() ?? ""}, {selectedState() ?? ""}
      </label>
    </column>
  );
}

if (import.meta.hot) import.meta.hot.accept();
