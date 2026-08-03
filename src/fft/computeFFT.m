function [frequency, magnitude, phase, fftInfo] = computeFFT(signal, Fs, winCoeffs)
%COMPUTEFFT Single-sided amplitude and phase spectrum of a signal.
%
%   [frequency, magnitude] = COMPUTEFFT(signal, Fs)
%   [frequency, magnitude, phase] = COMPUTEFFT(signal, Fs)
%   [frequency, magnitude, phase, fftInfo] = COMPUTEFFT(signal, Fs, winCoeffs)
%
%   Returns a correctly scaled single-sided spectrum. Two scaling details
%   matter and both were wrong in the first version of this file:
%
%   1. FACTOR OF TWO. The FFT of a real signal is symmetric: a sinusoid of
%      amplitude A appears as two lines of height A*N/2, one at +f and one
%      at -f. Keeping only the positive half therefore discards half the
%      energy, and the retained half must be doubled to recover the true
%      amplitude. Without this every current we report is half its real
%      value. DC and, for even N, the Nyquist bin are NOT doubled because
%      they have no mirror partner.
%
%   2. WINDOW AMPLITUDE CORRECTION. If the segment has been multiplied by a
%      window before transforming, the window reduces the amplitude of every
%      component by the mean of the window coefficients. Dividing by
%      sum(winCoeffs) instead of by N restores the true amplitude. Pass the
%      window coefficients as the third argument to enable this.
%
%   After scaling, MAGNITUDE is in PEAK amperes. Divide by sqrt(2) for RMS.
%
%   PHASE is returned in radians, referenced to a COSINE at t = 0, which is
%   the convention the DFT itself uses. For a signal A*sin(2*pi*f*t + phi)
%   the value returned at the signal's bin is phi - pi/2. Callers that want
%   a sine reference should add pi/2; extractHarmonicPhasors.m does this.
%
%   INPUTS
%     signal    : vector, time-domain samples
%     Fs        : sampling frequency, Hz
%     winCoeffs : optional, the window applied to the segment
%
%   OUTPUTS
%     frequency : column vector of bin frequencies, 0 to Nyquist, Hz
%     magnitude : column vector of peak amplitudes
%     phase     : column vector of phases, radians, cosine reference
%     fftInfo   : struct with resolution and scaling details
%
%   Backwards compatible with the original two-output call.

    signal = signal(:);
    N = numel(signal);

    if N < 2
        frequency = 0;
        magnitude = abs(signal);
        phase = 0;
        fftInfo = struct('N', N, 'valid', false);
        return;
    end

    if nargin < 3 || isempty(winCoeffs)
        winCoeffs = [];
        coherentGain = N;               % rectangular window: sum of ones is N
        windowUsed = 'none (rectangular)';
    else
        winCoeffs = winCoeffs(:);
        if numel(winCoeffs) ~= N
            error('computeFFT:windowLengthMismatch', ...
                'winCoeffs has %d elements but the signal has %d samples.', numel(winCoeffs), N);
        end
        coherentGain = sum(winCoeffs);
        windowUsed = 'caller-supplied window';
    end

    if abs(coherentGain) < eps
        error('computeFFT:degenerateWindow', 'Window coefficients sum to zero.');
    end

    % ---------------------------------------------------------------------
    % Transform
    % ---------------------------------------------------------------------
    X = fft(signal);

    % Number of points in the single-sided spectrum, including DC and, when
    % N is even, the Nyquist bin.
    half = floor(N/2) + 1;

    Xhalf = X(1:half);

    % ---------------------------------------------------------------------
    % Scale to peak amplitude
    % ---------------------------------------------------------------------
    magnitude = abs(Xhalf) * 2 / coherentGain;

    % DC has no negative-frequency twin, so undo the doubling.
    magnitude(1) = magnitude(1) / 2;

    % For even N the last retained bin is exactly Nyquist, which also has no
    % twin. For odd N there is no exact Nyquist bin and nothing to correct.
    if mod(N, 2) == 0
        magnitude(end) = magnitude(end) / 2;
    end

    phase = angle(Xhalf);

    frequency = (0:half-1).' * (Fs / N);

    % ---------------------------------------------------------------------
    % Diagnostics used by the report
    % ---------------------------------------------------------------------
    fftInfo = struct();
    fftInfo.valid = true;
    fftInfo.N = N;
    fftInfo.Fs = Fs;
    fftInfo.binResolution_Hz = Fs / N;
    fftInfo.nyquist_Hz = Fs / 2;
    fftInfo.duration_s = N / Fs;
    fftInfo.coherentGain = coherentGain;
    fftInfo.window = windowUsed;
    fftInfo.amplitudeUnits = 'peak (divide by sqrt(2) for RMS)';
    fftInfo.phaseReference = 'cosine at t = 0, radians';

end
