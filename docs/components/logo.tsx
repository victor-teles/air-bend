export function Logo() {
  return (
    <span className="inline-flex items-center gap-2 font-semibold">
      <span
        aria-hidden
        className="size-5 bg-air-gradient"
        style={{ mask: 'url(/icon.svg) center / contain no-repeat' }}
      />
      <span className="text-air-gradient">Air Bend</span>
    </span>
  );
}
