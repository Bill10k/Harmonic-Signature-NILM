function [signal, Fs] = generateTestSignal()

Fs = 5000;              % Sampling Frequency (Hz)
T = 1;                  % Signal duration (1 second)

t = 0:1/Fs:T-1/Fs;

% Fundamental (50 Hz)
signal = sin(2*pi*50*t);

% Third Harmonic
signal = signal + 0.35*sin(2*pi*150*t);

% Fifth Harmonic
signal = signal + 0.20*sin(2*pi*250*t);

% Seventh Harmonic
signal = signal + 0.10*sin(2*pi*350*t);

% Add Gaussian Noise
signal = signal + 0.05*randn(size(t));

end