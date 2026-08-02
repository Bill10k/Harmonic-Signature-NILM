function [frequency, magnitude] = performFFT(signal, params)
%PERFORMFFT Computes the FFT of the input signal.
%
% INPUTS
%   signal : Time-domain signal
%   params : Project parameter structure
%
% OUTPUTS
%   frequency : Frequency axis (Hz)
%   magnitude : Single-sided FFT magnitude

    % Compute FFT
    [frequency, magnitude] = computeFFT(signal, params.fs);

    % Optional visualization
    plotSpectrum(frequency, magnitude);

end