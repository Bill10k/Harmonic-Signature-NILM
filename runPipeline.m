function output = runPipeline(signal, params, groundTruth)
%RUNPIPELINE The complete DSP chain, from a current waveform to appliance states.
%
%   output = RUNPIPELINE(signal, params)
%   output = RUNPIPELINE(signal, params, groundTruth)
%
%   Everything after signal generation lives here, so that EXACTLY the same
%   code path runs on our own simulated recording and on the blind benchmark
%   waveform. That is not a tidiness preference - the brief requires our
%   pipeline to run on unseen data "unmodified", and the only way to be sure
%   of that is to have one function that both callers use.
%
%   STAGES
%     1. FIR low-pass filtering   remove everything above the 15th harmonic
%     2. Windowing                cut into overlapping analysis frames
%     3. FFT per window           amplitude and phase spectrum of each frame
%     4. Feature extraction       harmonic phasors, RMS, THD, phase
%     5. Classification           which combination of appliances fits best
%     6. Evaluation               only if ground truth is supplied
%
%   INPUTS
%     signal      : column vector, measured aggregate current, amperes
%     params      : project parameter struct (see defaultParameters.m)
%     groundTruth : optional numWindows x numAppliances logical matrix.
%                   Supply it to get a scored result; omit it when the true
%                   states are unknown, as they will be for blind data.
%
%   OUTPUT
%     output : struct containing every intermediate result, so the report
%              figures can be drawn without re-running anything:
%                filteredSignal, filterInfo
%                frames, frameInfo
%                featureSet, featureInfo
%                predictions, predStates, classifyInfo
%                results        (present only if groundTruth was supplied)
%
%   See also MAIN, RUNBLINDTEST, DEFAULTPARAMETERS.

    if nargin < 2 || isempty(params)
        params = defaultParameters();
    end

    if nargin < 3
        groundTruth = [];
    end

    signal = signal(:);

    verbose = getParam(params, 'verbose', true);

    output = struct();
    output.inputSignal = signal;
    output.params = params;

    % =====================================================================
    % 1. FIR low-pass filtering
    %
    % Everything we need lives at or below the 15th harmonic, 750 Hz. Above
    % that there is only measurement noise and any aliased content, so
    % removing it improves the signal-to-noise ratio of every harmonic
    % estimate without discarding information we use.
    % =====================================================================
    if verbose
        fprintf('  [1/5] FIR filtering ...\n');
    end

    [filteredSignal, filterInfo] = applyFIRFilter(signal, params);

    output.filteredSignal = filteredSignal;
    output.filterInfo = filterInfo;

    if verbose
        fprintf('        cutoff %.0f Hz, order %d, %s window\n', ...
            filterInfo.cutoffHz, filterInfo.order, filterInfo.windowType);
    end

    % =====================================================================
    % 2. Windowing
    % =====================================================================
    if verbose
        fprintf('  [2/5] Windowing ...\n');
    end

    [frames, frameInfo] = applyWindow(filteredSignal, params);

    output.frames = frames;
    output.frameInfo = frameInfo;

    if verbose
        fprintf('        %d windows of %.3f s, hop %.3f s, %s window\n', ...
            size(frames, 2), frameInfo.winLength/frameInfo.fs, ...
            frameInfo.hopLength/frameInfo.fs, frameInfo.windowType);
    end

    % =====================================================================
    % 3 and 4. FFT and feature extraction, one window at a time
    % =====================================================================
    if verbose
        fprintf('  [3/5] FFT and harmonic extraction ...\n');
        fprintf('  [4/5] Feature extraction ...\n');
    end

    [featureSet, featureInfo] = extractFeatureSet(filteredSignal, frames, frameInfo, params);

    output.featureSet = featureSet;
    output.featureInfo = featureInfo;

    if verbose
        fprintf('        %.1f Hz bin resolution, %d harmonics per window\n', ...
            featureInfo.binResolution_Hz, numel(featureInfo.analysisHarmonics));

        if featureInfo.coherentSampling
            fprintf('        window spans %.1f fundamental cycles: coherent, no leakage\n', ...
                featureInfo.windowLength_cycles);
        else
            fprintf('        WARNING window spans %.2f cycles: NOT coherent, expect leakage\n', ...
                featureInfo.windowLength_cycles);
        end

        if featureInfo.deadWindows > 0
            fprintf('        %d window(s) show no live supply\n', featureInfo.deadWindows);
        end
    end

    % =====================================================================
    % 5. Classification
    % =====================================================================
    if verbose
        fprintf('  [5/5] Classification ...\n');
    end

    [predictions, predStates, classifyInfo] = classifyLoad(featureSet, params);

    output.predictions = predictions;
    output.predStates = predStates;
    output.classifyInfo = classifyInfo;

    if verbose
        fprintf('        method "%s", %d combinations tested per window\n', ...
            classifyInfo.method, classifyInfo.numCombinations);

        if classifyInfo.heldWindows > 0
            fprintf('        %d window(s) held through a short outage\n', classifyInfo.heldWindows);
        end

        if isfield(classifyInfo, 'backgroundEstimated') && classifyInfo.backgroundEstimated
            bg = classifyInfo.backgroundMagnitude_A;
            orders = classifyInfo.analysisHarmonics;
            [~, worst] = max(bg);
            fprintf('        feeder background estimated and removed: %.3f A at the %dth harmonic\n', ...
                bg(worst), orders(worst));
        end

        if isfield(classifyInfo, 'releasedWindows') && classifyInfo.releasedWindows > 0
            fprintf('        %d window(s) silent for longer than %d windows: reported as idle\n', ...
                classifyInfo.releasedWindows, classifyInfo.maxHoldWindows);
        end
    end

    % =====================================================================
    % 6. Evaluation, only when the truth is known
    % =====================================================================
    if ~isempty(groundTruth)

        evalOptions = struct('verbose', verbose, ...
                             'label', getParam(params, 'evaluationLabel', 'Evaluation'));

        output.results = evaluateSystem(groundTruth, predStates, ...
            classifyInfo.applianceNames, evalOptions);

    elseif verbose
        fprintf('\n  No ground truth supplied, so no score was computed.\n');
        fprintf('  Predicted ON fraction per appliance:\n');

        for a = 1:numel(classifyInfo.applianceNames)
            fprintf('    %-16s %5.1f %% of windows\n', ...
                classifyInfo.applianceNames{a}, 100 * classifyInfo.onFraction(a));
        end
    end

end

% =========================================================================
% Helper: read an optional parameter with a default
% =========================================================================
function value = getParam(params, name, defaultValue)

    if isfield(params, name) && ~isempty(params.(name))
        value = params.(name);
    else
        value = defaultValue;
    end

end
