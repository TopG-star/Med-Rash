// Static Tailwind width classes for dynamic 0..100% bars. The JIT compiler
// needs to see each class literal in source, so we list them all here and
// look up by rounded bucket. Used by Dashboard and Intelligence panels.
//
// Keep the unused-reference string below — it exists solely so the JIT
// scanner finds every class name.
//
// w-[0%] w-[5%] w-[10%] w-[15%] w-[20%] w-[25%] w-[30%] w-[35%] w-[40%]
// w-[45%] w-[50%] w-[55%] w-[60%] w-[65%] w-[70%] w-[75%] w-[80%] w-[85%]
// w-[90%] w-[95%] w-[100%]

const WIDTH_CLASSES: Record<number, string> = {
  0: "w-[0%]",
  5: "w-[5%]",
  10: "w-[10%]",
  15: "w-[15%]",
  20: "w-[20%]",
  25: "w-[25%]",
  30: "w-[30%]",
  35: "w-[35%]",
  40: "w-[40%]",
  45: "w-[45%]",
  50: "w-[50%]",
  55: "w-[55%]",
  60: "w-[60%]",
  65: "w-[65%]",
  70: "w-[70%]",
  75: "w-[75%]",
  80: "w-[80%]",
  85: "w-[85%]",
  90: "w-[90%]",
  95: "w-[95%]",
  100: "w-[100%]",
};

export function widthClassFromPercent(percent: number): string {
  if (!Number.isFinite(percent) || percent <= 0) return WIDTH_CLASSES[0];
  if (percent >= 100) return WIDTH_CLASSES[100];
  const bucket = Math.round(percent / 5) * 5;
  return WIDTH_CLASSES[bucket] ?? WIDTH_CLASSES[50];
}
