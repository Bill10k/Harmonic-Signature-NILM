function [windowedFrames, frameInfo] = applyWindow(signal, params)

requiredFields = {'fs', 'windowLength', 'hopLength'};
for i = 1:numel(requiredFields)
    if ~isfield(params, requiredFields{i})
        error('applyWindow:missingParam', 'Missing parameter: %s', requiredFields{i});
    end
end

if isfield(params, 'windowType')
    windowType = params.windowType;
else
    windowType = 'hamming';
end

signal = signal(:);   % enforce column vector
N = length(signal);

fs = params.fs;
winLength = round(params.windowLength * fs);
hopLength = round(params.hopLength * fs);

if winLength < 2
    error('applyWindow:badWindowLength', 'windowLength is too short for the given fs.');
end

if hopLength < 1
    error('applyWindow:badHopLength', 'hopLength must be at least one sample.');
end

numWindows = floor((N - winLength) / hopLength) + 1;

if numWindows < 1
    error('applyWindow:signalTooShort', ...
        'Signal is shorter than a single analysis window (%d samples).', winLength);
end

winCoeffs = generateWindowCoeffs(winLength, windowType);

windowedFrames = zeros(winLength, numWindows);
startSamples = zeros(numWindows, 1);
stopSamples = zeros(numWindows, 1);
centerTime = zeros(numWindows, 1);

for w = 1:numWindows
    s1 = (w - 1) * hopLength + 1;
    s2 = s1 + winLength - 1;

    startSamples(w) = s1;
    stopSamples(w) = s2;
    centerTime(w) = ((s1 + s2) / 2 - 1) / fs;

    windowedFrames(:, w) = signal(s1:s2) .* winCoeffs;
end

frameInfo = struct();
frameInfo.startSamples = startSamples;
frameInfo.stopSamples = stopSamples;
frameInfo.centerTime = centerTime;
frameInfo.windowType = windowType;
frameInfo.winCoeffs = winCoeffs;
frameInfo.fs = fs;
frameInfo.winLength = winLength;
frameInfo.hopLength = hopLength;

end

%% ============================================================
% Helper function: generate window coefficients
% Implemented manually (no Signal Processing Toolbox dependency),
% consistent with the manual Hann window used in
% model_four_appliances.m/singleSidedSpectrum.
%% ============================================================

function w = generateWindowCoeffs(N, windowType)

n = (0:N-1).';

switch lower(windowType)

    case 'rectangular'
        w = ones(N, 1);

    case 'hann'
        w = 0.5 - 0.5 * cos(2 * pi * n / (N - 1));

    case 'hamming'
        w = 0.54 - 0.46 * cos(2 * pi * n / (N - 1));

    case 'blackman'
        w = 0.42 - 0.5 * cos(2 * pi * n / (N - 1)) + 0.08 * cos(4 * pi * n / (N - 1));

    otherwise
        error('applyWindow:unknownWindowType', 'Unknown window type: %s', windowType);
end

end
