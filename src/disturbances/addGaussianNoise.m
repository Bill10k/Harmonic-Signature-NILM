function signal = addGaussianNoise(signal, params)
%ADDGAUSSIANNOISE Adds additive white Gaussian system noise.
%
%   signal = addGaussianNoise(signal, params)
%
% Adds noise sized relative to the signal's own power via a target
% signal-to-noise ratio (SNR) in dB, rather than a fixed absolute noise
% level, so the noise scales sensibly whatever the aggregate current
% amplitude turns out to be.
%
% PARAMS FIELDS USED (all optional, defaults shown):
%   params.noise.enable   (default: true)
%   params.noise.snrDb    target SNR in dB (default: 30, moderate
%                         background noise placeholder)
%
% NOTE: Update the default SNR once the group's assigned Supply
% Disturbance Profile (noise level) is available.
%

    cfg = getFieldOrDefault(params, 'noise', struct());

    enable = getFieldOrDefault(cfg, 'enable', true);
    snrDb  = getFieldOrDefault(cfg, 'snrDb',  30);

    if ~enable
        return;
    end

    N = length(signal);

    signalPower = mean(signal.^2);
    snrLinear = 10^(snrDb / 10);
    noisePower = signalPower / snrLinear;

    noiseSignal = sqrt(noisePower) * randn(N, 1);

    signal = signal + noiseSignal;
end


function val = getFieldOrDefault(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = defaultVal;
    end
end
