%% HARMONIC SIGNATURE NILM - MAIN SCRIPT
%
%  COE 472 Digital Signal Processing, Mini Project 3
%  Harmonic Signature Disaggregation for Load Monitoring on an Unstable Feeder
%  Department of Computer Engineering, KNUST
%
%  Run this file to reproduce every result in the report.
%
%      >> main
%
%  WHAT IT DOES
%    1. Generates four appliance currents and their clean aggregate
%    2. Applies the supply disturbances: sag, background harmonics,
%       interruption and measurement noise
%    3. Runs the DSP pipeline: FIR filter, windowing, FFT, feature
%       extraction, classification
%    4. Scores the result against ground truth and prints the confusion
%       matrices, accuracy and macro-F1
%    5. Saves the report figures into figures/results
%
%  To run on the blind benchmark waveform instead, use:
%
%      >> runBlindTest('path/to/blind_data.mat')

clc;
clear;
close all;

%% ========================================================================
%  Make every module visible on the MATLAB path
%
%  addpath(genpath(...)) is used rather than a list of folders so that a new
%  module folder works without editing this file. The path is set relative
%  to this script's own location, so the project runs from any working
%  directory and on any machine - which the submission checklist requires.
%  ========================================================================

projectRoot = fileparts(mfilename('fullpath'));

if isempty(projectRoot)
    projectRoot = pwd;
end

addpath(genpath(fullfile(projectRoot, 'src')));
addpath(projectRoot);

fprintf('\n');
fprintf('================================================================\n');
fprintf('  HARMONIC SIGNATURE NILM  -  COE 472 Mini Project 3\n');
fprintf('================================================================\n\n');

%% ========================================================================
%  Configuration
%  ========================================================================

params = defaultParameters();

fprintf('CONFIGURATION\n');
fprintf('  Sampling frequency   : %d Hz  (Nyquist %d Hz)\n', params.fs, params.fs/2);
fprintf('  Fundamental          : %d Hz\n', params.f0);
fprintf('  Highest harmonic     : %d  (%d Hz)\n', params.maxHarmonic, params.maxHarmonic*params.f0);
fprintf('  Sampling ratio       : %.1f x the highest harmonic frequency\n', ...
    params.fs / (params.maxHarmonic * params.f0));
fprintf('  Nyquist margin       : %.1f x the minimum rate Nyquist demands\n', ...
    params.fs / (2 * params.maxHarmonic * params.f0));
fprintf('  Recording length     : %g s\n', params.duration);
fprintf('  Analysis window      : %g s  (%g cycles), hop %g s\n', ...
    params.windowLength, params.windowLength*params.f0, params.hopLength);
fprintf('  Classifier           : %s\n\n', params.classifierMethod);

%% ========================================================================
%  STAGE 1 - Signal generation
%  ========================================================================

fprintf('STAGE 1  Signal generation\n');

simParams = params;
simParams.plotResults = false;      % the appliance figures already exist

sim = model_four_appliances(simParams);

aggregateCurrent = sim.aggregateClean;

fprintf('  Clean aggregate RMS  : %.3f A\n', sqrt(mean(aggregateCurrent.^2)));
fprintf('  Ground-truth windows : %d\n\n', size(sim.windowStates, 1));

%% ========================================================================
%  STAGE 2 - Supply disturbances
%  ========================================================================

fprintf('STAGE 2  Supply disturbances\n');

[disturbedSignal, disturbanceInfo] = applyDisturbances(aggregateCurrent, params);

if disturbanceInfo.sag.applied
    fprintf('  Voltage sag          : %.0f%% for %g s (%s)\n', ...
        100*disturbanceInfo.sag.depth_fraction, ...
        disturbanceInfo.sag.duration_s, ...
        disturbanceInfo.sag.category);
else
    fprintf('  Voltage sag          : not applied\n');
end

if disturbanceInfo.distortion.applied
    fprintf('  Background THD       : %.1f%% at orders %s\n', ...
        disturbanceInfo.distortion.targetTHD_percent, ...
        mat2str(disturbanceInfo.distortion.orders));
else
    fprintf('  Background THD       : not applied\n');
end

if disturbanceInfo.interruption.applied
    fprintf('  Interruption         : %g s from t = %g s\n', ...
        disturbanceInfo.interruption.duration_s, ...
        disturbanceInfo.interruption.startTime_s);
else
    fprintf('  Interruption         : not applied\n');
end

if disturbanceInfo.noise.applied
    fprintf('  Measurement noise    : %.1f dB SNR\n', ...
        disturbanceInfo.noise.achievedSNR_dB);
else
    fprintf('  Measurement noise    : not applied\n');
end
fprintf('  RMS change           : %+.2f %%\n\n', disturbanceInfo.rmsChange_percent);

%% ========================================================================
%  STAGES 3 to 6 - The DSP pipeline and evaluation
%
%  Deliberately delegated to runPipeline so that the blind test runs the
%  identical code path.
%  ========================================================================

fprintf('STAGES 3-6  DSP pipeline\n');

params.evaluationLabel = 'Results on our own simulated recording';

output = runPipeline(disturbedSignal, params, sim.windowStates);

results = output.results;

