function sqrt(x: bigint): bigint {
  if (x < BigInt(256)) {
    for (let i = BigInt(0); i * i <= x; i++) {
      if (i * i === x) return i;
    }
    return BigInt(0);
  }

  let y: bigint = x;
  let z: bigint = BigInt(181);

  if (y >= BigInt(0x10000000000000000000000000000000000)) {
    y >>= BigInt(128);
    z <<= BigInt(64);
  }
  if (y >= BigInt(0x1000000000000000000)) {
    y >>= BigInt(64);
    z <<= BigInt(32);
  }
  if (y >= 0x10000000000) {
    y >>= BigInt(32);
    z <<= BigInt(16);
  }
  if (y >= BigInt(0x1000000)) {
    y >>= BigInt(16);
    z <<= BigInt(8);
  }

  z = (z * (y + BigInt(65536))) >> BigInt(18);

  for (let i = 0; i < 7; i++) {
    z = (z + x / z) >> BigInt(1);
  }

  z -= x / z < z ? BigInt(1) : BigInt(0);
  return z;
}

function findOptimalAmountToSwap(
  amountToCommit: bigint,
  totalReservesOfToken: bigint,
): bigint {
  const a = sqrt(totalReservesOfToken) + BigInt(1);
  console.log('a', a.toString());
  const b = sqrt(
    BigInt(3988000) * amountToCommit + BigInt(3988009) * totalReservesOfToken,
  );
  console.log('b', b.toString());
  const c = BigInt(1997) * totalReservesOfToken;
  console.log('c', c.toString());
  const d = BigInt(1994);

  const p1 = a * b;
  const p2 = p1 - c;
  const p3 = p2 / d;
  console.log('p1=', p1.toString());
  console.log('p2=', p2.toString());
  console.log('p3=', p3.toString());

  if (c > a * b) {
    throw new Error('Precision loss leads to underflow');
  }

  const res = (a * b - c) / d;
  return res;
}

// Example usage of the function
try {
  const amountToCommit = BigInt(1000); // Example amount to commit
  const totalReservesOfToken = BigInt(120313135); // Example total reserves of token
  const optimalAmount = findOptimalAmountToSwap(
    amountToCommit,
    totalReservesOfToken,
  );
  console.log('Optimal Amount to Swap:', optimalAmount.toString());
} catch (error) {
  console.error(error);
}

function getAmountOut(
  amountIn: bigint,
  reserveIn: bigint,
  reserveOut: bigint,
): bigint {
  if (amountIn <= BigInt(0)) {
    throw new Error('UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
  }
  if (reserveIn <= BigInt(0) || reserveOut <= BigInt(0)) {
    throw new Error('UniswapV2Library: INSUFFICIENT_LIQUIDITY');
  }

  const amountInWithFee = amountIn * BigInt(997);
  const numerator = amountInWithFee * reserveOut;
  const denominator = reserveIn * BigInt(1000) + amountInWithFee;
  const amountOut = numerator / denominator;

  return amountOut;
}
