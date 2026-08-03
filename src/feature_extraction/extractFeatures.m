function features = extractFeatures(harm, segment, params)
%EXTRACTFEATURES Builds the feature vector for one analysis window.
%
%   features = EXTRACTFEATURES(harm, segment, params)
%
%   INPUTS
%     harm    : struct from extractHarmonicPhasors for this window
%     segment : the raw (unwindowed) time-domain samples of this window,
%               in amperes - needed for a true RMS value
%     params  : project parameter struct
%
%   OUTPUT
%     features : struct with fields
%                  RMS         true RMS current, amperes
%                  THD         total harmonic distortion, percent
%                  phaseShift  fundamental phase, degrees, sine reference
%                  harmMag     1 x K peak amplitudes at each analysis order
%                  harmRatio   1 x (K-1) magnitudes relative to fundamental
%                  harmPhasor  1 x K complex phasors
%                  orders      1 x K the harmonic orders themselves
%                  H3, H5, H7  named ratios, so callers never index blindly
%                  isLive      false if the window looks like an outage
%
%   THREE CORRECTIONS FROM THE FIRST VERSION, all of which changed results:
%
%   1. RMS IS NOW A REAL RMS. It used to be sqrt(mean(magnitude.^2)) over
%      the FFT bins, which is a number with no physical meaning and no unit.
%      The classifier compares RMS against thresholds in amperes, so that
%      comparison could never work. RMS is now computed from the time-domain
%      samples, which is the definition of RMS.
%
%   2. HARMONIC RATIOS ARE NOW NAMED, NOT POSITIONAL. The old code built
%      harmRatio = harmMag(2:end)/H1 and the classifier then read element 1
%      as the 3rd harmonic. Because the old extractHarmonics returned every
%      multiple of 50 Hz, element 1 was actually the 2nd harmonic and every
%      decision was made on the wrong quantity. Named fields H3, H5 and H7
%      are provided so no caller has to count positions again.
%
%   3. PHASE IS REAL. It used to be hard-coded to zero, which made the
%      refrigerator - the only appliance identified by phase lag -
%      undetectable no matter what the signal contained.
%
%   See also EXTRACTHARMONICPHASORS, EXTRACTFEATURESET, CLASSIFYLOAD.

    if nargin < 3
        params = struct();
    end

    if ~isstruct(harm) || ~isfield(harm, 'mag')
        error('extractFeatures:badHarmonics', ...
            'harm must be the struct returned by extractHarmonicPhasors.');
    end

    segment = segment(:);

    orders = harm.orders(:).';
    harmMag = harm.mag(:).';
    harmPhasor = harm.phasor(:).';
    harmPhase = harm.phase_deg(:).';

    % ---------------------------------------------------------------------
    % Fundamental
    % ---------------------------------------------------------------------
    fundIdx = find(orders == 1, 1);

    if isempty(fundIdx)
        error('extractFeatures:noFundamental', ...
            'The analysis harmonic set must include order 1.');
    end

    H1 = harmMag(fundIdx);

    % ---------------------------------------------------------------------
    % True RMS current, from the time domain
    % ---------------------------------------------------------------------
    if isempty(segment)
        RMS = 0;
    else
        RMS = sqrt(mean(segment.^2));
    end

    % ---------------------------------------------------------------------
    % Harmonic ratios relative to the fundamental
    %
    % A guard on H1 matters here. During the supply interruption the
    % fundamental collapses toward zero, and dividing by it would produce
    % enormous ratios that look like a violently distorted rectifier load.
    % The guard is set relative to the noise floor rather than to eps.
    % ---------------------------------------------------------------------
    fundamentalFloor = getParam(params, 'fundamentalFloor_A', 0.05);

    isLive = (H1 > fundamentalFloor);

    harmonicIdx = (orders ~= 1);

    if isLive
        harmRatio = harmMag(harmonicIdx) / H1;
        THD = 100 * sqrt(sum(harmMag(harmonicIdx).^2)) / H1;
    else
        harmRatio = zeros(1, sum(harmonicIdx));
        THD = 0;
    end

    % ---------------------------------------------------------------------
    % Named harmonic ratios
    % ---------------------------------------------------------------------
    features = struct();

    features.RMS = RMS;
    features.THD = THD;
    features.phaseShift = harmPhase(fundIdx);
    features.harmMag = harmMag;
    features.harmRatio = harmRatio;
    features.harmPhasor = harmPhasor;
    features.harmPhase_deg = harmPhase;
    features.orders = orders;
    features.fundamental_A = H1;
    features.isLive = isLive;

    features.H3 = namedRatio(orders, harmMag, H1, 3, isLive);
    features.H5 = namedRatio(orders, harmMag, H1, 5, isLive);
    features.H7 = namedRatio(orders, harmMag, H1, 7, isLive);
    features.H9 = namedRatio(orders, harmMag, H1, 9, isLive);
    features.H11 = namedRatio(orders, harmMag, H1, 11, isLive);
    features.H13 = namedRatio(orders, harmMag, H1, 13, isLive);
    features.H15 = namedRatio(orders, harmMag, H1, 15, isLive);

    % Odd-harmonic energy above the fundamental, in amperes. Useful as a
    % single scalar summary of "how nonlinear does this window look".
    features.harmonicEnergy_A = sqrt(sum(harmMag(harmonicIdx).^2));

end

% =========================================================================
% Helper: ratio of a named harmonic order to the fundamental
% Returns 0 if that order is not in the analysis set or the window is dead.
% =========================================================================
function ratio = namedRatio(orders, harmMag, H1, wantedOrder, isLive)

    ratio = 0;

    if ~isLive
        return;
    end

    idx = find(orders == wantedOrder, 1);

    if ~isempty(idx) && H1 > 0
        ratio = harmMag(idx) / H1;
    end

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
