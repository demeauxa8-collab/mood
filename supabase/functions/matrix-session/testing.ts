// Minimal assertions so the tests run offline, without fetching jsr:@std/assert.
// Not deployed: only *_test.ts files import it.

export function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}

export function assertEquals(actual: unknown, expected: unknown, message?: string): void {
  if (!deepEqual(actual, expected)) {
    throw new Error(
      `${message ? message + ": " : ""}values differ\n  actual:   ${show(actual)}\n  expected: ${show(expected)}`,
    );
  }
}

export function assertIncludes(haystack: string, needle: string, message?: string): void {
  if (!haystack.includes(needle)) {
    throw new Error(`${message ? message + ": " : ""}${show(haystack)} does not include ${show(needle)}`);
  }
}

export function assertExcludes(haystack: string, needle: string, message?: string): void {
  if (needle !== "" && haystack.includes(needle)) {
    throw new Error(`${message ? message + ": " : ""}found a forbidden value in the output`);
  }
}

function deepEqual(a: unknown, b: unknown): boolean {
  if (Object.is(a, b)) return true;
  if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const aKeys = Object.keys(a as object).filter((k) => (a as Record<string, unknown>)[k] !== undefined).sort();
  const bKeys = Object.keys(b as object).filter((k) => (b as Record<string, unknown>)[k] !== undefined).sort();
  if (aKeys.length !== bKeys.length || aKeys.some((k, i) => k !== bKeys[i])) return false;
  return aKeys.every((k) => deepEqual((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k]));
}

function show(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}
