function output = runBlindTest(dataFile, groundTruthFile)
%RUNBLINDTEST Runs the complete pipeline on an unseen aggregate waveform.
%
%   output = RUNBLINDTEST(dataFile)
%   output = RUNBLINDTEST(dataFile, groundTruthFile)
%
%   This is the entry point for the blind benchmark. It loads a waveform
%   that our system has never seen, runs it through EXACTLY the same code
%   path as our own data, and reports what it finds.
%
%   No parameter is retuned, no threshold is adjusted, and no branch behaves
%   differently for blind data. That is the point: the brief requires the
%   pipeline to run on unseen data unmodified, and the anti-gaming clause
%   penalises anything that looks tuned to the released set.
%
%   USAGE
%     runBlindTest('blind_aggregate.mat')
%     runBlindTest('blind_aggregate.csv')
%     runBlindTest('blind_aggregate.mat', 'blind_truth.mat')
%
%   If a ground-truth file is supplied, the result is scored and the
%   accuracy and macro-F1 - the two numbers this project is graded on - are
%   printed. If not, the predicted appliance timeline is reported instead.
%
%   INPUTS
%     dataFile        : path to the blind waveform
%     groundTruthFile : optional path to a .mat holding a numWindows x
%                       numAppliances logical matrix, in any variable named
%                       windowStates, groundTruth, truth or labels
%
%   OUTPUT
%     output : the same struct runPipeline returns, plus loadInfo
%
%   See also RUNPIPELINE, LOADAGGREGATESIGNAL, MAIN.

    if nargin < 1 || isempty(dataFile)
        error('runBlindTest:noFile', ...
            'Give the path to the blind waveform, e.g. runBlindTest(''blind.mat'').');
    end

    % ---------------------------------------------------------------------
    % Path setup, so this works when called from anywhere
    % ---------------------------------------------------------------------
    projectRoot = fileparts(mfilename('fullpath'));

    if isempty(projectRoot)
        projectRoot = pwd;
    end

    addpath(genpath(fullfile(projectRoot, 'src')));
    addpath(projectRoot);

    fprintf('\n');
    fprintf('================================================================\n');
    fprintf('  BLIND BENCHMARK TEST\n');
    fprintf('================================================================\n\n');

    % ---------------------------------------------------------------------
    % Parameters: identical to the ones used on our own data
    % ---------------------------------------------------------------------
    params = defaultParameters();
    params.evaluationLabel = 'Results on the blind benchmark waveform';

    % ---------------------------------------------------------------------
    % Load
    % ---------------------------------------------------------------------
    fprintf('LOADING\n');

    [signal, fs, loadInfo] = loadAggregateSignal(dataFile, params);

    fprintf('  File                 : %s\n', loadInfo.source);
    fprintf('  Variable used        : %s\n', loadInfo.variableUsed);
    fprintf('  Samples              : %d\n', loadInfo.numSamples);
    fprintf('  Sampling rate        : %g Hz (%s)\n', fs, loadInfo.fsSource);
    fprintf('  Duration             : %.3f s\n', loadInfo.duration_s);
    fprintf('  RMS current          : %.3f A\n', loadInfo.rms_A);
    fprintf('  Peak current         : %.3f A\n\n', loadInfo.peak_A);

    % If the blind recording was sampled at a different rate from ours, the
    % pipeline must follow the FILE, not our assumption. Window lengths are
    % specified in seconds, so they adapt automatically.
    if abs(fs - params.fs) > 1e-6
        fprintf('  NOTE the blind file is sampled at %g Hz, not our %g Hz.\n', fs, params.fs);
        fprintf('       Adopting the file''s rate. Window lengths are defined in\n');
        fprintf('       seconds, so they rescale automatically.\n\n');
        params.fs = fs;
    end

    % A sampling rate below twice our highest analysis harmonic makes some
    % harmonics unrecoverable. Say so loudly rather than returning nonsense.
    highestNeeded = max(params.analysisHarmonics) * params.f0;

    if fs <= 2 * highestNeeded
        usable = params.analysisHarmonics(params.analysisHarmonics * params.f0 < fs/2);

        warning('runBlindTest:insufficientSamplingRate', ...
            ['The blind file is sampled at %g Hz, so harmonics above %g Hz ' ...
             'cannot be resolved. Restricting the analysis to orders %s.'], ...
            fs, fs/2, mat2str(usable));

        params.analysisHarmonics = usable;
        params.maxHarmonic = max(usable);
    end

    % ---------------------------------------------------------------------
    % Ground truth, if we were given any
    % ---------------------------------------------------------------------
    groundTruth = [];

    if nargin >= 2 && ~isempty(groundTruthFile)
        groundTruth = loadGroundTruth(groundTruthFile);
        fprintf('  Ground truth loaded  : %d windows x %d appliances\n\n', ...
            size(groundTruth, 1), size(groundTruth, 2));
    end

    % ---------------------------------------------------------------------
    % Run - the same function main.m calls
    % ---------------------------------------------------------------------
    fprintf('PIPELINE\n');

    output = runPipeline(signal, params, groundTruth);

    output.loadInfo = loadInfo;

    % ---------------------------------------------------------------------
    % Report
    % ---------------------------------------------------------------------
    if isfield(output, 'results')

        fprintf('KEY PERFORMANCE METRIC ON BLIND DATA\n');
        fprintf('  Overall accuracy     : %.2f %%\n', 100*output.results.accuracy);
        fprintf('  Macro F1             : %.4f\n\n', output.results.macroF1);

    else
        printPredictedTimeline(output);
    end

    % ---------------------------------------------------------------------
    % Figures
    % ---------------------------------------------------------------------
    [~, stem] = fileparts(loadInfo.source);

    if isfield(params, 'plotResults') && params.plotResults
        generateBlindFigures(output, params, stem);
    end

    % ---------------------------------------------------------------------
    % Save
    % ---------------------------------------------------------------------
    outFile = fullfile(projectRoot, sprintf('results_blind_%s.mat', stem));

    blindOutput = rmfield(output, 'frames');   % frames are large and derivable
    save(outFile, 'blindOutput', 'params', '-v7.3');

    fprintf('  Saved                : %s\n', outFile);
    fprintf('\n================================================================\n\n');

