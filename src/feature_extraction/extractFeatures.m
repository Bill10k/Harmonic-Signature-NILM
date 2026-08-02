function features = extractFeatures(frequency, magnitude)
%EXTRACTFEATURES Extracts features used for NILM classification.
%
% INPUTS:
%   frequency - Frequency vector from FFT
%   magnitude - FFT magnitude spectrum
%
% OUTPUT:
%   features.RMS
%   features.THD
%   features.phaseShift
%   features.harmMag
%   features.harmRatio

% Extract harmonic magnitudes from FFT
harmonics = extractHarmonics(frequency, magnitude);

if isempty(harmonics)
    error('No harmonics were extracted from the FFT spectrum.');
end

% Fundamental magnitude (50 Hz)
H1 = harmonics(1,2);

% Harmonic magnitudes
harmMag = harmonics(:,2);

% Harmonic ratios
if H1 > 0
    harmRatio = harmMag(2:end) ./ H1;
else
    harmRatio = zeros(length(harmMag)-1,1);
end

% RMS estimate
RMS = sqrt(mean(magnitude.^2));

% Total Harmonic Distortion
if H1 > 0
    THD = sqrt(sum(harmMag(2:end).^2)) / H1 * 100;
else
    THD = 0;
end

% Placeholder until FFT phase is available
phaseShift = 0;

% Package extracted features
features = struct();

features.RMS = RMS;
features.THD = THD;
features.phaseShift = phaseShift;
features.harmMag = harmMag;
features.harmRatio = harmRatio;

end