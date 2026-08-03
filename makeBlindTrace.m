function [traceFile, truthFile, info] = makeBlindTrace(seed, outDir)
%MAKEBLINDTRACE Builds a held-out recording our classifier has never seen.
%
%   [traceFile, truthFile, info] = MAKEBLINDTRACE()
%   [traceFile, truthFile, info] = MAKEBLINDTRACE(seed)
%   [traceFile, truthFile, info] = MAKEBLINDTRACE(seed, outDir)
%
%   The official blind waveform is described as having "a different appliance
%   combination and an undisclosed disturbance severity". This function
%   manufactures exactly that, so we can measure how our system behaves on
%   data it was not built around - without waiting for the release, and
%   without ever tuning against the result.
%
%   FOUR THINGS ARE MADE DIFFERENT FROM OUR OWN RECORDING
%
%   1. A DIFFERENT SET OF APPLIANCES. Each appliance has a 4-in-5 chance of
%      appearing at all, so most traces contain three of the four, and which
%      three varies.
%
%   2. DIFFERENT SWITCHING SCHEDULES. On and off times are drawn at random
%      rather than reused, so no appliance follows a pattern we have seen.
%
%   3. DIFFERENT SPECIMENS OF THE SAME APPLIANCE TYPES. This is the part
%      that matters most and it is easy to overlook. Two kettles of the same
%      nominal rating are not identical: manufacturing tolerance, supply
%      voltage and age all shift the current they draw. So each appliance is
%      perturbed - up to 15% in RMS current, 20% in every harmonic ratio and
%      10 degrees in every harmonic phase. Our appliance library is NOT
%      updated to match. If the classifier only works when the templates are
%      exactly right, this is where it will show.
%
%   4. HARSHER DISTURBANCES. A 45% sag rather than 30%, 12% background THD
%      rather than 8%, TWO interruptions rather than one, and 25 dB SNR
%      rather than 35 dB.
%
%   The waveform and the labels are written to SEPARATE files, so the trace
%   can be analysed without the answers being anywhere near the pipeline.
%
%   USAGE
%     [traceFile, truthFile] = makeBlindTrace(7);
%     runBlindTest(traceFile);                 % blind: no labels at all
%     runBlindTest(traceFile, truthFile);      % scored
%
%   INPUTS
%     seed   : integer controlling the randomisation  [default 7]
%     outDir : where to write the files                [default blind_data]
%
%   OUTPUTS
%     traceFile : path to the waveform file
%     truthFile : path to the label file
%     info      : struct recording exactly what was generated
%
%   See also RUNBLINDTEST, MODEL_FOUR_APPLIANCES.

    if nargin < 1 || isempty(seed)
        seed = 7;
    end

    projectRoot = fileparts(mfilename('fullpath'));

    if isempty(projectRoot)
        projectRoot = pwd;
    end

    if nargin < 2 || isempty(outDir)
        outDir = fullfile(projectRoot, 'blind_data');
    end

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    addpath(genpath(fullfile(projectRoot, 'src')));
    addpath(projectRoot);

    params = defaultParameters();

    fs = params.fs;
    f0 = params.f0;

    % A different length from our own 12 s recording, so nothing downstream
    % can rely on the window count.
    duration = 15;

    previousState = rng;
    rng(seed, 'twister');

    t = (0:1/fs:duration-1/fs).';
    N = numel(t);

    % =====================================================================
    % Appliance definitions, then perturbed
    % =====================================================================
    lib = applianceLibrary(params);
    numAppliances = numel(lib);

    currents = zeros(N, numAppliances);
    sampleStates = false(N, numAppliances);

    present = rand(1, numAppliances) < 0.8;

    if sum(present) < 2
        present(1:2) = true;      % always leave something to find
    end

    perturbation = repmat(struct('name', '', 'present', false, ...
        'rmsScale', 1, 'onIntervals', [], 'harmonics', []), numAppliances, 1);

    startupTypes = {'soft_ramp', 'motor_inrush', 'soft_ramp', 'charger_inrush'};

    startupParams = { ...
        struct('tau', 0.06), ...
        struct('factor', 3.2, 'tau', 0.35, 'transientRatio', 0.25, ...
               'transientOrder', 6, 'transientTau', 0.20), ...
        struct('tau', 0.03), ...
        struct('factor', 1.8, 'tauRise', 0.04, 'tauDecay', 0.20)};

    for a = 1:numAppliances

        perturbation(a).name = lib(a).name;
        perturbation(a).present = present(a);

        if ~present(a)
            continue;
        end

        % --- perturb the device ---------------------------------------
        rmsScale = 1 + (rand*2 - 1) * 0.15;
        rmsValue = lib(a).fundamentalRMS_A * rmsScale;

        H = lib(a).harmonics;

        for r = 1:size(H, 1)
            H(r, 2) = H(r, 2) * (1 + (rand*2 - 1) * 0.20);
            H(r, 3) = H(r, 3) + (rand*2 - 1) * 10;
        end

        % --- random switching schedule --------------------------------
        numSegments = randi([1 3]);
        edges = sort(rand(1, 2*numSegments) * duration);

        intervals = [];

        for s = 1:numSegments
            tOn = edges(2*s - 1);
            tOff = edges(2*s);

            if (tOff - tOn) >= 0.6           % ignore implausibly brief runs
                intervals = [intervals; tOn tOff]; %#ok<AGROW>
            end
        end

        if isempty(intervals)
            intervals = [rand*(duration-2), 0];
            intervals(2) = intervals(1) + 1.5;
        end

        perturbation(a).rmsScale = rmsScale;
        perturbation(a).onIntervals = intervals;
        perturbation(a).harmonics = H;

        % --- synthesise -----------------------------------------------
        [currents(:, a), sampleStates(:, a)] = synthesise( ...
            t, f0, rmsValue, H, intervals, startupTypes{a}, startupParams{a});

    end

    aggregate = sum(currents, 2);

    % =====================================================================
    % Harsher disturbances
    % =====================================================================
    blindParams = params;

    blindParams.sagDepth = 0.45;
    blindParams.sagStartTime = 2 + rand * (duration - 5);
    blindParams.sagDuration = 0.40;

    blindParams.supplyTHD = 0.12;

    blindParams.interruptionStartTime = 1 + rand * (duration - 3);
    blindParams.interruptionDuration = 0.12;

    blindParams.noiseSNR_dB = 25;
    blindParams.randomSeed = seed * 977;

    [disturbed, disturbanceInfo] = applyDisturbances(aggregate, blindParams);

    % A second interruption, which our own recording never contains.
    secondParams = blindParams;
    secondParams.interruptionStartTime = 1 + rand * (duration - 3);
    secondParams.applyNoise = false;

    [disturbed, secondInterruption] = applyInterruption(disturbed, secondParams);

    % =====================================================================
    % Ground truth per analysis window
    %
    % Uses the same window arithmetic as applyWindow so the label matrix
    % lines up row for row with the predictions.
    % =====================================================================
    winLength = round(params.windowLength * fs);
    hopLength = round(params.hopLength * fs);

    numWindows = floor((N - winLength) / hopLength) + 1;

    windowStates = false(numWindows, numAppliances);

    for w = 1:numWindows
        s1 = (w-1)*hopLength + 1;
        s2 = s1 + winLength - 1;
        windowStates(w, :) = mean(sampleStates(s1:s2, :), 1) >= 0.5;
    end

    % =====================================================================
    % Write the two files
    % =====================================================================
    aggregateCurrent = disturbed;   %#ok<NASGU>  saved below

    traceFile = fullfile(outDir, sprintf('blind_trace_seed%d.mat', seed));
    truthFile = fullfile(outDir, sprintf('blind_truth_seed%d.mat', seed));

    save(traceFile, 'aggregateCurrent', 'fs');

    applianceNames = {lib.name}; %#ok<NASGU>
    save(truthFile, 'windowStates', 'applianceNames');

    rng(previousState);

    % =====================================================================
    % Report
    % =====================================================================
    info = struct();
    info.seed = seed;
    info.duration_s = duration;
    info.fs = fs;
    info.numWindows = numWindows;
    info.appliancesPresent = {lib(present).name};
    info.perturbation = perturbation;
    info.disturbances = disturbanceInfo;
    info.secondInterruption = secondInterruption;
    info.traceFile = traceFile;
    info.truthFile = truthFile;

    fprintf('\nHELD-OUT TRACE GENERATED  (seed %d)\n', seed);
    fprintf('  Duration             : %g s, %d analysis windows\n', duration, numWindows);
    fprintf('  Appliances present   : %s\n', strjoin(info.appliancesPresent, ', '));

    for a = 1:numAppliances
        if present(a)
            fprintf('    %-16s current x%.2f of nominal, %d ON interval(s)\n', ...
                lib(a).name, perturbation(a).rmsScale, size(perturbation(a).onIntervals, 1));
        end
    end

    fprintf('  Sag                  : %.0f%% for %g s\n', ...
        100*blindParams.sagDepth, blindParams.sagDuration);
    fprintf('  Background THD       : %.0f%%\n', 100*blindParams.supplyTHD);
    fprintf('  Interruptions        : 2\n');
    fprintf('  SNR                  : %g dB\n', blindParams.noiseSNR_dB);
    fprintf('  Waveform             : %s\n', traceFile);
    fprintf('  Labels               : %s\n\n', truthFile);
    fprintf('  Score it with:  runBlindTest(''%s'', ''%s'')\n\n', traceFile, truthFile);

