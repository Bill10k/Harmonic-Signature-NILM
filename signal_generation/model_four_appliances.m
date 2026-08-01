function sim = model_four_appliances()
%MODEL_FOUR_APPLIANCES
% Clean appliance current simulation for NILM harmonic-signature project.
%
% Output:
% sim.t               = common time vector, seconds
% sim.fs              = sampling frequency, Hz
% sim.currents        = N x 4 matrix, appliance currents in amperes
% sim.aggregateClean  = N x 1 clean aggregate current in amperes
% sim.sampleStates    = N x 4 logical ON/OFF labels per sample
% sim.windowStates    = W x 4 logical ON/OFF labels per analysis window
% sim.metadata        = reproducibility information and appliance parameters

clc;
close all;

%% ============================================================
% Common simulation settings
%% ============================================================

rng(7);                         % Reproducibility seed
fs = 4000;                      % Low-cost ADC sampling frequency, Hz
f0 = 50;                        % Fundamental grid frequency, Hz
duration = 12;                  % Total simulation time, seconds

t = (0:1/fs:duration-1/fs).';   % Common time vector
N = length(t);

outDir = 'appliance_model_figures';
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% ============================================================
% Appliance definitions
% Harmonic table columns:
% [harmonic_order, magnitude_ratio_to_fundamental, phase_deg]
%% ============================================================

appliances(1) = makeAppliance( ...
    1, ...
    'Electric Kettle / Resistive Heater', ...
    'Resistive heating load', ...
    6.0, ...
    0, ...
    [1  1.00    0; ...
     3  0.020  20; ...
     5  0.010 -35], ...
    [1.0 5.5; 8.5 11.5], ...
    struct('type','soft_ramp','tau',0.06) ...
);

appliances(2) = makeAppliance( ...
    2, ...
    'Refrigerator Compressor Motor', ...
    'Inductive motor load', ...
    2.0, ...
    -35, ...
    [1  1.00  -35; ...
     3  0.080 -80; ...
     5  0.050 110; ...
     7  0.025  40], ...
    [2.5 10.0], ...
    struct('type','motor_inrush','factor',3.2,'tau',0.35, ...
           'transientRatio',0.25,'transientOrder',6,'transientTau',0.20) ...
);

appliances(3) = makeAppliance( ...
    3, ...
    'LED Lamp Bank / Rectifier Driver', ...
    'Nonlinear rectifier lighting load', ...
    0.7, ...
    5, ...
    [1   1.00   5; ...
     3   0.55 -10; ...
     5   0.35  60; ...
     7   0.22 -50; ...
     9   0.14  20; ...
     11  0.10 -90], ...
    [0.5 3.5; 4.8 9.2; 10.0 12.0], ...
    struct('type','soft_ramp','tau',0.03) ...
);

appliances(4) = makeAppliance( ...
    4, ...
    'Laptop Charger / Switch-Mode Power Supply', ...
    'Switch-mode power supply load', ...
    1.1, ...
    18, ...
    [1   1.00   18; ...
     3   0.25  -40; ...
     5   0.50   70; ...
     7   0.40 -110; ...
     11  0.26  130; ...
     13  0.18  -70; ...
     15  0.10   30], ...
    [6.0 12.0], ...
    struct('type','charger_inrush','factor',1.8, ...
           'tauRise',0.04,'tauDecay',0.20) ...
);

numApps = length(appliances);

%% ============================================================
% Generate appliance currents and sample-level state labels
%% ============================================================

currents = zeros(N, numApps);
sampleStates = false(N, numApps);

for k = 1:numApps
    [currents(:,k), sampleStates(:,k)] = synthApplianceCurrent(appliances(k), t, f0);
end

aggregateClean = sum(currents, 2);

%% ============================================================
% Analysis window labels
%% ============================================================

windowLengthSec = 0.20;     % 10 cycles at 50 Hz
hopLengthSec = 0.10;        % 50% overlap

[windowStates, windowStartSamples, windowStopSamples, windowCenterTime] = ...
    makeWindowStates(sampleStates, fs, windowLengthSec, hopLengthSec);

%% ============================================================
% Metadata and output structure
%% ============================================================

