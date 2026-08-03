function [featureSet, featureInfo] = extractFeatureSet(signal, frames, frameInfo, params)
%EXTRACTFEATURESET Feature vector for every analysis window in a recording.
%
%   [featureSet, featureInfo] = EXTRACTFEATURESET(signal, frames, frameInfo, params)
%
%   This is the bridge that was missing from the original pipeline. The old
%   main.m ran one FFT over the entire 12-second recording and produced a
%   single feature vector, which cannot describe a recording in which
%   appliances switch on and off. This function walks the windows produced by
%   applyWindow.m and produces one feature struct per window.
%
%   INPUTS
%     signal    : the full filtered signal, column vector, amperes.
%                 Used to recover each window's UNWINDOWED samples so that
%                 RMS is a true RMS rather than the RMS of a tapered segment.
%     frames    : winLength x numWindows matrix of windowed frames, from applyWindow
%     frameInfo : struct from applyWindow, carrying sample indices and the
%                 window coefficients
%     params    : project parameter struct
%
%   OUTPUTS
%     featureSet  : numWindows x 1 struct array, one entry per window
%     featureInfo : struct of diagnostics for the report, including the
%                   spectral resolution actually achieved
%
%   A NOTE ON THE WINDOW LENGTH, WHICH IS WORTH DEFENDING IN THE VIVA
%
%   The default window is 0.20 s at a 50 Hz fundamental, which is exactly ten
%   fundamental cycles. That is deliberate. When a window spans a whole number
%   of cycles the harmonics fall precisely on FFT bin centres, so there is no
%   spectral leakage between them and each harmonic amplitude can be read
%   directly from its bin. At 4000 Hz the window holds 800 samples, giving a
%   bin spacing of 4000/800 = 5 Hz, and every harmonic of 50 Hz lands exactly
%   on a bin.
%
%   The 0.10 s hop is five fundamental cycles, so consecutive windows are also
%   a whole number of cycles apart. That keeps the de-rotated phases in
%   extractHarmonicPhasors consistent from one window to the next.

    signal = signal(:);

    if isempty(frames)
        error('extractFeatureSet:noFrames', ...
            'No analysis windows were produced. Is the signal shorter than one window?');
    end

    numWindows = size(frames, 2);

    startSamples = frameInfo.startSamples;
    stopSamples = frameInfo.stopSamples;
    centerTime = frameInfo.centerTime;
    winCoeffs = frameInfo.winCoeffs;

    fs = frameInfo.fs;

    % ---------------------------------------------------------------------
    % Analyse the first window to learn the shape of the harmonic set, then
    % preallocate the struct array with the correct fields. Preallocating
    % with repmat(struct(), ...) - which the original classifier did - makes
    % a zero-field struct that MATLAB then refuses to assign into.
    % ---------------------------------------------------------------------
    firstFeatures = analyseOneWindow(1);

    featureSet = repmat(firstFeatures, numWindows, 1);

    for w = 2:numWindows
        featureSet(w) = analyseOneWindow(w);
    end

    % ---------------------------------------------------------------------
    % Diagnostics
    % ---------------------------------------------------------------------
    winLength = size(frames, 1);
    f0 = getParam(params, 'f0', 50);

    featureInfo = struct();
    featureInfo.numWindows = numWindows;
    featureInfo.windowLength_samples = winLength;
    featureInfo.windowLength_s = winLength / fs;
    featureInfo.windowLength_cycles = (winLength / fs) * f0;
    featureInfo.hopLength_s = frameInfo.hopLength / fs;
    featureInfo.hopLength_cycles = (frameInfo.hopLength / fs) * f0;
    featureInfo.binResolution_Hz = fs / winLength;
    featureInfo.coherentSampling = abs(featureInfo.windowLength_cycles - ...
        round(featureInfo.windowLength_cycles)) < 1e-9;
    featureInfo.windowType = frameInfo.windowType;
    featureInfo.centerTime_s = centerTime;
    featureInfo.analysisHarmonics = firstFeatures.orders;
    featureInfo.liveWindows = sum([featureSet.isLive]);
    featureInfo.deadWindows = numWindows - featureInfo.liveWindows;

    % =====================================================================
    % Nested function: analyse a single window
    % Nested (not a subfunction) so it can see frames, signal and params
    % without passing them repeatedly.
    % =====================================================================
    function features = analyseOneWindow(w)

        windowedSegment = frames(:, w);

        % The unwindowed samples, for a true RMS.
        rawSegment = signal(startSamples(w):stopSamples(w));

        % Time at which this window starts, used to de-rotate the phases.
        startTime = (startSamples(w) - 1) / fs;

        [frequency, magnitude, phase] = computeFFT(windowedSegment, fs, winCoeffs);

        harm = extractHarmonicPhasors(frequency, magnitude, phase, params, startTime);

        features = extractFeatures(harm, rawSegment, params);

        features.windowIndex = w;
        features.centerTime_s = centerTime(w);
        features.startTime_s = startTime;

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
