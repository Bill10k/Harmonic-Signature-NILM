clear;
clc;
close all;

addpath(genpath('src'));

params = defaultParameters();

params.plotResults = true;

sim = model_four_appliances(params);

aggregateCurrent = sim.aggregateClean;

disturbedSignal = applyDisturbances(aggregateCurrent, params);

filteredSignal = applyFIRFilter(disturbedSignal, params);

[freq, spectrum] = performFFT(filteredSignal, params);

features = extractFeatures(freq, spectrum, params);

predictions = classifyLoad(features, params);

results = evaluateSystem(sim.windowStates, predictions);

disp(results);