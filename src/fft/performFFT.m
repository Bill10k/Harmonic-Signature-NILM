function [frequency, magnitude, phase] = performFFT(signal, params, winCoeffs)
%PERFORMFFT Project wrapper around computeFFT.
%
%   [frequency, magnitude] = PERFORMFFT(signal, params)
%   [frequency, magnitude, phase] = PERFORMFFT(signal, params, winCoeffs)
%
%   Applies the project's sampling frequency and plotting policy to
%   computeFFT. The plot is now OPTIONAL and off by default.
%
%   The original version called plotSpectrum on every invocation. Once the
%   pipeline analyses each window separately that is one figure window per
%   window - over a hundred per run - which makes MATLAB unusable and hides
%   the figures we actually want. Set params.plotSpectrum = true to bring
%   the plot back for a single manual call.
%
%   INPUTS
%     signal    : time-domain signal
%     params    : project parameter struct, must contain fs
%     winCoeffs : optional window coefficients already applied to signal,
%                 passed through so the amplitude scaling stays correct
%
%   OUTPUTS
%     frequency : bin frequencies, Hz
%     magnitude : peak amplitudes, amperes
%     phase     : phases, radians, cosine reference

    if ~isfield(params, 'fs')
        error('performFFT:missingParam', 'Missing parameter: fs');
    end

    if nargin < 3
        winCoeffs = [];
    end

    [frequency, magnitude, phase] = computeFFT(signal, params.fs, winCoeffs);

    showPlot = false;
    if isfield(params, 'plotSpectrum') && ~isempty(params.plotSpectrum)
        showPlot = params.plotSpectrum;
    end

    if showPlot
        plotSpectrum(frequency, magnitude);
    end

end