sim = struct();
sim.t = t;
sim.fs = fs;
sim.f0 = f0;
sim.duration = duration;
sim.units = 'amperes';
sim.currents = currents;
sim.aggregateClean = aggregateClean;
sim.sampleStates = sampleStates;
sim.windowStates = windowStates;
sim.windowStartSamples = windowStartSamples;
sim.windowStopSamples = windowStopSamples;
sim.windowCenterTime = windowCenterTime;
sim.appliances = appliances;

sim.metadata = struct();
sim.metadata.modelVersion = 'clean_appliance_model_v1';
sim.metadata.createdBy = 'Appliance signal generation module';
sim.metadata.description = ...
    'Four clean appliance current models with distinct harmonic signatures and ground-truth labels.';
sim.metadata.fs_Hz = fs;
sim.metadata.fundamental_Hz = f0;
sim.metadata.duration_s = duration;
sim.metadata.windowLength_s = windowLengthSec;
sim.metadata.hopLength_s = hopLengthSec;
sim.metadata.maxModelledHarmonic = 15;
sim.metadata.nyquist_Hz = fs/2;
sim.metadata.note = ...
    'This file does not include feeder sag, dropout, or external supply distortion. Those should be added by the disturbance module.';

save('clean_appliance_models.mat', 'sim');

%% ============================================================
% Print summary in Command Window
%% ============================================================

names = cell(numApps,1);
types = cell(numApps,1);
Irms = zeros(numApps,1);
phase = zeros(numApps,1);

for k = 1:numApps
    names{k} = appliances(k).name;
    types{k} = appliances(k).loadType;
    Irms(k) = appliances(k).fundamentalRMS_A;
    phase(k) = appliances(k).fundamentalPhase_deg;
end

summaryTable = table((1:numApps).', names, types, Irms, phase, ...
    'VariableNames', {'ID','Appliance','LoadType','FundamentalRMS_A','FundamentalPhase_deg'});

disp(summaryTable);

fprintf('\nClean aggregate current generated successfully.\n');
fprintf('Saved output file: clean_appliance_models.mat\n');
fprintf('Saved figures in folder: %s\n\n', outDir);

%% ============================================================
% Figure 1: each appliance waveform and FFT spectrum - FAST VERSION
%% ============================================================

fig = figure('Visible','off','Name','Each appliance waveform and FFT spectrum', ...
    'Position',[100 100 1200 850]);

for k = 1:numApps

    idx = chooseSteadySegment(t, sampleStates(:,k), fs, 0.50);
    xseg = currents(idx,k);
    tseg = t(idx) - t(idx(1));

    shortIdx = 1:min(length(tseg), round(0.10*fs));

    [freq, mag] = singleSidedSpectrum(xseg, fs);

    % Only plot useful frequency range to prevent freezing
    fmax_plot = 850;
    keep = freq <= fmax_plot;

    subplot(numApps, 2, 2*k-1);
    plot(tseg(shortIdx), xseg(shortIdx), 'LineWidth', 1.1);
    grid on;
    xlabel('Time (s)');
    ylabel('Current (A)');
    title(['Waveform: ', appliances(k).name], 'Interpreter','none');

    subplot(numApps, 2, 2*k);
    plot(freq(keep), mag(keep), 'LineWidth', 1.2);
    grid on;
    xlabel('Frequency (Hz)');
    ylabel('Magnitude (A peak)');
    title(['FFT Spectrum: ', appliances(k).name], 'Interpreter','none');
    xlim([0 fmax_plot]);
end

saveas(fig, fullfile(outDir, 'figure1_all_appliances_waveform_fft.png'));
close(fig);

%% ============================================================
% Figure 2: all four appliance currents on aligned time axes
%% ============================================================

fig = figure('Visible','off','Name','Aligned appliance currents', ...
    'Position',[120 120 1100 800]);

for k = 1:numApps
    subplot(numApps,1,k);
    plot(t, currents(:,k), 'LineWidth', 1.0);
    grid on;
    xlabel('Time (s)');
    ylabel('Current (A)');
    title(['Current waveform: ', appliances(k).name], 'Interpreter','none');
    xlim([0 duration]);
end

