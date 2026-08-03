function signal = addHarmonicDistortion(signal, params)
%ADDHARMONICDISTORTION Injects supply-side harmonic distortion.
%
%   signal = addHarmonicDistortion(signal, params)
%
% Adds extra harmonic content onto the supply (e.g. 5% 3rd harmonic
% distortion), referenced to the fundamental frequency (params.f0) and
% scaled relative to the signal's own peak amplitude so the injected
% distortion is proportionate rather than an arbitrary fixed constant.
%
% PARAMS FIELDS USED (all optional, defaults shown):
%   params.harmonics.enable        (default: true)
%   params.harmonics.orders        harmonic orders to inject (default: 3)
%   params.harmonics.magnitudePct  fraction of signal amplitude per order
%                                  (default: 0.05 -> 5% THD, brief's example)
%   params.harmonics.phaseDeg      phase in degrees per order (default: 0)
%
% NOTE: orders/magnitudePct/phaseDeg must be the same length if more than
% one harmonic is injected. Update defaults once the group's assigned
% Supply Disturbance Profile (harmonic distortion level) is available.
%

    cfg = getFieldOrDefault(params, 'harmonics', struct());

    enable    = getFieldOrDefault(cfg, 'enable',       true);
    orders    = getFieldOrDefault(cfg, 'orders',       3);
    magPct    = getFieldOrDefault(cfg, 'magnitudePct', 0.05);
    phaseDeg  = getFieldOrDefault(cfg, 'phaseDeg',     0);

    if ~enable
        return;
    end

    fs = params.fs;
    f0 = params.f0;
    N = length(signal);
    t = (0:N-1).' / fs;   % column vector, matches signal orientation

    harmonicComponent = zeros(N, 1);
    for k = 1:length(orders)
        harmonicComponent = harmonicComponent + ...
            magPct(min(k,length(magPct))) * ...
            sin(2*pi*f0*orders(k)*t + deg2rad(phaseDeg(min(k,length(phaseDeg)))));
    end

    refAmplitude = max(abs(signal));
    signal = signal + refAmplitude * harmonicComponent;
end


function val = getFieldOrDefault(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = defaultVal;
    end
end
