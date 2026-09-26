#ifndef Reynard_VideoRemux_h
#define Reynard_VideoRemux_h

// Input is a locally downloaded playlist/media file. Network is disabled.
int ReynardRemuxVideo(const char *inputPath, const char *outputPath);
// Returns a finite media duration when a video track exists, or -1.
double ReynardVideoDuration(const char *inputPath);

#endif
