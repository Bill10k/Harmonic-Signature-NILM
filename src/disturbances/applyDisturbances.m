function disturbedSignal = applyDisturbances(signal, params)
%APPLYDISTURBANCES Applies all disturbance models in sequence.
%
% INPUTS:
%   signal - Clean aggregate current signal
%   params - Project parameters
%
% OUTPUT:
%   disturbedSignal - Signal after all disturbances

    disturbedSignal = signal;

    % Apply voltage sag
    disturbedSignal = applyVoltageSag(disturbedSignal, params);

    % Apply harmonic distortion
    disturbedSignal = addHarmonicDistortion(disturbedSignal, params);

    % Apply supply interruption
    disturbedSignal = applyInterruption(disturbedSignal, params);

    % Add Gaussian noise
    disturbedSignal = addGaussianNoise(disturbedSignal, params);

end