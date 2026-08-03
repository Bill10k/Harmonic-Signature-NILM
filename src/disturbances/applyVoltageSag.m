function signal = applyVoltageSag(signal, params)
%APPLYVOLTAGESAG Applies a temporary voltage sag to the signal.
%
%   signal = applyVoltageSag(signal, params)
%
% Multiplies a window of the signal by (1 - sagDepth), simulating a
% supply voltage dip. Edges are ramped over roughly one mains cycle
% rather than stepped instantly: an instant step is broadband and
% injects energy at every harmonic we measure, contaminating windows
% that overlap the edge. A real sag develops over about a cycle, so
% ramping removes an artefact that would otherwise be ours, not the
% feeder's.
%
% PARAMS FIELDS USED (all optional, defaults shown):
%   params.sag.enable       (default: true)
%   params.sag.depth        fraction, 0-1 (default: 0.30 -> 30% sag)
%   params.sag.startTime_s  seconds into signal (default: 4.0)
%   params.sag.duration_s   seconds (default: 0.5)
%   params.sag.edgeCycles   mains cycles for the ramp in/out
%                           (default: 1 cycle, i.e. 1/f0 seconds)
%
% NOTE: These are placeholder values pending the group's assigned Supply
% Disturbance Profile. Update in defaultParameters.m or override in
% main.m when that arrives.
%
    signal = signal(:);   % enforce column vector - avoids silent N x N
                           % broadcasting if a row vector is ever passed

    cfg = getFieldOrDefault(params, 'sag', struct());

    enable    = getFieldOrDefault(cfg, 'enable',      true);
    depth     = getFieldOrDefault(cfg, 'depth',       0.30);
    startSec  = getFieldOrDefault(cfg, 'startTime_s', 4.0);
    durSec    = getFieldOrDefault(cfg, 'duration_s',  0.5);
    edgeCycles = getFieldOrDefault(cfg, 'edgeCycles', 1);

    if ~enable
        return;
    end

    fs = params.fs;
    f0 = params.f0;
    N = length(signal);

    edgeSec = edgeCycles / f0;
    edgeSamples = max(1, round(edgeSec * fs));

    startIdx = max(1, round(startSec * fs) + 1);
    endIdx   = min(N, startIdx + round(durSec * fs) - 1);

    sagMask = ones(N, 1);
    sagMask(startIdx:endIdx) = 1 - depth;

    % Ramp into the sag (one mains cycle)
    rampDownStart = max(1, startIdx - edgeSamples);
    sagMask(rampDownStart:startIdx) = ...
        linspace(1, 1 - depth, startIdx - rampDownStart + 1).';

    % Ramp out of the sag (recovery, one mains cycle)
    rampUpEnd = min(N, endIdx + edgeSamples);
    sagMask(endIdx:rampUpEnd) = ...
        linspace(1 - depth, 1, rampUpEnd - endIdx + 1).';

    signal = signal .* sagMask;
end


function val = getFieldOrDefault(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = defaultVal;
    end
end
