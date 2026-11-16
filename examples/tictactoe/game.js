export const winningLines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8],
  [0, 3, 6], [1, 4, 7], [2, 5, 8],
  [0, 4, 8], [2, 4, 6],
];

export function outcome(board) {
  const line = winningLines.find(([a, b, c]) => board[a] && board[a] === board[b] && board[a] === board[c]);
  if (line) return { winner: board[line[0]], line };
  return board.every(Boolean) ? { winner: "tie", line: [] } : null;
}

// Minimax keeps the CPU consistent across runs and never plays an occupied cell.
export function cpuMove(board, mark) {
  const other = mark === "x" ? "o" : "x";
  function score(cells, turn, depth) {
    const result = outcome(cells);
    if (result) return result.winner === "tie" ? 0 : result.winner === mark ? 10 - depth : depth - 10;
    const values = cells.flatMap((cell, index) => {
      if (cell) return [];
      const next = cells.slice();
      next[index] = turn;
      return [score(next, turn === "x" ? "o" : "x", depth + 1)];
    });
    return turn === mark ? Math.max(...values) : Math.min(...values);
  }
  let best = -Infinity;
  let move = -1;
  for (const index of [4, 0, 2, 6, 8, 1, 3, 5, 7]) {
    if (board[index]) continue;
    const next = board.slice();
    next[index] = mark;
    const value = score(next, other, 0);
    if (value > best) { best = value; move = index; }
  }
  return move;
}
