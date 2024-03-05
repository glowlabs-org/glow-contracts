import { defineConfig } from '@wagmi/cli';
import { foundry } from '@wagmi/cli/plugins';
import { type FoundryConfig } from '@wagmi/cli/plugins';
import { react } from '@wagmi/cli/plugins';

export default defineConfig({
  plugins: [
    react(),
    foundry({
      artifacts: 'out/',
      include: ['MinerPoolAndGCA*.json'],
    }),
  ],
  out: 'wagmi-types/generated.ts',
});
