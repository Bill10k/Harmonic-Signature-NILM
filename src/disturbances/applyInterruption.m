function signal = applyInterruption(signal, params)
%APPLYINTERRUPTION Applies a brief supply dropout and recovery.
%
%   signal = applyInterruption(signal, params)
%
% Signal drops to a low residual level for a short window (simulating a
% supply interruption), then recovers to full amplitude.
%
% IMPORTANT - residual level must sit BELOW the classifier's fundamental
% floor: the classification module treats a window as "no live supply"
% when its fundamental amplitude falls below params.fundamentalFloor_A
% (see main pipeline / classifyLoad). A residual of, e.g., 0.05 of this
% aggregate's typical amplitude can leave current an order of magnitude
% above that floor, so the interruption is never actually recognised as
% an outage -- every appliance coefficient just collapses under the ON
% threshold and gets reported as falsely switched off. Default here is
% deliberately low (0.02) to sit under a typical floor; if you raise it,
% check the result against params.fundamentalFloor_A first.
%
% PARAMS FIELDS USED (all optional, defaults shown):
%   params.dropout.enable         (default: true)
%   params.dropout.startTime_s    seconds into signal (default: 7.0)
%   params.dropout.duration_s     seconds (default: 0.2)
%   params.dropout.residualLevel  fraction remaining during dropout,
%                                 0-1 (default: 0.02 -- checked against
%                                 the classifier's floor, see above)
%   params.dropout.rampTime_s     ramp in/out duration (default: 0.02)
%
    signal = signal(:);   % enforce column vector

    cfg = getFieldOrDefault(params, 'dropout', struct());

    enable   = getFieldOrDefault(cfg, 'enable',        true);
    startSec = getFieldOrDefault(cfg, 'startTime_s',   7.0);
    durSec   = getFieldOrDefault(cfg, 'duration_s',    0.2);
    residual = getFieldOrDefault(cfg, 'residualLevel', 0.02);
    rampSec  = getFieldOrDefault(cfg, 'rampTime_s',    0.02);

    if ~enable
        return;
    end

    % Warn if the residual would leave current above the classifier's
    % fundamental floor, since that silently defeats the whole point of
    % this disturbance (see note above).
    if isfield(params, 'fundamentalFloor_A')
        approxPeak = max(abs(signal));
        residualCurrent = residual * approxPeak;
        if residualCurrent > params.fundamentalFloor_A
            warning(['applyInterruption:residualAboveFloor', ...
                'Dropout residual (%.3f A) is above the classifier''s ', ...
                'fundamentalFloor_A (%.3f A). The interruption may not ', ...
                'be recognised as an outage downstream.'], ...
                residualCurrent, params.fundamentalFloor_A);
        end
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
