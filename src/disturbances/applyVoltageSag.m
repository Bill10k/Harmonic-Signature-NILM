function [sagSignal, sagInfo] = applyVoltageSag(signal, params)
%APPLYVOLTAGESAG Applies a voltage sag (dip) to an aggregate current signal.
%
%   [sagSignal, sagInfo] = APPLYVOLTAGESAG(signal, params)
%
%   A voltage sag is a short-duration reduction in supply RMS voltage.
%   IEEE Std 1159 defines a sag as a reduction to between 0.1 pu and 0.9 pu
%   of nominal voltage lasting from half a cycle to one minute, and further
%   classifies it as:
%
%       instantaneous : 0.5 - 30 cycles
%       momentary     : 30 cycles - 3 seconds
%       temporary     : 3 seconds - 1 minute
%
%   For a load supplied at reduced voltage the drawn current also falls.
%   For a linear (resistive) load the current is directly proportional to
%   the applied voltage, so scaling the current waveform by the residual
%   voltage in per-unit is the standard first-order model and is what is
%   implemented here. This deliberately does NOT model constant-power loads
%   (which draw MORE current during a sag); that limitation is stated in
%   the report as a known simplification.
%
%   The sag edges are given a finite transition time rather than being a
%   perfect step. A perfect step would create a broadband transient that is
%   an artefact of the model rather than a property of a real feeder, and it
%   would contaminate the FFT of every window near the edge.
%
%   INPUTS
%     signal : column vector, aggregate current in amperes
%     params : struct. Fields used (all optional except fs):
%                fs               sampling frequency, Hz              [required]
%                f0               fundamental frequency, Hz           [default 50]
%                sagDepth         fractional voltage drop, 0 to 0.9   [default 0.30]
%                sagStartTime     sag start, seconds                  [default 4.0]
%                sagDuration      sag length, seconds                 [default 0.30]
%                sagTransition    edge transition time, seconds       [default 1 cycle]
%                applySag         set false to disable this stage     [default true]
%
%   OUTPUTS
%     sagSignal : column vector, current after the sag is applied
%     sagInfo   : struct describing what was applied, for the report
%
%   Example
%     params.fs = 4000; params.sagDepth = 0.30;
%     y = applyVoltageSag(x, params);

    % ---------------------------------------------------------------------
    % Validate input
    % ---------------------------------------------------------------------
    if ~isfield(params, 'fs')
        error('applyVoltageSag:missingParam', 'Missing parameter: fs');
    end

    signal = signal(:);            % enforce column vector
    N = numel(signal);
    fs = params.fs;

    if N < 2
        sagSignal = signal;
        sagInfo = struct('applied', false, 'reason', 'signal too short');
        return;
    end

    % ---------------------------------------------------------------------
    % Resolve parameters, with defaults chosen from IEEE Std 1159
    % ---------------------------------------------------------------------
    f0            = getParam(params, 'f0',            50);
    sagDepth      = getParam(params, 'sagDepth',      0.30);
    sagStartTime  = getParam(params, 'sagStartTime',  4.00);
    sagDuration   = getParam(params, 'sagDuration',   0.30);
    sagTransition = getParam(params, 'sagTransition', 1/f0);
    enabled       = getParam(params, 'applySag',      true);

    if ~enabled
        sagSignal = signal;
        sagInfo = struct('applied', false, 'reason', 'disabled by params.applySag');
        return;
    end

    % Clamp the depth into the range IEEE 1159 actually calls a sag.
    % Below 0.1 pu residual it is an interruption, not a sag, and that is
    % handled by applyInterruption.m instead.
    if sagDepth < 0
        sagDepth = 0;
    end
    if sagDepth > 0.9
        warning('applyVoltageSag:depthClamped', ...
            'sagDepth %.2f exceeds 0.9 and was clamped. Below 0.1 pu residual is an interruption.', sagDepth);
        sagDepth = 0.9;
    end

    residual = 1 - sagDepth;       % residual voltage in per unit

    % ---------------------------------------------------------------------
    % Build the per-unit voltage envelope
    % ---------------------------------------------------------------------
    t = (0:N-1).' / fs;

    envelope = ones(N, 1);
    inSag = (t >= sagStartTime) & (t < sagStartTime + sagDuration);
    envelope(inSag) = residual;

    % Smooth the two edges with a short moving average. A moving average of
    % length L applied to a step produces a linear ramp of length L, which
    % is a simple and predictable transition.
    L = max(1, round(sagTransition * fs));
    if L > 1
        kernel = ones(L, 1) / L;
        envelope = conv(envelope, kernel, 'same');

        % conv(...,'same') pulls the first and last L/2 samples toward zero
        % because it treats the signal as zero outside its support. Restore
        % those ends so we do not accidentally create a sag at t = 0.
        half = floor(L/2);
        if half >= 1
            envelope(1:half) = 1;
            envelope(end-half+1:end) = 1;
        end
    end

    % ---------------------------------------------------------------------
    % Apply
    % ---------------------------------------------------------------------
    sagSignal = signal .* envelope;

    % ---------------------------------------------------------------------
    % Report metadata
    % ---------------------------------------------------------------------
    cycles = sagDuration * f0;

    if cycles <= 30
        category = 'instantaneous sag (IEEE 1159)';
    elseif sagDuration <= 3
        category = 'momentary sag (IEEE 1159)';
    else
        category = 'temporary sag (IEEE 1159)';
    end

    sagInfo = struct();
    sagInfo.applied = true;
    sagInfo.depth_fraction = sagDepth;
    sagInfo.residualVoltage_pu = residual;
    sagInfo.startTime_s = sagStartTime;
    sagInfo.duration_s = sagDuration;
    sagInfo.duration_cycles = cycles;
    sagInfo.transition_s = sagTransition;
    sagInfo.category = category;
    sagInfo.envelope = envelope;
    sagInfo.reference = 'IEEE Std 1159, Recommended Practice for Monitoring Electric Power Quality';

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
