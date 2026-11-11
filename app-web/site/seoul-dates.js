const seoulDay = new Intl.DateTimeFormat("sv-SE", {
  timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit",
});

export const datePresets = Object.freeze({ today: "今天", weekend: "这周末", "next-week": "下周" });

export function dayInSeoul(date = new Date()) {
  return seoulDay.format(date);
}

export function shiftDay(day, amount) {
  const date = new Date(day + "T00:00:00Z");
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
}

export function validDay(value) {
  if (!/^20\d{2}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(value + "T00:00:00Z");
  return Number.isFinite(date.valueOf()) && date.toISOString().startsWith(value);
}

export function dateRange(preset, today = dayInSeoul()) {
  const weekday = (new Date(today + "T00:00:00Z").getUTCDay() + 6) % 7;
  if (preset === "today") return [today, today];
  if (preset === "weekend") return [shiftDay(today, Math.max(0, 5 - weekday)), shiftDay(today, 6 - weekday)];
  if (preset === "next-week") return [shiftDay(today, 7 - weekday), shiftDay(today, 13 - weekday)];
  return null;
}

export function dateQuery([first, last]) {
  return {
    from: new Date(first + "T00:00:00+09:00").toISOString(),
    to: new Date(new Date(shiftDay(last, 1) + "T00:00:00+09:00").valueOf() - 1).toISOString(),
  };
}
