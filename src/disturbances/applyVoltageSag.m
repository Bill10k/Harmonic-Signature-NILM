function signal = applyVoltageSag(signal, params)
%APPLYVOLTAGESAG Applies a temporary voltage sag to the signal.
%
%   signal = applyVoltageSag(signal, params)
%
% Multiplies a window of the signal by (1 - sagDepth), simulating a
% supply voltage dip (e.g. sagDepth = 0.30 means the signal amplitude
% drops to 70% of normal for sagDuration_s seconds).
%
% PARAMS FIELDS USED (all optional, defaults shown):
%   params.sag.enable       (default: true)
%   params.sag.depth        fraction, 0-1 (default: 0.30  -> 30% sag)
%   params.sag.startTime_s  seconds into signal (default: 4.0)
%   params.sag.duration_s   seconds (default: 0.5)
%
% NOTE: These are placeholder values from the project brief's own
% examples. Update in defaultParameters.m (or override in main.m) once
% the group's assigned Supply Disturbance Profile parameter sheet is
% available. Nothing in this file needs to change when that happens.
%

    cfg = getFieldOrDefault(params, 'sag', struct());

    enable   = getFieldOrDefault(cfg, 'enable',      true);
    depth    = getFieldOrDefault(cfg, 'depth',       0.30);
    startSec = getFieldOrDefault(cfg, 'startTime_s', 4.0);
    durSec   = getFieldOrDefault(cfg, 'duration_s',  0.5);

    if ~enable
        return;
    end

    fs = params.fs;
    N = length(signal);

    startIdx = max(1, round(startSec * fs) + 1);
    endIdx   = min(N, startIdx + round(durSec * fs) - 1);

    sagMask = ones(N, 1);
    sagMask(startIdx:endIdx) = 1 - depth;

    signal = signal .* sagMask;
end


function val = getFieldOrDefault(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = defaultVal;
    end
end
