#ifndef CRASHREPORTER_H
#define CRASHREPORTER_H

typedef enum {
	kCrashReporterStateNotActive = 0,
	kCrashReporterStateActive = 1,
	kCrashReporterStatePaused = 2
} crash_reporter_state;

void crashreporter_start();
// Pair every pause with exactly one resume. Overlapping scopes share a key;
// only the final scope restores handlers. Zero means the reporter is inactive.
int crashreporter_pause(void);
void crashreporter_resume(int key);

FILE *crashreporter_open_outfile(const char *source, char **nameOut);
void crashreporter_save_outfile(FILE *f);


#endif // CRASHREPORTER_H