end

% =========================================================================
% Print the predicted on/off timeline when no ground truth is available
% =========================================================================
function printPredictedTimeline(output)

    names = output.classifyInfo.applianceNames;
    predStates = output.predStates;
    centreTimes = output.featureInfo.centerTime_s;

    fprintf('PREDICTED APPLIANCE TIMELINE\n');
    fprintf('  (no ground truth supplied, so these cannot be scored)\n\n');

    for a = 1:numel(names)

        states = predStates(:, a);

        fprintf('  %-16s on for %5.1f %% of the recording\n', ...
            names{a}, 100*mean(states));

        % Report contiguous ON intervals rather than 119 individual windows.
        edges = diff([false; states(:); false]);
        starts = find(edges == 1);
        stops = find(edges == -1) - 1;

        for k = 1:numel(starts)
            t1 = centreTimes(starts(k));
            t2 = centreTimes(stops(k));
            fprintf('      %6.2f s  to %6.2f s\n', t1, t2);
        end

    end

    fprintf('\n');

end

% =========================================================================
% Load a ground-truth label matrix from a .mat file
% =========================================================================
function groundTruth = loadGroundTruth(groundTruthFile)

    if exist(groundTruthFile, 'file') ~= 2
        error('runBlindTest:truthNotFound', ...
            'Cannot find the ground-truth file "%s".', groundTruthFile);
    end

    contents = load(groundTruthFile);

    candidates = {'windowStates', 'groundTruth', 'truth', 'labels', 'states'};

    groundTruth = [];

    for k = 1:numel(candidates)
        if isfield(contents, candidates{k})
            groundTruth = logical(contents.(candidates{k}));
            return;
        end
    end

    names = fieldnames(contents);

    for k = 1:numel(names)
        value = contents.(names{k});
        if (islogical(value) || isnumeric(value)) && ismatrix(value) && size(value, 2) > 1
            groundTruth = logical(value);
            return;
        end
    end

    error('runBlindTest:noTruthVariable', ...
        ['No label matrix was found in "%s". Expected a variable named one of: %s.'], ...
        groundTruthFile, strjoin(candidates, ', '));

end
