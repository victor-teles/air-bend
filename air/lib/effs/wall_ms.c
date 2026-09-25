// Clock
// =====

// Milliseconds since the Unix epoch, as decimal text: the number does
// not fit a U32.
Term wall_ms_run(Env e, Term* f, IoWork* w) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  char buf[32];
  int n = snprintf(buf, sizeof buf, "%llu",
    (unsigned long long)ts.tv_sec * 1000ull + (unsigned long long)(ts.tv_nsec / 1000000));
  return io_str(e, buf, (u64)n);
}

static void __attribute__((constructor)) wall_ms_use(void) {
  io_eff(CID_WALL_MS, wall_ms_run, 0);
}
