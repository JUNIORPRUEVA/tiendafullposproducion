typedef AsyncStep = Future<void> Function();

Future<void> runInitialReleaseCheck({
  required AsyncStep ensureStartupReady,
  required AsyncStep checkForUpdates,
}) async {
  try {
    await ensureStartupReady();
  } catch (_) {
    // Startup already reports its own failures. Keep the release check alive so
    // it can recover as soon as configuration becomes available.
  }

  await checkForUpdates();
}
