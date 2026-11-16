import { createEffect, createMemo, createSignal, For, onCleanup, Show } from "solid-js";
import { cpuMove, outcome } from "./game.js";
import "./styles/game.css";

function Mark(props) {
  return <div class={`mark mark-${props.value} ${props.small ? "mark-small" : ""}`}>
    <div class="mark-stroke first" /><div class="mark-stroke second" />
  </div>;
}

function Logo() {
  return <div class="logo"><Mark value="x" small /><Mark value="o" small /></div>;
}

export default function App() {
  const [screen, setScreen] = createSignal("setup");
  const [player, setPlayer] = createSignal("x");
  const [mode, setMode] = createSignal("player");
  const [board, setBoard] = createSignal(Array(9).fill(null));
  const [turn, setTurn] = createSignal("x");
  const [scores, setScores] = createSignal({ x: 0, o: 0, tie: 0 });
  const [restart, setRestart] = createSignal(false);
  const result = createMemo(() => outcome(board()));
  const cpuTurn = () => mode() === "cpu" && turn() !== player();

  function clearRound() {
    setBoard(Array(9).fill(null));
    setTurn("x");
    setRestart(false);
  }
  function start(nextMode) {
    setMode(nextMode);
    setScores({ x: 0, o: 0, tie: 0 });
    clearRound();
    setScreen("game");
  }
  function play(index) {
    if (screen() !== "game" || result() || restart() || board()[index]) return;
    const next = board().slice();
    next[index] = turn();
    const finished = outcome(next);
    setBoard(next);
    if (finished) setScores(previous => ({ ...previous, [finished.winner]: previous[finished.winner] + 1 }));
    else setTurn(turn() === "x" ? "o" : "x");
  }
  let cpuTimer;
  onCleanup(() => clearTimeout(cpuTimer));
  createEffect(
    () => screen() === "game" && !result() && !restart() && cpuTurn() ? { cells: board(), mark: turn() } : null,
    pending => {
      clearTimeout(cpuTimer);
      if (pending) cpuTimer = setTimeout(() => play(cpuMove(pending.cells, pending.mark)), 350);
    },
  );
  function quit() { setScreen("setup"); clearRound(); }
  const resultCaption = () => result()?.winner === "tie" ? "A WELL-MATCHED ROUND" : mode() === "cpu" ? result()?.winner === player() ? "YOU WON!" : "OH NO, YOU LOST…" : `PLAYER ${result()?.winner === player() ? "1" : "2"} WINS!`;

  return <div id="tictactoe">
    <Show when={screen() === "setup"} fallback={
      <div class="game-shell">
        <div class="game-header">
          <Logo />
          <div class="turn-indicator"><Mark value={turn()} small /><div>TURN</div></div>
          <button class="restart-button" onClick={() => setRestart(true)}>↻</button>
        </div>
        <div class="board">
          <For each={board()}>{(cell, index) => <button
            class={`cell ${cell ? "occupied" : ""} ${result()?.line.includes(index()) ? `winner winner-${cell}` : ""}`}
            disabled={Boolean(cell) || Boolean(result()) || cpuTurn() || restart()}
            onClick={() => { if (!cpuTurn()) play(index()); }}
            aria-label={`Cell ${index() + 1}${cell ? `: ${cell.toUpperCase()}` : ""}`}
          ><Show when={cell}><Mark value={cell} /></Show></button>}</For>
        </div>
        <div class="scoreboard">
          <div class="score score-x"><div>X ({mode() === "cpu" ? player() === "x" ? "YOU" : "CPU" : player() === "x" ? "P1" : "P2"})</div><div class="score-number">{scores().x}</div></div>
          <div class="score score-tie"><div>TIES</div><div class="score-number">{scores().tie}</div></div>
          <div class="score score-o"><div>O ({mode() === "cpu" ? player() === "o" ? "YOU" : "CPU" : player() === "o" ? "P1" : "P2"})</div><div class="score-number">{scores().o}</div></div>
        </div>
      </div>
    }>
      <div class="setup-shell">
        <Logo />
        <div class="pick-card">
          <div class="eyebrow">PICK PLAYER 1’S MARK</div>
          <div class="mark-picker">
            <button class={`pick ${player() === "x" ? "selected" : ""}`} onClick={() => setPlayer("x")}><Mark value="x" small /></button>
            <button class={`pick ${player() === "o" ? "selected" : ""}`} onClick={() => setPlayer("o")}><Mark value="o" small /></button>
          </div>
          <div class="reminder">REMEMBER : X GOES FIRST</div>
        </div>
        <button class="wide-button gold-button" onClick={() => start("cpu")}>NEW GAME (VS CPU)</button>
        <button class="wide-button teal-button" onClick={() => start("player")}>NEW GAME (VS PLAYER)</button>
      </div>
    </Show>
    <Show when={screen() === "game" && (result() || restart())}>
      <div class="overlay">
        <div class="result-panel">
          <Show when={!restart()}><div class="eyebrow">{resultCaption()}</div></Show>
          <div class={`result-title ${result()?.winner === "o" ? "gold-text" : ""}`}>
            <Show when={!restart() && result()?.winner !== "tie"}><Mark value={result()?.winner} small /></Show>
            <div>{restart() ? "RESTART GAME?" : result()?.winner === "tie" ? "ROUND TIED" : "TAKES THE ROUND"}</div>
          </div>
          <div class="result-actions">
            <button class="silver-button" onClick={() => restart() ? setRestart(false) : quit()}>{restart() ? "NO, CANCEL" : "QUIT"}</button>
            <button class="gold-button" onClick={clearRound}>{restart() ? "YES, RESTART" : "NEXT ROUND"}</button>
          </div>
        </div>
      </div>
    </Show>
  </div>;
}
