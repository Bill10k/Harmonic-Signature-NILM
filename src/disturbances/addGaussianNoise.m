function signal = addGaussianNoise(signal, params)
%ADDGAUSSIANNOISE Adds additive white Gaussian system noise.
%
%   signal = addGaussianNoise(signal, params)
%
% Adds noise sized relative to the signal's own power via a target SNR
% in dB. Uses a FIXED random seed by default so results are reproducible
% across runs -- the submission checklist requires the course team to be
% able to rerun the analysis independently and get the same numbers.
% The previous global random state is saved and restored afterwards, so
% calling this does not disturb random behaviour elsewhere in the
% pipeline.
%
% PARAMS FIELDS USED (all optional, defaults shown):
%   params.noise.enable   (default: true)
%   params.noise.snrDb    target SNR in dB (default: 30)
%   params.noise.seed     RNG seed for reproducibility (default: 20897245)
%
    signal = signal(:);   % enforce column vector

    cfg = getFieldOrDefault(params, 'noise', struct());

    enable = getFieldOrDefault(cfg, 'enable', true);
    snrDb  = getFieldOrDefault(cfg, 'snrDb',  30);
    seed   = getFieldOrDefault(cfg, 'seed',   20897245);

    if ~enable
        return;
    end

    N = length(signal);

    signalPower = mean(signal.^2);
    snrLinear = 10^(snrDb / 10);
    noisePower = signalPower / snrLinear;

    % Save current RNG state, seed deterministically, generate noise,
    % then restore -- so this call doesn't affect random behaviour
    % elsewhere in the pipeline (e.g. train/test splits).
    previousState = rng;
    rng(seed);
    noiseSignal = sqrt(noisePower) * randn(N, 1);
    rng(previousState);

    signal = signal + noiseSignal;
end


function val = getFieldOrDefault(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = defaultVal;
    end
end
