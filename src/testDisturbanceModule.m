%% testDisturbanceModule.m
% Standalone test for the disturbance module (applyVoltageSag,
% addHarmonicDistortion, applyInterruption, addGaussianNoise,
% applyDisturbances) using the REAL signal generation output.
%

clc; clear; close all;
addpath(genpath('src'));

%% Use the same params as main.m, plus disturbance placeholder settings
params = defaultParameters();

% --- Disturbance placeholder parameters ---
% These are NOT the assigned Group 3 values yet (still waiting on the
% parameter sheet). They are realistic placeholders from the brief's own
% examples, clearly separated here so they're easy to update later.
params.sag.enable        = true;
params.sag.depth          = 0.30;
params.sag.startTime_s    = 6.5;   % during multi-appliance overlap
params.sag.duration_s     = 0.5;

params.harmonics.enable       = true;
params.harmonics.orders       = 3;
params.harmonics.magnitudePct = 0.05;
params.harmonics.phaseDeg     = 0;

params.dropout.enable        = true;
params.dropout.startTime_s    = 9.0;
params.dropout.duration_s     = 0.2;
params.dropout.residualLevel  = 0.05;
params.dropout.rampTime_s     = 0.02;

params.noise.enable = true;
params.noise.snrDb  = 30;

%% Generate the real clean aggregate signal
sim = model_four_appliances(params);
cleanSignal = sim.aggregateClean;
t = sim.t;
fs = sim.fs;

%% Apply disturbances
disturbedSignal = applyDisturbances(cleanSignal, params);

fprintf('Clean signal length: %d samples (%.1f s at %d Hz)\n', ...
    length(cleanSignal), length(cleanSignal)/fs, fs);
fprintf('Disturbed signal length: %d samples\n', length(disturbedSignal));

%% Plot: time domain before/after
figure('Name', 'Disturbance Module Test: Time Domain');
subplot(2,1,1);
plot(t, cleanSignal, 'b');
title('Clean Aggregate Current (real signal generation module)');
xlabel('Time (s)'); ylabel('Current (A)'); grid on;

subplot(2,1,2);
plot(t, disturbedSignal, 'r');
title('Disturbed Aggregate Current (sag + 3rd harmonic + noise + dropout)');
xlabel('Time (s)'); ylabel('Current (A)'); grid on;

%% Plot: before/after spectra
N = length(cleanSignal);
NFFT = 2^nextpow2(N);
f = fs/2 * linspace(0, 1, NFFT/2 + 1);

Xclean = fft(cleanSignal, NFFT) / N;
Xdisturbed = fft(disturbedSignal, NFFT) / N;

figure('Name', 'Disturbance Module Test: Frequency Domain');
subplot(2,1,1);
stem(f, 2*abs(Xclean(1:NFFT/2+1)), 'b', 'Marker', 'none');
xlim([0 800]);
title('Spectrum: Clean Aggregate Signal');
xlabel('Frequency (Hz)'); ylabel('|Amplitude|'); grid on;

subplot(2,1,2);
stem(f, 2*abs(Xdisturbed(1:NFFT/2+1)), 'r', 'Marker', 'none');
xlim([0 800]);
title('Spectrum: Disturbed Signal (look for added energy at 150 Hz + raised noise floor)');
xlabel('Frequency (Hz)'); ylabel('|Amplitude|'); grid on;

fprintf('\nDisturbance module test complete. Check the figures.\n');
