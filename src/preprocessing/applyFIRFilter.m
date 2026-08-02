function [filteredSignal, filterInfo] = applyFIRFilter(signal, params)


requiredFields = {'fs', 'f0'};
for i = 1:numel(requiredFields)
    if ~isfield(params, requiredFields{i})
        error('applyFIRFilter:missingParam', 'Missing parameter: %s', requiredFields{i});
    end
end

fs = params.fs;
f0 = params.f0;
nyquist = fs / 2;

if isfield(params, 'maxHarmonic')
    maxHarmonic = params.maxHarmonic;
elseif isfield(params, 'analysisHarmonics')
    maxHarmonic = max(params.analysisHarmonics);
else
    maxHarmonic = 15;
end

if isfield(params, 'cutoffMarginHz')
    cutoffMarginHz = params.cutoffMarginHz;
else
    cutoffMarginHz = f0 / 2;
end

cutoffHz = maxHarmonic * f0 + cutoffMarginHz;
cutoffHz = min(cutoffHz, 0.9 * nyquist);   % stay safely below Nyquist

if isfield(params, 'windowType')
    windowType = params.windowType;
else
    windowType = 'hamming';
end

if isfield(params, 'filterOrder')
    order = params.filterOrder;
    if mod(order, 2) ~= 0
        order = order + 1;   % force even order -> odd, symmetric kernel length
    end
else
    % Rule-of-thumb transition-width based order (window method),
    % scaled to the sampling rate, then rounded to an even number.
    order = 2 * round(0.5 * (3.3 * fs / cutoffMarginHz));
    order = max(order, 100);     % floor for a clean transition band
    order = min(order, 800);     % ceiling to keep runtime/edge effects sane
end

coeffs = designWindowedSincLowpass(cutoffHz, fs, order, windowType);

signal = signal(:);   % enforce column vector
filteredSignal = conv(signal, coeffs, 'same');

filterInfo = struct();
filterInfo.coeffs = coeffs;
filterInfo.cutoffHz = cutoffHz;
filterInfo.order = order;
filterInfo.windowType = windowType;

end

%% ============================================================
% Helper function: windowed-sinc FIR lowpass design
%% ============================================================

function h = designWindowedSincLowpass(cutoffHz, fs, order, windowType)

N = order + 1;              % number of taps (odd -> linear phase, symmetric)
M = (N - 1) / 2;
n = (0:N-1).';

fc = cutoffHz / fs;         % normalized cutoff, cycles/sample (0 to 0.5)

% Ideal lowpass impulse response (sinc), with the sin(0)/0 case handled
% explicitly at the centre tap. Implemented manually (no Signal
% Processing/Communications Toolbox dependency on sinc()).
m = n - M;
x = 2 * fc * m;
hIdeal = 2 * fc * ones(N, 1);
nonzero = x ~= 0;
hIdeal(nonzero) = 2 * fc * sin(pi * x(nonzero)) ./ (pi * x(nonzero));

winCoeffs = generateWindowCoeffs(N, windowType);

h = hIdeal .* winCoeffs;
h = h / sum(h);              % normalize for unity DC gain

end

%% ============================================================
% Helper function: generate window coefficients
% Duplicated (small, self-contained) from applyWindow.m so this file
% remains a single self-contained function per the "one function per
% file" project convention, while still using identical window math.
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
        error('applyFIRFilter:unknownWindowType', 'Unknown window type: %s', windowType);
end

end
