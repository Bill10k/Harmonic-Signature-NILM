function harm = extractHarmonicPhasors(frequency, magnitude, phase, params, startTime)
%EXTRACTHARMONICPHASORS Harmonic magnitudes and phases as complex phasors.
%
%   harm = EXTRACTHARMONICPHASORS(frequency, magnitude, phase, params)
%   harm = EXTRACTHARMONICPHASORS(frequency, magnitude, phase, params, startTime)
%
%   Reads the amplitude and phase of each analysis harmonic out of a single
%   window's spectrum and returns them as complex phasors, so that harmonics
%   from different appliances can be added and subtracted the way they
%   physically combine on the feeder.
%
%   WHY PHASORS AND NOT JUST MAGNITUDES
%   Two appliances drawing the same harmonic at different phase angles do not
%   simply add their magnitudes - they add as vectors, and can partially
%   cancel. A classifier that only looks at magnitudes cannot represent that,
%   and will misjudge any window where two rectifier loads are on together.
%   Working in phasors lets the classifier predict the aggregate correctly.
%
%   WHY ONLY ODD HARMONICS
%   A current waveform with half-wave symmetry - which is what any balanced,
%   symmetric load produces - contains only odd harmonics. Even harmonics
%   indicate a DC offset or asymmetric conduction, neither of which our
%   appliance models produce. Reading them adds noise and no information, so
%   the default set is 1, 3, 5, 7, 9, 11, 13, 15.
%
%   PHASE REFERENCE AND DE-ROTATION
%   The phase the FFT reports depends on where the window starts. A window
%   beginning at 4.0 s sees a different instantaneous phase from one starting
%   at 4.1 s, even for an identical steady signal. To make phases comparable
%   across windows, each harmonic phase is rotated back by 2*pi*k*f0*startTime.
%   After this every window is referenced to absolute time zero, which is what
%   makes the appliance templates in applianceLibrary.m directly comparable.
%
%   INPUTS
%     frequency : bin frequency vector from computeFFT, Hz
%     magnitude : peak-amplitude spectrum from computeFFT
%     phase     : phase spectrum from computeFFT, radians, cosine reference
%     params    : struct. Fields used:
%                   f0                 fundamental, Hz     [default 50]
%                   analysisHarmonics  orders to read      [default 1:2:15]
%     startTime : window start time in seconds, for de-rotation [default 0]
%
%   OUTPUT
%     harm : struct with fields
%              orders      1 x K harmonic orders
%              freq_Hz     1 x K nominal frequencies
%              mag         1 x K peak amplitudes, amperes
%              phase_rad   1 x K de-rotated phases, sine reference
%              phase_deg   1 x K same, degrees, wrapped to +/-180
%              phasor      1 x K complex, mag .* exp(1i*phase_rad)
%              binIndex    1 x K which spectrum bin each came from
%              binError_Hz 1 x K how far that bin sits from the ideal
%
%   See also COMPUTEFFT, APPLIANCELIBRARY.

    if nargin < 5 || isempty(startTime)
        startTime = 0;
    end

    frequency = frequency(:);
    magnitude = magnitude(:);
    phase = phase(:);

    f0 = getParam(params, 'f0', 50);
    orders = getParam(params, 'analysisHarmonics', 1:2:15);

    orders = orders(:).';
    K = numel(orders);

    % Discard any requested harmonic that sits at or above Nyquist - it
    % cannot be resolved and reading it would return an aliased value.
    nyquist = max(frequency);
    keep = (orders * f0) <= nyquist;

    if ~all(keep)
        orders = orders(keep);
        K = numel(orders);
        if K == 0
            error('extractHarmonicPhasors:noValidHarmonics', ...
                'No requested harmonic falls below Nyquist (%.1f Hz). Increase fs.', nyquist);
        end
    end

    harm = struct();
    harm.orders = orders;
    harm.freq_Hz = orders * f0;
    harm.mag = zeros(1, K);
    harm.phase_rad = zeros(1, K);
    harm.phase_deg = zeros(1, K);
    harm.phasor = zeros(1, K);
    harm.binIndex = zeros(1, K);
    harm.binError_Hz = zeros(1, K);

    for k = 1:K

        targetFreq = orders(k) * f0;

        % Nearest bin. With a window of exactly ten fundamental cycles the
        % harmonics land on bin centres and this error is zero.
        [binError, idx] = min(abs(frequency - targetFreq));

        rawPhase = phase(idx);

        % Undo the window's start-time rotation, then convert from the DFT's
        % cosine reference to a sine reference so the values line up with the
        % appliance definitions, which are written as sines.
        deRotated = rawPhase + pi/2 - 2*pi*targetFreq*startTime;

        harm.mag(k) = magnitude(idx);
        harm.phase_rad(k) = deRotated;
        harm.phase_deg(k) = wrapTo180Degrees(deRotated * 180/pi);
        harm.phasor(k) = magnitude(idx) * exp(1i * deRotated);
        harm.binIndex(k) = idx;
        harm.binError_Hz(k) = binError;

    end

    harm.startTime_s = startTime;
    harm.f0_Hz = f0;
    harm.magnitudeUnits = 'peak amperes';
    harm.phaseReference = 'sine at absolute time zero';

end

% =========================================================================
% Helper: wrap an angle in degrees to the range -180 to +180
% Written out rather than using wrapTo180, which needs the Mapping Toolbox.
% =========================================================================
function wrapped = wrapTo180Degrees(angleDeg)

    wrapped = mod(angleDeg + 180, 360) - 180;

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
