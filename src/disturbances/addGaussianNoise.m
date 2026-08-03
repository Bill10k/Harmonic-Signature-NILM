function [noisySignal, noiseInfo] = addGaussianNoise(signal, params)
%ADDGAUSSIANNOISE Adds white Gaussian measurement noise at a target SNR.
%
%   [noisySignal, noiseInfo] = ADDGAUSSIANNOISE(signal, params)
%
%   This represents the measurement chain rather than the feeder: current
%   transformer noise, amplifier thermal noise and ADC quantisation. Those
%   sources are independent of each other and of the signal, so by the
%   central limit theorem their sum is well modelled as white Gaussian noise.
%
%   Level selection: the brief frames the meter as a low-cost device. A 12-bit
%   ADC driven near full scale gives a theoretical signal-to-noise ratio of
%   about 6.02*12 + 1.76 = 74 dB, but a cheap current transformer front end
%   loses far more than that in practice. The default of 35 dB is a
%   deliberately pessimistic figure that leaves the low-amplitude harmonics
%   of the 0.7 A LED load genuinely close to the noise floor - which is where
%   the interesting failures live.
%
%   Noise is added LAST in the disturbance chain because it represents the
%   measurement instrument, which sits at the end of the physical path. The
%   sag, background distortion and interruption all happen on the feeder,
%   before the meter sees anything.
%
%   INPUTS
%     signal : column vector, aggregate current in amperes
%     params : struct. Fields used (all optional except fs):
%                noiseSNR_dB  target signal-to-noise ratio, dB   [default 35]
%                randomSeed   seed for repeatability            [default 20897245]
%                applyNoise   set false to disable              [default true]
%
%   OUTPUTS
%     noisySignal : column vector, current with measurement noise added
%     noiseInfo   : struct describing what was added
%
%   The random seed is fixed by default so that every run of the pipeline
%   produces identical results. Reproducibility is a marking criterion: the
%   course team must be able to re-run our analysis and obtain our numbers.

    signal = signal(:);
    N = numel(signal);

    if N < 1
        noisySignal = signal;
        noiseInfo = struct('applied', false, 'reason', 'empty signal');
        return;
    end

    % ---------------------------------------------------------------------
    % Resolve parameters
    % ---------------------------------------------------------------------
    snr_dB  = getParam(params, 'noiseSNR_dB', 35);
    seed    = getParam(params, 'randomSeed',  20897245);
    enabled = getParam(params, 'applyNoise',  true);

    if ~enabled
        noisySignal = signal;
        noiseInfo = struct('applied', false, 'reason', 'disabled by params.applyNoise');
        return;
    end

    % ---------------------------------------------------------------------
    % Work out the required noise power
    %
    % SNR in dB is 10*log10(signalPower / noisePower), so
    %   noisePower = signalPower / 10^(SNR/10)
    %
    % Signal power is the mean square of the waveform, which for a current
    % waveform is the square of its RMS value.
    % ---------------------------------------------------------------------
    signalPower = mean(signal.^2);

    if signalPower < eps
        % A silent input has no meaningful SNR. Rather than divide by zero
        % or return a bare signal, add a small fixed noise floor so that
        % downstream stages still see a realistic measurement.
        noisePower = 1e-12;
        warning('addGaussianNoise:silentInput', ...
            'Input signal power is effectively zero; applying a fixed noise floor instead of a relative SNR.');
    else
        noisePower = signalPower / (10^(snr_dB / 10));
    end

    noiseSigma = sqrt(noisePower);

    % ---------------------------------------------------------------------
    % Generate reproducible noise
    %
    % The previous random-number state is saved and restored so that calling
    % this function does not disturb any randomness the caller relies on.
    % ---------------------------------------------------------------------
    previousState = rng;
    rng(seed, 'twister');

    noise = noiseSigma * randn(N, 1);

    rng(previousState);

    noisySignal = signal + noise;

    % ---------------------------------------------------------------------
    % Report metadata, including the SNR actually achieved
    % ---------------------------------------------------------------------
    achievedNoisePower = mean(noise.^2);

    if achievedNoisePower > 0 && signalPower > 0
        achievedSNR = 10 * log10(signalPower / achievedNoisePower);
    else
        achievedSNR = Inf;
    end

    noiseInfo = struct();
    noiseInfo.applied = true;
    noiseInfo.targetSNR_dB = snr_dB;
    noiseInfo.achievedSNR_dB = achievedSNR;
    noiseInfo.signalPower = signalPower;
    noiseInfo.signalRMS_A = sqrt(signalPower);
    noiseInfo.noiseSigma_A = noiseSigma;
    noiseInfo.noiseRMS_A = sqrt(achievedNoisePower);
    noiseInfo.randomSeed = seed;
    noiseInfo.distribution = 'white Gaussian, zero mean';

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