saveas(fig, fullfile(outDir, 'figure2_aligned_appliance_currents.png'));
close(fig);

%% ============================================================
% Figure 3: clean aggregate current and ON/OFF timeline
%% ============================================================

fig = figure('Visible','off','Name','Aggregate current and state timeline', ...
    'Position',[140 140 1150 700]);

subplot(2,1,1);
plot(t, aggregateClean, 'LineWidth', 1.0);
grid on;
xlabel('Time (s)');
ylabel('Current (A)');
title('Clean Aggregate Current');
xlim([0 duration]);

subplot(2,1,2);
hold on;
spacing = 1.35;

for k = 1:numApps
    base = spacing*(k-1);
    stairs(t, base + double(sampleStates(:,k)), 'LineWidth', 1.4);
end

grid on;
xlabel('Time (s)');
ylabel('Appliance state');
title('Ground-Truth ON/OFF State Timeline');
xlim([0 duration]);

yticks(0.5 + spacing*(0:numApps-1));
yticklabels({'Kettle','Motor','LED Driver','Laptop Charger'});
ylim([-0.25 spacing*(numApps-1)+1.25]);

saveas(fig, fullfile(outDir, 'figure3_clean_aggregate_and_states.png'));
close(fig);

%% ============================================================
% Figure 4: comparison showing why appliances are distinguishable
%% ============================================================

ordersToCompare = [1 3 5 7 9 11 13 15];
ratioMatrix = zeros(numApps, length(ordersToCompare));

for k = 1:numApps
    H = appliances(k).harmonics;
    for m = 1:length(ordersToCompare)
        order = ordersToCompare(m);
        loc = find(H(:,1) == order, 1);
        if ~isempty(loc)
            ratioMatrix(k,m) = H(loc,2);
        end
    end
end

fig = figure('Visible','off','Name','Harmonic signature comparison', ...
    'Position',[160 160 1100 600]);

