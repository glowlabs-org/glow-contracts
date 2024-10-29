import { spawn } from 'bun';
import { Elysia } from 'elysia';
let anvilProcess;
import { Anvil, createAnvil } from '@viem/anvil';
import { getAnvilClient } from './anvil-viem-client';

const MINE_COMMAND = `curl -H "Content-Type: application/json" -X POST --data '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":67}' 127.0.0.1:8545`;
// const DEPLOY_BUCKETS_COMMAND = `forge script script/V2/Local/DeployBucketSimulation.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vvvv --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --non-interactive`;
// const DEPLOY_MULTICALL_COMMAND = `forge script script/V2/Local/D3.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vvvv --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`;
// Helper function to parse a command string into command and arguments
function parseCommand(commandString) {
  const parts = commandString.match(/(?:[^\s"]+|"[^"]*")+/g) || [];
  return parts.map((part) => part.replace(/(^"|"$)/g, '')); // Remove surrounding quotes
}
// Function to run any command from a single command string
function runCommand(commandString) {
  return new Promise((resolve, reject) => {
    const [command, ...args] = parseCommand(commandString);

    const process = spawn({
      cmd: [command, ...args],
      stdout: 'pipe',
      stderr: 'pipe',
    });

    let output = '';
    let errorOutput = '';

    // Pipe stdout to capture output
    process.stdout.pipeTo(
      new WritableStream({
        write(chunk) {
          const message = new TextDecoder().decode(chunk);
          console.log(`Output from ${command}:`, message);
          output += message;
        },
      }),
    );

    // Pipe stderr to capture error output
    process.stderr.pipeTo(
      new WritableStream({
        write(chunk) {
          const message = new TextDecoder().decode(chunk);
          console.error(`Error from ${command}:`, message);
          errorOutput += message;
        },
      }),
    );

    // Resolve or reject the Promise based on exit code
    process.exited.then((code) => {
      if (code === 0) {
        resolve(
          `Command "${commandString}" executed successfully.\nOutput: ${output}`,
        );
      } else {
        reject(
          new Error(
            `Command "${commandString}" failed with code ${code}.\nError: ${errorOutput}`,
          ),
        );
      }
    });
  });
}

// Helper function to run a Make command and capture output
const runMakeCommand = async (command) => {
  const process = spawn({
    cmd: ['make', command],
    stdout: 'pipe',
    stderr: 'pipe',
  });

  process.stdout.pipeTo(
    new WritableStream({
      write(chunk) {
        console.log(`Output from ${command}:`, new TextDecoder().decode(chunk));
      },
    }),
  );

  process.stderr.pipeTo(
    new WritableStream({
      write(chunk) {
        console.error(
          `Error from ${command}:`,
          new TextDecoder().decode(chunk),
        );
      },
    }),
  );

  // Wait for the process to complete
  await process.exited;
  return process.exitCode === 0
    ? `${command} executed successfully.`
    : `${command} failed.`;
};

function getAnvilServer() {
  const anvilServer = createAnvil({
    noMining: true,
    codeSizeLimit: 0x9000,
  });

  return anvilServer;
}

class AnvilListener {
  public anvil: Anvil;
  constructor(anvil: Anvil) {
    this.anvil = anvil;
    this.runListeners();
  }

  runListeners() {
    this.anvil.on('message', (message) => {
      console.log(message);
    });
    this.anvil.on('stdout', (message) => {
      console.log(message);
    });
    this.anvil.on('stderr', (message) => {
      console.log(message);
    });
  }
}

let anvilServer = getAnvilServer();
if (anvilServer.status == 'listening') {
  anvilServer.stop();
}
let anvilListener = new AnvilListener(anvilServer);
const startAnvilServer = async (server: Anvil) => {
  const anvilClient = getAnvilClient();
  await server.start();
  //await forge build
  await runCommand('forge build');
  //   await runCommand(DEPLOY_BUCKETS_COMMAND);
  runMakeCommand('deploy.bucket.simulation.anvil');
  //sleep 5 seconds
  await sleep(1300);

  await anvilClient.mine({ blocks: 1 });
  //   await runCommand(DEPLOY_MULTICALL_COMMAND);
  runMakeCommand('deploy.multicall3.anvil');

  //sleep 5 seconds
  await sleep(1300);

  await anvilClient.mine({ blocks: 1 });
  //   await anvilClient.mine({ blocks: 1 });
  //   await anvilClient.mine({ blocks: 1 });

  //mine 2 more blocks

  //   await runMakeCommand('mine.anvil');
  //   await runMakeCommand('deploy.multicall3.anvil');
  //   await runMakeCommand('mine.anvil');
};

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
await startAnvilServer(anvilServer);
async function main() {
  const app = new Elysia()
    .get('/', () => 'hi!')
    .get('/status', () => {
      return { status: anvilServer.status };
    })
    .get('/restart', async () => {
      try {
        const status = anvilServer.status;
        if (status == 'starting' || status == 'listening') {
          await anvilServer.stop();
          await sleep(1000);
        }
        anvilServer = getAnvilServer();
        anvilListener = new AnvilListener(anvilServer);
        await startAnvilServer(anvilServer);
        return { status: anvilServer.status };
      } catch (err) {
        return { error: err.message };
        throw err;
      }
    })
    .listen(3010);

  console.log('Server started on port 3010');
}

main();
