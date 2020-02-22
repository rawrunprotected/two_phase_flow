// Compatibility definitions for FFTW generated codelets
typedef float R;
typedef float E;

#define FMA(a, b, c) mad(a, b, c)
#define FMS(a, b, c) mad(a, b, -c)
#define FNMA(a, b, c) (-mad(a, b, c))
#define FNMS(a, b, c) (-mad(a, b, -c))
#define DK(cnst, val) static const float cnst = float(val)