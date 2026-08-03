function [interruptedSignal, interruptionInfo] = applyInterruption(signal, params)
%APPLYINTERRUPTION Applies a brief supply interruption and recovery.
%
%   [interruptedSignal, interruptionInfo] = APPLYINTERRUPTION(signal, params)
%
%   IEEE Std 1159 defines an interruption as a reduction of supply voltage
%   to below 0.1 pu. A momentary interruption lasts from half a cycle to
%   3 seconds and is exactly what an auto-recloser produces on a feeder with
%   a transient fault: the supply is cut, and restored a fraction of a
%   second later.
%
%   Two things happen at the measurement point:
%
%     1. During the interruption the current collapses to (almost) zero.
%        A small residual is retained rather than an exact zero, because a
%        real meter still sees leakage and its own noise floor, and an exact
%        zero makes the "is the supply live" test trivially easy in a way a
%        real system would not enjoy.
%
%     2. On restoration the load does not resume instantly. Motors re-accelerate
%        and switch-mode supplies recharge their input capacitors, so the
%        current recovers over a short time constant. That recovery period is
%        the hardest part of the record to classify and we report it as such.
%
%   This is the disturbance most likely to cause our classifier to fail, and
%   that is intentional - the brief asks us to identify and explain a failure
%   mode, and this one is both real and explainable.
%
%   INPUTS
%     signal : column vector, aggregate current in amperes
%     params : struct. Fields used (all optional except fs):
%                fs                      sampling frequency, Hz    [required]
%                f0                      fundamental, Hz           [default 50]
%                interruptionStartTime   start, seconds            [default 7.5]
%                interruptionDuration    length, seconds           [default 0.10]
%                interruptionResidual    residual level, pu        [default 0.02]
%                interruptionCollapseTau collapse constant, s      [default 0.002]
%                interruptionRecoveryTau recovery constant, s      [default 0.05]
%                applyInterruptionStage  set false to disable      [default true]
%
%   OUTPUTS
%     interruptedSignal : column vector, current after the interruption
%     interruptionInfo  : struct describing what was applied

    % ---------------------------------------------------------------------
    % Validate input
    % ---------------------------------------------------------------------
    if ~isfield(params, 'fs')
        error('applyInterruption:missingParam', 'Missing parameter: fs');
    end

    signal = signal(:);
    N = numel(signal);
    fs = params.fs;

    if N < 2
        interruptedSignal = signal;
        interruptionInfo = struct('applied', false, 'reason', 'signal too short');
        return;
    end

    % ---------------------------------------------------------------------
    % Resolve parameters
    % ---------------------------------------------------------------------
    f0          = getParam(params, 'f0',                      50);
    startTime   = getParam(params, 'interruptionStartTime',   7.50);
    duration    = getParam(params, 'interruptionDuration',    0.10);
    residual    = getParam(params, 'interruptionResidual',    0.02);
    collapseTau = getParam(params, 'interruptionCollapseTau', 0.002);
    recoveryTau = getParam(params, 'interruptionRecoveryTau', 0.05);
    enabled     = getParam(params, 'applyInterruptionStage',  true);

    if ~enabled
        interruptedSignal = signal;
        interruptionInfo = struct('applied', false, 'reason', 'disabled by params.applyInterruptionStage');
        return;
    end

    if residual < 0
        residual = 0;
    end
    if residual > 0.1
        warning('applyInterruption:residualTooHigh', ...
            'interruptionResidual %.2f exceeds 0.1 pu. IEEE 1159 would classify that as a sag, not an interruption.', residual);
    end

    % ---------------------------------------------------------------------
    % Build the envelope: collapse, hold, recover
    % ---------------------------------------------------------------------
    t = (0:N-1).' / fs;

    stopTime = startTime + duration;

    envelope = ones(N, 1);

    duringIdx = (t >= startTime) & (t < stopTime);
    afterIdx  = (t >= stopTime);

    % Collapse: fall from 1 to the residual level with a short exponential.
    if any(duringIdx)
        tau = t(duringIdx) - startTime;
        envelope(duringIdx) = residual + (1 - residual) * exp(-tau / max(collapseTau, eps));
    end

    % Recovery: rise from the residual level back to 1.
    if any(afterIdx)
        tau = t(afterIdx) - stopTime;
        envelope(afterIdx) = 1 - (1 - residual) * exp(-tau / max(recoveryTau, eps));
    end

    % ---------------------------------------------------------------------
    % Apply
    % ---------------------------------------------------------------------
    interruptedSignal = signal .* envelope;

    % ---------------------------------------------------------------------
    % Report metadata
    %
    % recoverySettling_s is how long the current stays visibly depressed
    % after restoration. We take five time constants as the settling point
    % (at 5*tau the envelope is within 0.7% of its final value). Any analysis
    % window overlapping the interruption or this settling period should be
    % treated as unreliable, and the classifier uses this to hold state.
    % ---------------------------------------------------------------------
    settling = 5 * recoveryTau;

    if duration * f0 <= 30
        category = 'momentary interruption, recloser-like (IEEE 1159)';
    elseif duration <= 3
        category = 'momentary interruption (IEEE 1159)';
    else
        category = 'temporary interruption (IEEE 1159)';
    end

    interruptionInfo = struct();
    interruptionInfo.applied = true;
    interruptionInfo.startTime_s = startTime;
    interruptionInfo.stopTime_s = stopTime;
    interruptionInfo.duration_s = duration;
    interruptionInfo.duration_cycles = duration * f0;
    interruptionInfo.residual_pu = residual;
    interruptionInfo.collapseTau_s = collapseTau;
    interruptionInfo.recoveryTau_s = recoveryTau;
    interruptionInfo.recoverySettling_s = settling;
    interruptionInfo.affectedWindow_s = [startTime, stopTime + settling];
    interruptionInfo.category = category;
    interruptionInfo.envelope = envelope;
    interruptionInfo.reference = 'IEEE Std 1159, Recommended Practice for Monitoring Electric Power Quality';

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
