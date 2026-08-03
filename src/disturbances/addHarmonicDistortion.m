function [distortedSignal, distortionInfo] = addHarmonicDistortion(signal, params)
%ADDHARMONICDISTORTION Adds supply-side background harmonic distortion.
%
%   [distortedSignal, distortionInfo] = ADDHARMONICDISTORTION(signal, params)
%
%   This models distortion that does NOT come from our own appliances. On a
%   weak low-voltage feeder the supply voltage is already distorted by other
%   customers' nonlinear loads, so a background harmonic current is present
%   at the measurement point regardless of what our appliances are doing.
%
%   This is the disturbance that most directly attacks our method, because
%   our classifier identifies appliances from harmonic magnitudes. Injecting
%   background harmonics at the SAME orders our appliances use (5th, 7th,
%   11th) is deliberate: it is the hardest case, not the easiest, and it is
%   what justifies the filtering and window design in the report.
%
%   Level selection: IEEE Std 519 recommends a voltage total harmonic
%   distortion limit of 5% for systems below 69 kV, with 3% for any single
%   harmonic. A feeder described as "unstable" is one where those limits are
%   not being met, so the default here (8% total) sits deliberately above
%   the IEEE 519 limit to represent a non-compliant feeder.
%
%   INPUTS
%     signal : column vector, aggregate current in amperes
%     params : struct. Fields used (all optional except fs):
%                fs                  sampling frequency, Hz        [required]
%                f0                  fundamental frequency, Hz     [default 50]
%                supplyTHD           total background THD, e.g 0.08 [default 0.08]
%                distortionOrders    harmonic orders to inject     [default [5 7 11]]
%                distortionWeights   relative weight of each order [default [1 0.6 0.35]]
%                distortionPhases    phase of each order, degrees  [default [25 -60 140]]
%                applyDistortion     set false to disable          [default true]
%
%   OUTPUTS
%     distortedSignal : column vector, current with background harmonics
%     distortionInfo  : struct describing what was injected
%
%   The injected amplitudes are scaled relative to the measured fundamental
%   amplitude of the incoming signal, so the distortion stays proportionate
%   whether the feeder is lightly or heavily loaded.

    % ---------------------------------------------------------------------
    % Validate input
    % ---------------------------------------------------------------------
    if ~isfield(params, 'fs')
        error('addHarmonicDistortion:missingParam', 'Missing parameter: fs');
    end

    signal = signal(:);
    N = numel(signal);
    fs = params.fs;

    if N < 2
        distortedSignal = signal;
        distortionInfo = struct('applied', false, 'reason', 'signal too short');
        return;
    end

    % ---------------------------------------------------------------------
    % Resolve parameters
    % ---------------------------------------------------------------------
    f0      = getParam(params, 'f0',                50);
    THD     = getParam(params, 'supplyTHD',         0.08);
    orders  = getParam(params, 'distortionOrders',  [5 7 11]);
    weights = getParam(params, 'distortionWeights', [1 0.6 0.35]);
    phases  = getParam(params, 'distortionPhases',  [25 -60 140]);
    enabled = getParam(params, 'applyDistortion',   true);

    if ~enabled
        distortedSignal = signal;
        distortionInfo = struct('applied', false, 'reason', 'disabled by params.applyDistortion');
        return;
    end

    orders  = orders(:).';
    weights = weights(:).';
    phases  = phases(:).';

    if numel(weights) ~= numel(orders)
        error('addHarmonicDistortion:sizeMismatch', ...
            'distortionWeights must have the same number of elements as distortionOrders.');
    end
    if numel(phases) ~= numel(orders)
        error('addHarmonicDistortion:sizeMismatch', ...
            'distortionPhases must have the same number of elements as distortionOrders.');
    end

    % Guard against aliasing: never inject a harmonic above Nyquist.
    nyquist = fs / 2;
    valid = (orders * f0) < nyquist;

    if ~all(valid)
        warning('addHarmonicDistortion:aboveNyquist', ...
            'Dropped %d harmonic order(s) at or above Nyquist (%.0f Hz).', sum(~valid), nyquist);
    end

    orders  = orders(valid);
    weights = weights(valid);
    phases  = phases(valid);

    if isempty(orders)
        distortedSignal = signal;
        distortionInfo = struct('applied', false, 'reason', 'no valid harmonic orders below Nyquist');
        return;
    end

    % ---------------------------------------------------------------------
    % Measure the fundamental amplitude of the incoming signal
    %
    % Rather than assume a value we project the signal onto sine and cosine
    % at f0. For a signal x(t) = A*sin(2*pi*f0*t + phi) the projections give
    % the in-phase and quadrature components directly, and the amplitude is
    % the magnitude of that pair. This is a single-bin DFT and needs no
    % toolbox.
    % ---------------------------------------------------------------------
    t = (0:N-1).' / fs;

    refSin = sin(2*pi*f0*t);
    refCos = cos(2*pi*f0*t);

    aSin = 2 * mean(signal .* refSin);
    aCos = 2 * mean(signal .* refCos);

    fundamentalAmp = sqrt(aSin^2 + aCos^2);

    % If the input is essentially silent there is no fundamental to scale
    % against. Fall back to the signal's own RMS so the function still does
    % something sensible instead of injecting nothing.
    if fundamentalAmp < eps
        fundamentalAmp = sqrt(2) * sqrt(mean(signal.^2));
    end

    % ---------------------------------------------------------------------
    % Scale the weights so the injected set has the requested total THD
    %
    % THD is defined as sqrt(sum of squared harmonic amplitudes) divided by
    % the fundamental amplitude. We therefore normalise the weight vector to
    % unit 2-norm and then multiply by THD * fundamentalAmp.
    % ---------------------------------------------------------------------
    weightNorm = sqrt(sum(weights.^2));

    if weightNorm < eps
        distortedSignal = signal;
        distortionInfo = struct('applied', false, 'reason', 'all distortion weights are zero');
        return;
    end

    amplitudes = (weights / weightNorm) * THD * fundamentalAmp;

    % ---------------------------------------------------------------------
    % Build and add the background distortion
    % ---------------------------------------------------------------------
    distortion = zeros(N, 1);

    for k = 1:numel(orders)
        distortion = distortion + ...
            amplitudes(k) * sin(2*pi*orders(k)*f0*t + phases(k)*pi/180);
    end

    distortedSignal = signal + distortion;

    % ---------------------------------------------------------------------
    % Report metadata
    % ---------------------------------------------------------------------
    distortionInfo = struct();
    distortionInfo.applied = true;
    distortionInfo.targetTHD_fraction = THD;
    distortionInfo.targetTHD_percent = THD * 100;
    distortionInfo.orders = orders;
    distortionInfo.amplitudes_A = amplitudes;
    distortionInfo.phases_deg = phases;
    distortionInfo.measuredFundamental_A = fundamentalAmp;
    distortionInfo.exceedsIEEE519 = (THD > 0.05);
    distortionInfo.reference = 'IEEE Std 519, Recommended Practice and Requirements for Harmonic Control in Electric Power Systems';

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
