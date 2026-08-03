%% Harmonic Signature NILM
% Main Pipeline

clc;
clear;
close all;

addpath(genpath('src'));

%% Project Configuration

params = struct();

params.fs = 4000;
params.f0 = 50;
params.duration = 12;
params.windowLength = 0.20;
params.hopLength = 0.10;

%% Signal Generation

sim = model_four_appliances(params);

%% Aggregate Signal

aggregateCurrent = sim.aggregateClean;

groundTruth = sim.windowStates;

%% Disturbance Module

disturbedSignal = applyDisturbances(aggregateCurrent, params);

%% Preprocessing

filteredSignal = applyFIRFilter(disturbedSignal, params);

%% FFT + Feature Extraction (Window by Window)

numWindows = size(sim.windowStates,1);

features = repmat(struct(), numWindows, 1);

for k = 1:numWindows

    startIdx = sim.windowStartSamples(k);
    stopIdx  = sim.windowStopSamples(k);

    signalWindow = filteredSignal(startIdx:stopIdx);

    [frequency, magnitude] = performFFT(signalWindow, params);

    features(k) = extractFeatures(frequency, magnitude);

end

%% Classification

[predictions, predictionMatrix] = classifyLoad(features);

%% Evaluation

results = evaluateSystem(sim.windowStates, predictionMatrix);

disp(results)