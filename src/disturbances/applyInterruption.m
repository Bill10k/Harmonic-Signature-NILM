function signal = applyInterruption(signal, params)
%APPLYINTERRUPTION Applies a brief supply dropout and recovery.
%
%   signal = applyInterruption(signal, params)
%
% Signal drops to a low residual level for a short window (simulating a
% supply interruption), then ramps back up to full amplitude (recovery).
% Ramping in/out avoids an unrealistic instantaneous step, which real
% power interruptions don't produce.
%
% PARAMS FIELDS USED (all optional, defaults shown):
%   params.dropout.enable         (default: true)
%   params.dropout.startTime_s    seconds into signal (default: 7.0)
%   params.dropout.duration_s     seconds (default: 0.2)
%   params.dropout.residualLevel  fraction remaining during dropout,
%                                  0-1 (default: 0.05, not fully zero —
%                                  models sensor/measurement floor)
%   params.dropout.rampTime_s     ramp in/out duration (default: 0.02)
%
% NOTE: Update defaults once the group's assigned Supply Disturbance
% Profile (dropout-and-recovery timing) is available.
%

    cfg = getFieldOrDefault(params, 'dropout', struct());

    enable   = getFieldOrDefault(cfg, 'enable',        true);
    startSec = getFieldOrDefault(cfg, 'startTime_s',   7.0);
    durSec   = getFieldOrDefault(cfg, 'duration_s',    0.2);
    residual = getFieldOrDefault(cfg, 'residualLevel', 0.05);
    rampSec  = getFieldOrDefault(cfg, 'rampTime_s',    0.02);

    if ~enable
        return;
    end

    fs = params.fs;
    N = length(signal);

    startIdx = max(1, round(startSec * fs) + 1);
    endIdx   = min(N, startIdx + round(durSec * fs) - 1);
    rampSamples = max(1, round(rampSec * fs));

    mask = ones(N, 1);
    mask(startIdx:endIdx) = residual;

    % Ramp down into dropout
    rampDownStart = max(1, startIdx - rampSamples);
    mask(rampDownStart:startIdx) = ...
        linspace(1, residual, startIdx - rampDownStart + 1).';

    % Ramp up out of dropout (recovery)
    rampUpEnd = min(N, endIdx + rampSamples);
    mask(endIdx:rampUpEnd) = ...
        linspace(residual, 1, rampUpEnd - endIdx + 1).';

    signal = signal .* mask;
end


function val = getFieldOrDefault(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = defaultVal;
    end
end
