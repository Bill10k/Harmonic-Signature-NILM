function harmonics = extractHarmonics(frequency, magnitude, orders, f0)
%EXTRACTHARMONICS Harmonic magnitudes as a simple two-column table.
%
%   harmonics = EXTRACTHARMONICS(frequency, magnitude)
%   harmonics = EXTRACTHARMONICS(frequency, magnitude, orders)
%   harmonics = EXTRACTHARMONICS(frequency, magnitude, orders, f0)
%
%   Returns an N x 2 matrix: column 1 is the harmonic frequency in Hz and
%   column 2 is its peak amplitude.
%
%   This is the magnitude-only view of the spectrum, kept for the standalone
%   FFT demonstration in MAIN.m and for anyone who wants a quick look at the
%   harmonic content. The main pipeline does NOT use it - it uses
%   extractHarmonicPhasors.m instead, which also returns phase and is what
%   the classifier needs.
%
%   Two changes from the original version:
%
%     * The default order set is now the ODD harmonics 1, 3, 5 ... 15 rather
%       than every multiple of 50 Hz up to the 10th. Even harmonics carry no
%       information for symmetric loads, and stopping at the 10th missed the
%       13th and 15th that identify the laptop charger.
%
%     * The disp() calls have been removed. This function is called once per
%       analysis window, so printing inside it produced over a hundred blocks
%       of console output per run and hid any real warnings.
%
%   INPUTS
%     frequency : bin frequency vector, Hz
%     magnitude : peak-amplitude spectrum
%     orders    : optional harmonic orders  [default 1:2:15]
%     f0        : optional fundamental, Hz  [default 50]
%
%   OUTPUT
%     harmonics : N x 2, [frequency_Hz, peakAmplitude]

    if nargin < 3 || isempty(orders)
        orders = 1:2:15;
    end

    if nargin < 4 || isempty(f0)
        f0 = 50;
    end

    frequency = frequency(:);
    magnitude = magnitude(:);
    orders = orders(:).';

    numHarmonics = numel(orders);
    harmonics = zeros(numHarmonics, 2);

    for k = 1:numHarmonics

        targetFreq = orders(k) * f0;

        [~, index] = min(abs(frequency - targetFreq));

        harmonics(k, 1) = targetFreq;
        harmonics(k, 2) = magnitude(index);

    end

end