%% ========================================================================
%  Comparison: rule-based classifier, given its best possible chance
%
%  The report claims that per-appliance threshold rules cannot work on an
%  aggregate measurement. Simply running them once at our default tolerance
%  would be a straw man - a reader could fairly object that the thresholds
%  were merely badly tuned.
%
%  So instead we SWEEP the tolerance from +/-25% to +/-1000% and report the
%  BEST result any setting achieves. We also compute the score of a trivial
%  classifier that declares every appliance permanently ON, which is the
%  floor any real method must beat.
%
%  If the best-tuned rule set cannot beat "always say yes", the problem is
%  not the tuning - it is that per-appliance thresholds are the wrong
%  question to ask of an aggregate measurement.
%  ========================================================================

fprintf('COMPARISON 1  Combination matching (all-or-nothing, one common gain)\n\n');

comboParams = params;
comboParams.classifierMethod = 'combination';
comboParams.verbose = false;

[~, comboStatesPred] = classifyLoad(output.featureSet, comboParams);

comboResults = evaluateSystem(sim.windowStates, comboStatesPred, ...
    output.classifyInfo.applianceNames, struct('verbose', false));

fprintf('  accuracy %.2f %%, macro-F1 %.4f\n\n', ...
    100*comboResults.accuracy, comboResults.macroF1);

fprintf('COMPARISON 2  Rule-based classifier, swept across tolerances\n\n');

ruleTolerances = [0.25 0.5 0.75 1.0 1.5 2.0 3.0 5.0 10.0];

quiet = struct('verbose', false);

bestRuleF1 = -1;
bestRuleTol = NaN;
bestRuleResults = [];

fprintf('  %-12s %12s %12s\n', 'Tolerance', 'Accuracy', 'Macro-F1');
fprintf('  %s\n', repmat('-', 1, 38));

for k = 1:numel(ruleTolerances)

    ruleParams = params;
    ruleParams.classifierMethod = 'rules';
    ruleParams.ruleTolerance = ruleTolerances(k);
    ruleParams.verbose = false;

    [~, sweepStates] = classifyLoad(output.featureSet, ruleParams);

    sweepResults = evaluateSystem(sim.windowStates, sweepStates, ...
        output.classifyInfo.applianceNames, quiet);

    fprintf('  +/- %-8.0f%% %11.2f%% %12.4f\n', ...
        100*ruleTolerances(k), 100*sweepResults.accuracy, sweepResults.macroF1);

    if sweepResults.macroF1 > bestRuleF1
        bestRuleF1 = sweepResults.macroF1;
        bestRuleTol = ruleTolerances(k);
        bestRuleResults = sweepResults;
    end

end

ruleResults = bestRuleResults;

%  Trivial baseline: assume every appliance is always on.
alwaysOn = true(size(sim.windowStates));

baselineResults = evaluateSystem(sim.windowStates, alwaysOn, ...
    output.classifyInfo.applianceNames, quiet);

fprintf('\nHEADLINE COMPARISON\n');
fprintf('  NNLS decomposition           : accuracy %6.2f %%, macro-F1 %.4f\n', ...
    100*results.accuracy, results.macroF1);
fprintf('  Combination matching         : accuracy %6.2f %%, macro-F1 %.4f\n', ...
    100*comboResults.accuracy, comboResults.macroF1);
fprintf('  Best-tuned rules (+/-%.0f%%)     : accuracy %6.2f %%, macro-F1 %.4f\n', ...
    100*bestRuleTol, 100*ruleResults.accuracy, ruleResults.macroF1);
fprintf('  Trivial "always ON" baseline : accuracy %6.2f %%, macro-F1 %.4f\n', ...
    100*baselineResults.accuracy, baselineResults.macroF1);

if ruleResults.macroF1 < baselineResults.macroF1
    fprintf('\n  Note: even at its best tolerance the rule set scores BELOW the\n');
    fprintf('  trivial baseline. Per-appliance thresholds are not mistuned here -\n');
    fprintf('  they are answering the wrong question about an aggregate signal.\n\n');
else
    fprintf('\n');
end

%% ========================================================================
%  Figures for the report
%  ========================================================================

if params.plotResults
    fprintf('FIGURES\n');
    generateResultFigures(sim, disturbedSignal, output, results, params);
    fprintf('  Saved to %s\n\n', params.figureDir);
end

%% ========================================================================
%  Save everything, so the report can quote numbers without re-running
%  ========================================================================

resultsFile = fullfile(projectRoot, 'results_own_data.mat');

save(resultsFile, 'params', 'disturbanceInfo', 'results', 'ruleResults', ...
    'comboResults', 'baselineResults', 'bestRuleTol', '-v7.3');

fprintf('SUMMARY\n');
fprintf('  Overall accuracy     : %.2f %%\n', 100*results.accuracy);
fprintf('  Macro F1             : %.4f\n', results.macroF1);
fprintf('  Exact-match windows  : %.2f %%\n', 100*results.exactMatch);
fprintf('  Saved                : %s\n', resultsFile);
fprintf('\n================================================================\n');
fprintf('  Done. For the blind benchmark run:  runBlindTest(''file.mat'')\n');
fprintf('================================================================\n\n');
