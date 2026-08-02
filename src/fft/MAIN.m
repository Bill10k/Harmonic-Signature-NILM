clc
clear
close all

% Load Signal
[signal, Fs] = loadSignal();

% FFT
[frequency, magnitude] = computeFFT(signal, Fs);

% Plot Spectrum
plotSpectrum(frequency, magnitude);

% Extract Harmonics
harmonics = extractHarmonics(frequency, magnitude);

disp(harmonics)