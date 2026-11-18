import { runStableContract } from "./solid-stable-contract.js";

const result = await runStableContract();
console.log(`PASS Solid 2 stable contracts: ${result.checks} checks (development=${result.development})`);
