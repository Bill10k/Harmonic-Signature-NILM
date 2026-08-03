function signal = addHarmonicDistortion(signal, params)
%ADDHARMONICDISTORTION Injects supply-side harmonic distortion.
%
%   signal = addHarmonicDistortion(signal, params)
%
% Adds extra harmonic content onto the supply, referenced to the SIGNAL'S
% FUNDAMENTAL component (not its peak sample). This matters: THD is
% defined by IEEE 519 as a percentage of the fundamental. Referencing the
% peak instead ties the injected distortion level to whatever the
% largest single sample happens to be — on this aggregate, that is the
% refrigerator's startup inrush (3.2x normal current), a transient
% lasting about a second. Referencing the fundamental makes the
% distortion level steady-state and directly comparable to the
% standard's limit (e.g. 5% under IEEE 519 for general distribution).
%
% PARAMS FIELDS USED (all optional, defaults shown):
%   params.harmonics.enable        (default: true)
%   params.harmonics.orders        harmonic orders to inject (default: 3)
%   params.harmonics.magnitudePct  fraction of the FUNDAMENTAL amplitude,
%                                  per order (default: 0.05 -> 5% THD)
%   params.harmonics.phaseDeg      phase in degrees per order (default: 0)
%
% NOTE: orders/magnitudePct/phaseDeg must be the same length if more than
% one harmonic is injected. Default targets the 3rd harmonic; this is a
% deliberate design choice (stresses the LED bank's dominant harmonic) --
% confirm with the team which harmonic(s) the report/slides describe
% before final submission, since the target harmonic changes which
% appliance's signature is most stressed.
%
    signal = signal(:);   % enforce column vector

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
    t = (0:N-1).' / fs;

    % --- Estimate the fundamental amplitude via a single-bin DFT at f0 ---
    % This gives a steady-state reference unaffected by any one transient
    % sample, unlike max(abs(signal)).
    fundamentalAmp = estimateFundamentalAmplitude(signal, fs, f0);

    harmonicComponent = zeros(N, 1);
    for k = 1:length(orders)
        harmonicComponent = harmonicComponent + ...
            magPct(min(k,length(magPct))) * ...
            sin(2*pi*f0*orders(k)*t + deg2rad(phaseDeg(min(k,length(phaseDeg)))));
    end

    signal = signal + fundamentalAmp * harmonicComponent;
end


function amp = estimateFundamentalAmplitude(signal, fs, f0)
% Single-frequency (Goertzel-style) amplitude estimate at f0, using the
% whole recording. Robust to any single transient sample, unlike
% max(abs(signal)).
    N = length(signal);
    t = (0:N-1).' / fs;
    % Correlate against a unit-amplitude reference sinusoid at f0
    refCos = cos(2*pi*f0*t);
    refSin = sin(2*pi*f0*t);
    a = 2/N * sum(signal .* refCos);
    b = 2/N * sum(signal .* refSin);
    amp = sqrt(a^2 + b^2);
end


function val = getFieldOrDefault(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = defaultVal;
    end
end
