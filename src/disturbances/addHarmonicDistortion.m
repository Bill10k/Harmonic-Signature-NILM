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
%   params.harmonics.orders        harmonic orders to inject
%                                  (default: [5 7 11])
%   params.harmonics.magnitudePct  fraction of the FUNDAMENTAL amplitude,
%                                  per order (default: [0.06 0.045 0.025],
%                                  chosen so the RMS-combined THD is
%                                  ~7.9%, matching the report's ~8% THD
%                                  figure -- see note below)
%   params.harmonics.phaseDeg      phase in degrees per order (default: 0
%                                  for each -- update if the report
%                                  specifies exact phases)
%
% NOTE: orders/magnitudePct/phaseDeg must be the same length if more than
% one harmonic is injected.
%
% Default targets the 5th, 7th and 11th harmonics -- matching what the
% team's report and slides currently describe (this stresses the laptop
% charger's dominant harmonics, rather than the 3rd, which is the LED
% bank's dominant harmonic and was this module's original default).
% Total THD is combined as an RMS sum (sqrt(sum(magnitudePct.^2))), which
% is the standard IEEE 519 definition, not a simple sum -- the per-order
% split (6%/4.5%/2.5%) is a reasonable decreasing-with-order shape but
% was not separately specified by the team; confirm the exact per-order
% split against the assigned Group 3 parameter sheet once available, and
% update here if it differs.
%
    signal = signal(:);   % enforce column vector

    cfg = getFieldOrDefault(params, 'harmonics', struct());

    enable    = getFieldOrDefault(cfg, 'enable',       true);
    orders    = getFieldOrDefault(cfg, 'orders',       [5 7 11]);
    magPct    = getFieldOrDefault(cfg, 'magnitudePct', [0.06 0.045 0.025]);
    phaseDeg  = getFieldOrDefault(cfg, 'phaseDeg',     [0 0 0]);

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
