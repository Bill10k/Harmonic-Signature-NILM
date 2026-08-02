%% Harmonic Signature NILM
% Main Pipeline

clc;
clear;
close all;

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

%% Disturbance Module

disturbedSignal = applyDisturbances(aggregateCurrent, params);

%% Preprocessing

filteredSignal = applyFIRFilter(disturbedSignal, params);

%% FFT

[frequency, magnitude] = performFFT(filteredSignal, params);

%% Feature Extraction

features = extractFeatures(frequency, magnitude);

%% Classification

predictions = classifyLoad(features);

%% Evaluation

results = evaluateSystem(sim.windowStates, predictions);

disp(results)