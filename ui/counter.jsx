export function Counter(props) {
  return (
    <column>
      <label>Count: {props.count()}</label>
      <button ref={props.buttonRef} onClick={props.onClick}>
        Increment
      </button>
    </column>
  );
}

if (import.meta.hot) import.meta.hot.accept();