bar(ordersToCompare, ratioMatrix.', 'grouped');
grid on;
xlabel('Harmonic order');
ylabel('Magnitude ratio relative to fundamental');
title('Harmonic Signature Comparison of the Four Appliances');

legend({'Kettle / Heater','Motor','LED Driver','Laptop Charger'}, ...
    'Location','northeast');

saveas(fig, fullfile(outDir, 'figure4_harmonic_signature_comparison.png'));
close(fig);

%% ============================================================
% Figure 5: window-level ground truth labels
%% ============================================================

fig = figure('Visible','off','Name','Window labels', ...
    'Position',[180 180 1100 550]);

imagesc(windowCenterTime, 1:numApps, windowStates.');
colormap(gray);
xlabel('Window centre time (s)');
ylabel('Appliance');
title('Ground-Truth Appliance States per Analysis Window');
yticks(1:numApps);
yticklabels({'Kettle','Motor','LED Driver','Laptop Charger'});
colorbar;

saveas(fig, fullfile(outDir, 'figure5_window_ground_truth_labels.png'));
close(fig);

%% ============================================================
% Helper function: create appliance metadata
%% ============================================================

function A = makeAppliance(id, name, loadType, fundamentalRMS_A, fundamentalPhase_deg, harmonics, onIntervals, startup)

A = struct();
A.id = id;
A.name = name;
A.loadType = loadType;
A.fundamentalRMS_A = fundamentalRMS_A;
A.fundamentalPeak_A = sqrt(2)*fundamentalRMS_A;
A.fundamentalPhase_deg = fundamentalPhase_deg;
A.harmonics = harmonics;
A.harmonicColumns = {'order','magnitudeRatioToFundamental','phaseDegrees'};
A.onIntervals_s = onIntervals;
A.startup = startup;

end

%% ============================================================
% Helper function: synthesize one appliance current
%% ============================================================

function [current, state] = synthApplianceCurrent(A, t, f0)

N = length(t);
state = false(N,1);
envelope = zeros(N,1);
startupTransient = zeros(N,1);

for e = 1:size(A.onIntervals_s,1)

    tOn = A.onIntervals_s(e,1);
    tOff = A.onIntervals_s(e,2);

    idx = (t >= tOn) & (t < tOff);
    tau = t(idx) - tOn;

    state(idx) = true;

    switch lower(A.startup.type)

        case 'instant'
            env = ones(size(tau));

        case 'soft_ramp'
            env = 1 - exp(-tau/A.startup.tau);

        case 'motor_inrush'
            env = 1 + (A.startup.factor - 1)*exp(-tau/A.startup.tau);

            transientPeak = sqrt(2)*A.fundamentalRMS_A*A.startup.transientRatio;
            startupTransient(idx) = transientPeak .* exp(-tau/A.startup.transientTau) .* ...
                sin(2*pi*A.startup.transientOrder*f0*t(idx) + deg2rad(90));

        case 'charger_inrush'
            rise = 1 - exp(-tau/A.startup.tauRise);
            decayBoost = 1 + (A.startup.factor - 1)*exp(-tau/A.startup.tauDecay);
            env = rise .* decayBoost;

        otherwise
            error(['Unknown startup type: ', A.startup.type]);
    end

    envelope(idx) = env;
end

base = zeros(N,1);
H = A.harmonics;

for r = 1:size(H,1)
    order = H(r,1);
    ratio = H(r,2);
    phaseRad = deg2rad(H(r,3));

    peakAmp = sqrt(2)*A.fundamentalRMS_A*ratio;

    base = base + peakAmp*sin(2*pi*order*f0*t + phaseRad);
end

current = envelope .* base + startupTransient;

end

%% ============================================================
% Helper function: sample states to window states
%% ============================================================

function [windowStates, startSamples, stopSamples, centreTime] = ...
    makeWindowStates(sampleStates, fs, windowLengthSec, hopLengthSec)

N = size(sampleStates,1);
numApps = size(sampleStates,2);

winLength = round(windowLengthSec*fs);
hopLength = round(hopLengthSec*fs);

numWindows = floor((N - winLength)/hopLength) + 1;

windowStates = false(numWindows, numApps);
startSamples = zeros(numWindows,1);
stopSamples = zeros(numWindows,1);
centreTime = zeros(numWindows,1);

for w = 1:numWindows
    s1 = (w-1)*hopLength + 1;
    s2 = s1 + winLength - 1;

    startSamples(w) = s1;
    stopSamples(w) = s2;
    centreTime(w) = ((s1+s2)/2 - 1)/fs;

    windowStates(w,:) = mean(sampleStates(s1:s2,:), 1) >= 0.5;
end

end

%% ============================================================
% Helper function: choose an ON segment away from startup
%% ============================================================

function idx = chooseSteadySegment(t, state, fs, segmentLengthSec)

segLen = round(segmentLengthSec*fs);
onIdx = find(state);

if isempty(onIdx)
    idx = 1:min(segLen, length(t));
    return;
end

% Find continuous ON blocks safely
gapLocations = find(diff(onIdx) > 1);

blockStarts = [onIdx(1); onIdx(gapLocations + 1)];
blockStops  = [onIdx(gapLocations); onIdx(end)];

blockLengths = blockStops - blockStarts + 1;
[~, bestBlock] = max(blockLengths);

bestStart = blockStarts(bestBlock);
bestStop = blockStops(bestBlock);

% Avoid startup transient if possible
safeStart = bestStart + round(0.5*fs);

if safeStart + segLen - 1 <= bestStop
    idx = safeStart:(safeStart + segLen - 1);
elseif bestStart + segLen - 1 <= bestStop
    idx = bestStart:(bestStart + segLen - 1);
else
    idx = bestStart:bestStop;
end

end

%% ============================================================
% Helper function: single-sided FFT spectrum
%% ============================================================

function [freq, mag] = singleSidedSpectrum(x, fs)

x = x(:);
N = length(x);

if N < 2
    freq = 0;
    mag = abs(x);
    return;
end

% Hann window written manually to avoid toolbox dependency
w = 0.5 - 0.5*cos(2*pi*(0:N-1)'/(N-1));

xw = x .* w;

Nfft = 2^nextpow2(4*N);

X = fft(xw, Nfft);

freq = (0:Nfft/2)' * fs/Nfft;

% Amplitude-corrected single-sided magnitude
mag = abs(X(1:Nfft/2+1)) * 2 / sum(w);

end

end