end

% =========================================================================
% Synthesise one perturbed appliance current
% Mirrors the maths in model_four_appliances.m
% =========================================================================
function [current, state] = synthesise(t, f0, rmsValue, H, intervals, startupType, sp)

    N = numel(t);

    state = false(N, 1);
    envelope = zeros(N, 1);
    startupTransient = zeros(N, 1);

    for e = 1:size(intervals, 1)

        tOn = intervals(e, 1);
        tOff = intervals(e, 2);

        idx = (t >= tOn) & (t < tOff);
        tau = t(idx) - tOn;

        state(idx) = true;

        switch lower(startupType)

            case 'soft_ramp'
                env = 1 - exp(-tau / sp.tau);

            case 'motor_inrush'
                env = 1 + (sp.factor - 1) * exp(-tau / sp.tau);

                transientPeak = sqrt(2) * rmsValue * sp.transientRatio;
                startupTransient(idx) = transientPeak .* exp(-tau / sp.transientTau) .* ...
                    sin(2*pi*sp.transientOrder*f0*t(idx) + pi/2);

            case 'charger_inrush'
                rise = 1 - exp(-tau / sp.tauRise);
                decayBoost = 1 + (sp.factor - 1) * exp(-tau / sp.tauDecay);
                env = rise .* decayBoost;

            otherwise
                env = ones(size(tau));
        end

        envelope(idx) = env;

    end

    base = zeros(N, 1);

    for r = 1:size(H, 1)
        peakAmp = sqrt(2) * rmsValue * H(r, 2);
        base = base + peakAmp * sin(2*pi*H(r,1)*f0*t + H(r,3)*pi/180);
    end

    current = envelope .* base + startupTransient;

end
