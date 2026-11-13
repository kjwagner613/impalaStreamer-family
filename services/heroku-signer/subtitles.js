export function srtToWebVtt(value) {
  const source = String(value || "").replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
  const lines = source.split("\n").map((line) => line.replace(
    /^(\d{1,2}:\d{2}:\d{2})[,.](\d{1,3})(\s+-->\s+)(\d{1,2}:\d{2}:\d{2})[,.](\d{1,3})(.*)$/,
    (_match, start, startMs, arrow, end, endMs, settings) => (
      `${start}.${startMs.padStart(3, "0")}${arrow}${end}.${endMs.padStart(3, "0")}${settings}`
    )
  ));
  if (/^WEBVTT(?:\s|$)/i.test(lines[0] || "")) {
    lines.shift();
  }
  return `WEBVTT\n\n${lines.join("\n").replace(/^\n+/, "")}`;
}
